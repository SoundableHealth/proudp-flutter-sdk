import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundable_proudp/soundable_proudp.dart';

const _user = SoundableUser(
  id: 'user',
  gender: Gender.female,
  clinic: 'clinic',
);

const _resultMap = <String, Object>{
  'result': 'normal',
  'qmax': '20.1',
  'volume': '300',
  'record_date': '2026-10-15 10:00:00',
  'flow_list': ['0.0', '1.2'],
  'available': true,
  'url': 'https://example.com/result',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  PlatformException? nativeError;

  // Sends a call from the native side to Dart.
  Future<void> sendFromNative(String method, [Object? arguments]) async {
    final data = SoundableProudp.channel.codec.encodeMethodCall(
      MethodCall(method, arguments),
    );
    await messenger.handlePlatformMessage(
      SoundableProudp.channel.name,
      data,
      (_) {},
    );
  }

  setUp(() {
    SoundableProudp.debugReset();
    calls = [];
    nativeError = null;
    messenger.setMockMethodCallHandler(SoundableProudp.channel, (call) async {
      calls.add(call);
      if (nativeError != null) throw nativeError!;
      return switch (call.method) {
        'hasPermission' || 'requestPermission' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SoundableProudp.channel, null);
  });

  test('init sends server configuration', () async {
    await SoundableProudp.init(
      apiKey: 'key',
      serverUrl: 'https://server/',
      socketUrl: 'wss://socket',
    );

    expect(calls.single.method, 'init');
    expect(calls.single.arguments, {
      'apiKey': 'key',
      'serverUrl': 'https://server/',
      'socketUrl': 'wss://socket',
    });
  });

  test('init appends a trailing slash to serverUrl', () async {
    await SoundableProudp.init(
      apiKey: 'key',
      serverUrl: 'https://server/api',
      socketUrl: 'wss://socket',
    );

    expect((calls.single.arguments as Map)['serverUrl'], 'https://server/api/');
  });

  test('permission helpers return native value', () async {
    expect(await SoundableProudp.hasPermission(), isTrue);
    expect(await SoundableProudp.requestPermission(), isTrue);
  });

  test('start, recording ticks, stop and result', () async {
    final ticks = <int>[];
    await SoundableProudp.start(user: _user, onRecording: ticks.add);

    expect(calls.last.method, 'start');
    expect(calls.last.arguments, {
      'id': 'user',
      'gender': 'f',
      'clinic': 'clinic',
    });
    expect(SoundableProudp.state, SoundableProudpState.recording);

    await sendFromNative('onRecording', 1);
    await sendFromNative('onRecording', 2);
    expect(ticks, [1, 2]);

    final future = SoundableProudp.stop();
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'stop');
    expect(SoundableProudp.state, SoundableProudpState.analyzing);

    await sendFromNative('onResult', _resultMap);
    final result = await future;
    expect(result.result, 'normal');
    expect(result.qmax, '20.1');
    expect(result.recordDate, '2026-10-15 10:00:00');
    expect(result.flowList, ['0.0', '1.2']);
    expect(result.available, isTrue);
    expect(SoundableProudp.state, SoundableProudpState.idle);
  });

  test('analysis error is thrown by stop', () async {
    await SoundableProudp.start(user: _user);
    final future = SoundableProudp.stop();
    await sendFromNative('onError', {
      'code': SoundableProudpException.analysisFailed,
      'message': 'upload failed',
    });

    await expectLater(
      future,
      throwsA(
        isA<SoundableProudpException>()
            .having((e) => e.code, 'code', 'analysis_failed')
            .having((e) => e.message, 'message', 'upload failed'),
      ),
    );
    expect(SoundableProudp.state, SoundableProudpState.idle);
  });

  test('auto stop result can be received by stop afterwards', () async {
    var autoStopped = false;
    await SoundableProudp.start(
      user: _user,
      onAutoStop: () => autoStopped = true,
    );

    await sendFromNative('onAutoStop');
    expect(autoStopped, isTrue);
    expect(SoundableProudp.state, SoundableProudpState.analyzing);

    await sendFromNative('onResult', _resultMap);
    expect(SoundableProudp.state, SoundableProudpState.idle);

    final result = await SoundableProudp.stop();
    expect(result.result, 'normal');
    // The result is returned only once.
    expect(
      SoundableProudp.stop,
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          'not_recording',
        ),
      ),
    );
    expect(calls.where((c) => c.method == 'stop'), isEmpty);
  });

  test('cancel while analyzing completes stop with cancelled', () async {
    await SoundableProudp.start(user: _user);
    final future = SoundableProudp.stop();
    await SoundableProudp.cancel();

    await expectLater(
      future,
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        ),
      ),
    );
    expect(calls.last.method, 'cancel');

    // A late result of the cancelled recording is ignored.
    await sendFromNative('onResult', _resultMap);
    expect(SoundableProudp.state, SoundableProudpState.idle);
  });

  test('call interrupt resets state and calls callback', () async {
    var interrupted = false;
    final ticks = <int>[];
    await SoundableProudp.start(
      user: _user,
      onRecording: ticks.add,
      onCallInterrupted: () => interrupted = true,
    );

    await sendFromNative('onCallInterrupted');
    await sendFromNative('onRecording', 3);

    expect(interrupted, isTrue);
    expect(ticks, isEmpty);
    expect(SoundableProudp.state, SoundableProudpState.idle);
  });

  test('start throws while recording or analyzing', () async {
    await SoundableProudp.start(user: _user);
    await expectLater(
      SoundableProudp.start(user: _user),
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          'already_recording',
        ),
      ),
    );

    SoundableProudp.stop().ignore();
    await expectLater(
      SoundableProudp.start(user: _user),
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          'analyzing',
        ),
      ),
    );
  });

  test('native start error is converted and state is reset', () async {
    nativeError = PlatformException(
      code: SoundableProudpException.permissionDenied,
      message: 'RECORD_AUDIO permission is not granted.',
    );

    await expectLater(
      SoundableProudp.start(user: _user),
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          'permission_denied',
        ),
      ),
    );
    expect(SoundableProudp.state, SoundableProudpState.idle);
  });

  test('AnalysisResult.fromMap accepts numbers and missing values', () {
    final result = AnalysisResult.fromMap({
      'result': 'normal',
      'qmax': 20.5,
      'volume': 300,
      'record_date': '2026-10-15',
      'flow_list': [0, 1.5],
      'available': 1,
    });

    expect(result.qmax, '20.5');
    expect(result.volume, '300');
    expect(result.flowList, ['0', '1.5']);
    expect(result.available, isTrue);
    expect(result.url, '');
  });
}
