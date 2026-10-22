import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Entry point of the Soundable Health proudP SDK.
///
/// Android wraps `io.github.soundablehealth:sdk` and iOS wraps
/// `SoundableProudpLib`, so recording, upload and analysis are done by the
/// native SDKs.
class SoundableProudp {
  SoundableProudp._();

  /// Recording is stopped automatically and analyzed after about this many seconds.
  static const int maxRecordingSeconds = 180;

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('soundable_proudp');

  static bool _handlerRegistered = false;
  static SoundableProudpState _state = SoundableProudpState.idle;

  static void Function(int seconds)? _onRecording;
  static void Function()? _onAutoStop;
  static void Function()? _onCallInterrupted;

  // Analysis of the current or last recording. Kept until it is returned by
  // stop() so that a result of an auto stopped recording is not lost.
  static Completer<AnalysisResult>? _analysis;
  static bool _analysisClaimed = false;

  /// Current recording state.
  static SoundableProudpState get state => _state;

  static bool get isRecording => _state == SoundableProudpState.recording;

  static bool get isAnalyzing => _state == SoundableProudpState.analyzing;

  /// Sets the Soundable Health server configuration.
  ///
  /// Contact dev@soundable.health to get these keys.
  static Future<void> init({
    required String apiKey,
    required String serverUrl,
    required String socketUrl,
  }) {
    return _invoke<void>('init', {
      'apiKey': apiKey,
      // Both native SDKs append the API path to serverUrl.
      'serverUrl': serverUrl.isEmpty || serverUrl.endsWith('/')
          ? serverUrl
          : '$serverUrl/',
      'socketUrl': socketUrl,
    });
  }

  /// Whether the microphone permission is granted.
  static Future<bool> hasPermission() async =>
      await _invoke<bool>('hasPermission') ?? false;

  /// Requests the microphone permission and returns whether it is granted.
  static Future<bool> requestPermission() async =>
      await _invoke<bool>('requestPermission') ?? false;

  /// Starts recording.
  ///
  /// - [onRecording] is called every second with the elapsed recording time.
  /// - [onAutoStop] is called when the recording reached
  ///   [maxRecordingSeconds] and was stopped automatically. The recording is
  ///   analyzed and the result can be received by calling [stop].
  /// - [onCallInterrupted] is called when the recording was cancelled by an
  ///   incoming call. The recorded file is deleted.
  ///
  /// Throws [SoundableProudpException] if recording could not be started.
  static Future<void> start({
    required SoundableUser user,
    void Function(int seconds)? onRecording,
    void Function()? onAutoStop,
    void Function()? onCallInterrupted,
  }) async {
    switch (_state) {
      case SoundableProudpState.recording:
        throw const SoundableProudpException(
          SoundableProudpException.alreadyRecording,
          'Already recording.',
        );
      case SoundableProudpState.analyzing:
        throw const SoundableProudpException(
          SoundableProudpException.analyzing,
          'Analyzing. Please wait a moment.',
        );
      case SoundableProudpState.idle:
        break;
    }

    _analysis = null;
    _onRecording = onRecording;
    _onAutoStop = onAutoStop;
    _onCallInterrupted = onCallInterrupted;
    // Set before invoking so that events sent right after the native start are not dropped.
    _state = SoundableProudpState.recording;
    try {
      await _invoke<void>('start', user.toMap());
    } catch (_) {
      _reset();
      rethrow;
    }
  }

  /// Stops recording, uploads the recorded file and returns the analysis result.
  ///
  /// If the recording was already stopped by [onAutoStop] in [start], returns
  /// the result of that recording.
  ///
  /// Throws [SoundableProudpException] if upload or analysis failed.
  static Future<AnalysisResult> stop() async {
    switch (_state) {
      case SoundableProudpState.recording:
        final analysis = _beginAnalysis();
        _analysisClaimed = true;
        try {
          await _invoke<void>('stop');
        } catch (_) {
          _reset();
          rethrow;
        }
        return analysis.future;
      case SoundableProudpState.analyzing:
        _analysisClaimed = true;
        return _analysis!.future;
      case SoundableProudpState.idle:
        final analysis = _analysis;
        if (analysis != null && !_analysisClaimed) {
          _analysisClaimed = true;
          return analysis.future;
        }
        throw const SoundableProudpException(
          SoundableProudpException.notRecording,
          'Not recording.',
        );
    }
  }

  /// Cancels recording and deletes the recorded file.
  ///
  /// If called while analyzing, the pending [stop] throws
  /// [SoundableProudpException.cancelled] and the result is ignored.
  static Future<void> cancel() async {
    final analysis = _analysis;
    _reset();
    if (analysis != null && !analysis.isCompleted) {
      analysis.completeError(
        const SoundableProudpException(
          SoundableProudpException.cancelled,
          'Cancelled.',
        ),
      );
    }
    _analysis = null;
    await _invoke<void>('cancel');
  }

  static Completer<AnalysisResult> _beginAnalysis() {
    final analysis = Completer<AnalysisResult>();
    // Avoid an unhandled error when nobody calls stop() after an auto stop.
    analysis.future.ignore();
    _analysis = analysis;
    _analysisClaimed = false;
    _state = SoundableProudpState.analyzing;
    return analysis;
  }

  static void _reset() {
    _state = SoundableProudpState.idle;
    _onRecording = null;
    _onAutoStop = null;
    _onCallInterrupted = null;
  }

  static Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onRecording':
        if (_state == SoundableProudpState.recording) {
          _onRecording?.call(call.arguments as int);
        }
      case 'onAutoStop':
        if (_state == SoundableProudpState.recording) {
          final onAutoStop = _onAutoStop;
          _beginAnalysis();
          onAutoStop?.call();
        }
      case 'onResult':
        if (_state == SoundableProudpState.analyzing) {
          final analysis = _analysis!;
          _reset();
          analysis.complete(
            AnalysisResult.fromMap(call.arguments as Map<Object?, Object?>),
          );
        }
      case 'onError':
        if (_state != SoundableProudpState.idle) {
          final args = call.arguments as Map<Object?, Object?>;
          final error = SoundableProudpException(
            args['code'] as String? ?? SoundableProudpException.analysisFailed,
            args['message'] as String? ?? 'Unknown error.',
          );
          // An error while recording is reported by the next stop().
          final analysis = _state == SoundableProudpState.analyzing
              ? _analysis!
              : _beginAnalysis();
          _reset();
          analysis.completeError(error);
        }
      case 'onCallInterrupted':
        if (_state == SoundableProudpState.recording) {
          final onCallInterrupted = _onCallInterrupted;
          _reset();
          onCallInterrupted?.call();
        }
    }
  }

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_handlerRegistered) {
      channel.setMethodCallHandler(_handleNativeCall);
      _handlerRegistered = true;
    }
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw SoundableProudpException(e.code, e.message ?? e.code);
    }
  }

  @visibleForTesting
  static void debugReset() {
    _reset();
    _analysis = null;
    _analysisClaimed = false;
    _handlerRegistered = false;
  }
}
