/// Gender of the user being recorded.
enum Gender {
  male('m'),
  female('f');

  const Gender(this.code);

  /// Value sent to the Soundable Health server.
  final String code;
}

/// User information attached to a recording.
class SoundableUser {
  const SoundableUser({
    required this.id,
    required this.gender,
    required this.clinic,
  });

  /// User's de-identified ID.
  final String id;

  final Gender gender;

  /// Clinic name or company name.
  final String clinic;

  Map<String, Object> toMap() => {
    'id': id,
    'gender': gender.code,
    'clinic': clinic,
  };
}

/// Recording state of the SDK.
enum SoundableProudpState {
  /// Not recording and not waiting for an analysis result.
  idle,

  /// Recording audio.
  recording,

  /// Recording is finished. The file is being uploaded and analyzed.
  analyzing,
}

/// Analysis result received from the Soundable Health server.
class AnalysisResult {
  const AnalysisResult({
    required this.result,
    required this.qmax,
    required this.volume,
    required this.recordDate,
    required this.flowList,
    required this.available,
    required this.url,
  });

  factory AnalysisResult.fromMap(Map<Object?, Object?> map) {
    final flowList = map['flow_list'];
    return AnalysisResult(
      result: _string(map['result']),
      qmax: _string(map['qmax']),
      volume: _string(map['volume']),
      recordDate: _string(map['record_date']),
      flowList: flowList is List
          ? flowList.map(_string).toList(growable: false)
          : const [],
      available: _bool(map['available']),
      url: _string(map['url']),
    );
  }

  final String result;
  final String qmax;
  final String volume;
  final String recordDate;
  final List<String> flowList;
  final bool available;
  final String url;

  Map<String, Object> toMap() => {
    'result': result,
    'qmax': qmax,
    'volume': volume,
    'record_date': recordDate,
    'flow_list': flowList,
    'available': available,
    'url': url,
  };

  @override
  String toString() =>
      'AnalysisResult(result: $result, qmax: $qmax, volume: $volume, '
      'recordDate: $recordDate, flowList: $flowList, available: $available, '
      'url: $url)';

  static String _string(Object? value) => value?.toString() ?? '';

  static bool _bool(Object? value) => switch (value) {
    bool b => b,
    num n => n != 0,
    String s => s.toLowerCase() == 'true' || s == '1',
    _ => false,
  };
}

/// Error thrown by the SDK. [code] is one of the constants below.
class SoundableProudpException implements Exception {
  const SoundableProudpException(this.code, this.message);

  /// [SoundableProudp.init] was not called.
  static const notInitialized = 'not_initialized';

  /// Microphone permission is not granted.
  static const permissionDenied = 'permission_denied';

  /// [SoundableProudp.start] was called while recording.
  static const alreadyRecording = 'already_recording';

  /// [SoundableProudp.start] was called while the previous recording is being analyzed.
  static const analyzing = 'analyzing';

  /// [SoundableProudp.stop] was called while not recording.
  static const notRecording = 'not_recording';

  /// Recording could not be started.
  static const startFailed = 'start_failed';

  /// Upload or analysis failed.
  static const analysisFailed = 'analysis_failed';

  /// No analysis result was received in time.
  static const timeout = 'timeout';

  /// The analysis was cancelled by [SoundableProudp.cancel].
  static const cancelled = 'cancelled';

  /// Invalid argument passed to the SDK.
  static const invalidArgument = 'invalid_argument';

  final String code;
  final String message;

  @override
  String toString() => 'SoundableProudpException($code): $message';
}
