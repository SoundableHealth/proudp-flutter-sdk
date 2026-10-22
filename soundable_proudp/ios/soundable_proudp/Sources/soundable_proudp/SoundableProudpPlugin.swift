import AVFoundation
import Flutter
import UIKit

// With CocoaPods, SoundableProudpLib is compiled into this module (see ios/Classes/SoundableProudpLib).
#if canImport(SoundableProudpLib)
  import SoundableProudpLib
#endif

/// Bridges SoundableProudpLib to Flutter.
public class SoundableProudpPlugin: NSObject, FlutterPlugin, SoundableProudpLibDelegate {
  private enum State {
    case idle, recording, analyzing
  }

  // SoundableProudpLib stops by itself on its 180th timer tick (about 179 seconds after start).
  private static let autoStopSeconds = 179
  // SoundableProudpLib does not report upload failures, so stop waiting for the result after this.
  private static let analysisTimeout: TimeInterval = 150
  private static let resultNotification = Notification.Name("SoundableProudpLib")

  private let channel: FlutterMethodChannel
  private let lib = SoundableProudpLib()
  private var initialized = false
  private var state = State.idle
  private var elapsedSeconds = 0
  private var recordTimer: Timer?
  private var timeoutWorkItem: DispatchWorkItem?
  private var resultObserver: NSObjectProtocol?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    lib.delegate = self
    resultObserver = NotificationCenter.default.addObserver(
      forName: Self.resultNotification, object: nil, queue: .main
    ) { [weak self] notification in
      self?.onResultNotification(notification)
    }
  }

  deinit {
    if let resultObserver {
      NotificationCenter.default.removeObserver(resultObserver)
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "soundable_proudp", binaryMessenger: registrar.messenger())
    let instance = SoundableProudpPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    if state != .idle {
      resetToIdle()
      lib.cancelRecording()
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "init":
      initialize(args, result: result)
    case "hasPermission":
      result(hasPermission())
    case "requestPermission":
      requestPermission(result: result)
    case "start":
      start(args, result: result)
    case "stop":
      stop(result: result)
    case "cancel":
      resetToIdle()
      lib.cancelRecording()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ args: [String: Any], result: FlutterResult) {
    guard let apiKey = args["apiKey"] as? String, !apiKey.isEmpty,
      let serverUrl = args["serverUrl"] as? String, !serverUrl.isEmpty,
      let socketUrl = args["socketUrl"] as? String, !socketUrl.isEmpty
    else {
      result(error("invalid_argument", "apiKey, serverUrl and socketUrl are required."))
      return
    }
    lib.setServerConfig(serverUrl: serverUrl, apiKey: apiKey, websocketUrl: socketUrl)
    initialized = true
    result(nil)
  }

  private func hasPermission() -> Bool {
    if #available(iOS 17.0, *) {
      return AVAudioApplication.shared.recordPermission == .granted
    }
    return AVAudioSession.sharedInstance().recordPermission == .granted
  }

  private func requestPermission(result: @escaping FlutterResult) {
    let completion: (Bool) -> Void = { granted in
      DispatchQueue.main.async { result(granted) }
    }
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: completion)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(completion)
    }
  }

  private func start(_ args: [String: Any], result: FlutterResult) {
    guard initialized else {
      result(error("not_initialized", "Please call init() first."))
      return
    }
    guard hasPermission() else {
      result(error("permission_denied", "Microphone permission is not granted."))
      return
    }
    switch state {
    case .recording:
      result(error("already_recording", "Already recording."))
      return
    case .analyzing:
      result(error("analyzing", "Analyzing. Please wait a moment."))
      return
    case .idle:
      break
    }

    // Configures the audio session for recording. Permission is already granted here.
    lib.checkPermission()
    lib.startRecording(
      userId: args["id"] as? String ?? "",
      gender: args["gender"] as? String ?? "m",
      clinic: args["clinic"] as? String ?? ""
    )
    state = .recording
    elapsedSeconds = 0
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      self?.onRecordTimerTick()
    }
    RunLoop.main.add(timer, forMode: .common)
    recordTimer = timer
    result(nil)
  }

  private func stop(result: FlutterResult) {
    guard state == .recording else {
      result(error("not_recording", "Not recording."))
      return
    }
    beginAnalysis()
    result(nil)
  }

  private func onRecordTimerTick() {
    guard state == .recording else { return }
    elapsedSeconds += 1
    channel.invokeMethod("onRecording", arguments: elapsedSeconds)
    if elapsedSeconds >= Self.autoStopSeconds {
      beginAnalysis()
      channel.invokeMethod("onAutoStop", arguments: nil)
    }
  }

  private func beginAnalysis() {
    stopRecordTimer()
    state = .analyzing
    // The result is posted as a "SoundableProudpLib" notification.
    lib.stopRecording()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.state == .analyzing else { return }
      self.resetToIdle()
      self.sendError("timeout", "No analysis result was received in time.")
    }
    timeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.analysisTimeout, execute: workItem)
  }

  private func onResultNotification(_ notification: Notification) {
    guard state == .analyzing else { return }
    resetToIdle()

    let message = notification.userInfo?["result"] as? String ?? ""
    if let data = message.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      json["result"] != nil
    {
      channel.invokeMethod("onResult", arguments: json)
    } else {
      // Upload, socket and server errors are delivered as plain messages.
      sendError("analysis_failed", message.isEmpty ? "Analysis failed." : message)
    }
  }

  public func recordingDidCancelDueToCallInterrupt() {
    // SoundableProudpLib has already cancelled the recording and deleted the file.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.state == .recording else { return }
      self.resetToIdle()
      self.channel.invokeMethod("onCallInterrupted", arguments: nil)
    }
  }

  private func resetToIdle() {
    stopRecordTimer()
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    state = .idle
  }

  private func stopRecordTimer() {
    recordTimer?.invalidate()
    recordTimer = nil
  }

  private func sendError(_ code: String, _ message: String) {
    channel.invokeMethod("onError", arguments: ["code": code, "message": message])
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
