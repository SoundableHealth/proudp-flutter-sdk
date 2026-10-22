package health.soundable.soundable_proudp

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.soundable.health.sdk.api.SoundableHealth
import com.soundable.health.sdk.model.AnalysisResult
import com.soundable.health.sdk.model.Gender
import com.soundable.health.sdk.model.User
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** Bridges the Soundable Health Android SDK (io.github.soundablehealth:sdk) to Flutter. */
class SoundableProudpPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private enum class State { IDLE, RECORDING, ANALYZING }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: Result? = null

    private var initialized = false
    private var state = State.IDLE

    // Increased on every start/cancel so that callbacks of a previous recording are ignored.
    private var session = 0

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        if (state != State.IDLE) {
            session++
            state = State.IDLE
            SoundableHealth.cancel()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "init" -> init(call, result)
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "start" -> start(call, result)
            "stop" -> stop(result)
            "cancel" -> cancel(result)
            else -> result.notImplemented()
        }
    }

    private fun init(
        call: MethodCall,
        result: Result
    ) {
        val apiKey = call.argument<String>("apiKey")
        val serverUrl = call.argument<String>("serverUrl")
        val socketUrl = call.argument<String>("socketUrl")
        if (apiKey.isNullOrBlank() || serverUrl.isNullOrBlank() || socketUrl.isNullOrBlank()) {
            result.error(INVALID_ARGUMENT, "apiKey, serverUrl and socketUrl are required.", null)
            return
        }
        SoundableHealth.init(apiKey = apiKey, serverUrl = serverUrl, socketUrl = socketUrl)
        initialized = true
        result.success(null)
    }

    private fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        val activity: Activity? = activityBinding?.activity
        if (activity == null) {
            result.error(NO_ACTIVITY, "Permission can be requested only while an activity is attached.", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(PERMISSION_REQUEST_IN_PROGRESS, "A permission request is already in progress.", null)
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    private fun start(
        call: MethodCall,
        result: Result
    ) {
        when {
            !initialized -> {
                result.error(NOT_INITIALIZED, "Please call init() first.", null)
                return
            }
            !hasPermission() -> {
                result.error(PERMISSION_DENIED, "RECORD_AUDIO permission is not granted.", null)
                return
            }
            state == State.RECORDING -> {
                result.error(ALREADY_RECORDING, "Already recording.", null)
                return
            }
            state == State.ANALYZING -> {
                result.error(ANALYZING, "Analyzing. Please wait a moment.", null)
                return
            }
        }
        val user = User(
            id = call.argument<String>("id").orEmpty(),
            gender = if (call.argument<String>("gender") == "f") Gender.FEMALE else Gender.MALE,
            clinic = call.argument<String>("clinic").orEmpty(),
        )

        val currentSession = ++session
        var startError: String? = null
        state = State.RECORDING
        SoundableHealth.start(
            context = context,
            user = user,
            // The SDK reports start errors synchronously.
            onError = { message -> startError = message },
            onRecording = { seconds -> onRecording(currentSession, seconds) },
            onCallInterrupted = { onCallInterrupted(currentSession) },
        )

        val error = startError
        if (error != null) {
            session++
            state = State.IDLE
            SoundableHealth.cancel()
            result.error(START_FAILED, error, null)
            return
        }
        result.success(null)
    }

    private fun stop(result: Result) {
        if (state != State.RECORDING) {
            result.error(NOT_RECORDING, "Not recording.", null)
            return
        }
        beginAnalysis(session)
        result.success(null)
    }

    private fun cancel(result: Result) {
        session++
        state = State.IDLE
        SoundableHealth.cancel()
        result.success(null)
    }

    private fun onRecording(
        recordingSession: Int,
        seconds: Int
    ) = runOnMain {
        // The SDK also reports 0 when the recording is finished.
        if (recordingSession != session || state != State.RECORDING) return@runOnMain
        channel.invokeMethod("onRecording", seconds)
        // The SDK stops by itself when its 180 second timer finishes, but then the result is
        // delivered only to the callbacks of stop(). Stop here first so that the result is
        // delivered to Flutter.
        if (seconds >= AUTO_STOP_SECONDS) {
            beginAnalysis(recordingSession)
            channel.invokeMethod("onAutoStop", null)
        }
    }

    private fun onCallInterrupted(recordingSession: Int) = runOnMain {
        // The SDK has already cancelled the recording and deleted the file.
        if (recordingSession != session || state != State.RECORDING) return@runOnMain
        session++
        state = State.IDLE
        channel.invokeMethod("onCallInterrupted", null)
    }

    private fun beginAnalysis(recordingSession: Int) {
        state = State.ANALYZING
        SoundableHealth.stop(
            onError = { message ->
                runOnMain { finishAnalysis(recordingSession) { sendError(ANALYSIS_FAILED, message) } }
            },
            onFinish = { analysisResult ->
                runOnMain {
                    finishAnalysis(recordingSession) {
                        // The SDK returns an empty result when no result was received in time.
                        if (analysisResult.result.isEmpty() && analysisResult.record_date.isEmpty()) {
                            sendError(TIMEOUT, "No analysis result was received in time.")
                        } else {
                            channel.invokeMethod("onResult", analysisResult.toMap())
                        }
                    }
                }
            },
        )
    }

    private inline fun finishAnalysis(
        recordingSession: Int,
        send: () -> Unit
    ) {
        if (recordingSession != session || state != State.ANALYZING) return
        state = State.IDLE
        send()
    }

    private fun sendError(
        code: String,
        message: String
    ) {
        channel.invokeMethod("onError", mapOf("code" to code, "message" to message))
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    private fun AnalysisResult.toMap(): Map<String, Any> =
        mapOf(
            "result" to result,
            "qmax" to qmax,
            "volume" to volume,
            "record_date" to record_date,
            "flow_list" to flow_list,
            "available" to available,
            "url" to url,
        )

    companion object {
        private const val CHANNEL = "soundable_proudp"
        private const val PERMISSION_REQUEST_CODE = 0x5D11

        // The SDK's CountDownTimer does not always deliver the 180th tick.
        private const val AUTO_STOP_SECONDS = 179

        private const val NOT_INITIALIZED = "not_initialized"
        private const val PERMISSION_DENIED = "permission_denied"
        private const val ALREADY_RECORDING = "already_recording"
        private const val ANALYZING = "analyzing"
        private const val NOT_RECORDING = "not_recording"
        private const val START_FAILED = "start_failed"
        private const val ANALYSIS_FAILED = "analysis_failed"
        private const val TIMEOUT = "timeout"
        private const val INVALID_ARGUMENT = "invalid_argument"
        private const val NO_ACTIVITY = "no_activity"
        private const val PERMISSION_REQUEST_IN_PROGRESS = "permission_request_in_progress"
    }
}
