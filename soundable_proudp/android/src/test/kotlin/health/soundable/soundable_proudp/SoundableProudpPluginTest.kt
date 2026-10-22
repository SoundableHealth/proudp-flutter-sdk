package health.soundable.soundable_proudp

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.ArgumentMatchers.anyString
import org.mockito.ArgumentMatchers.isNull
import org.mockito.Mockito
import kotlin.test.Test

/*
 * Run from the command line with `./gradlew testDebugUnitTest` in the `example/android/` directory.
 */
internal class SoundableProudpPluginTest {
    @Test
    fun onMethodCall_unknownMethod_returnsNotImplemented() {
        val result = Mockito.mock(MethodChannel.Result::class.java)
        SoundableProudpPlugin().onMethodCall(MethodCall("unknown", null), result)

        Mockito.verify(result).notImplemented()
    }

    @Test
    fun onMethodCall_initWithoutKeys_returnsInvalidArgument() {
        val result = Mockito.mock(MethodChannel.Result::class.java)
        SoundableProudpPlugin().onMethodCall(MethodCall("init", mapOf("apiKey" to "key")), result)

        Mockito.verify(result).error(Mockito.eq("invalid_argument"), anyString(), isNull())
    }

    @Test
    fun onMethodCall_startBeforeInit_returnsNotInitialized() {
        val result = Mockito.mock(MethodChannel.Result::class.java)
        val args = mapOf("id" to "user", "gender" to "m", "clinic" to "clinic")
        SoundableProudpPlugin().onMethodCall(MethodCall("start", args), result)

        Mockito.verify(result).error(Mockito.eq("not_initialized"), anyString(), isNull())
    }

    @Test
    fun onMethodCall_stopWhileIdle_returnsNotRecording() {
        val result = Mockito.mock(MethodChannel.Result::class.java)
        SoundableProudpPlugin().onMethodCall(MethodCall("stop", null), result)

        Mockito.verify(result).error(Mockito.eq("not_recording"), anyString(), isNull())
    }
}
