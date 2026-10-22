// Runs on a device or simulator: flutter test integration_test
//
// Recording tests run only when the microphone permission is granted, e.g.
//   Android: adb shell pm grant health.soundable.soundable_proudp_example android.permission.RECORD_AUDIO
//   iOS simulator: xcrun simctl privacy booted grant microphone health.soundable.soundableProudpExample

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:soundable_proudp/soundable_proudp.dart';

const _user = SoundableUser(
  id: 'integrationTest',
  gender: Gender.male,
  clinic: 'soundable',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native plugin is registered', (WidgetTester tester) async {
    expect(await SoundableProudp.hasPermission(), isA<bool>());
  });

  testWidgets('init validates arguments', (WidgetTester tester) async {
    await expectLater(
      SoundableProudp.init(apiKey: '', serverUrl: '', socketUrl: ''),
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          SoundableProudpException.invalidArgument,
        ),
      ),
    );
    // Nothing listens on this port, so uploads fail.
    await SoundableProudp.init(
      apiKey: 'key',
      serverUrl: 'http://127.0.0.1:9/',
      socketUrl: 'ws://127.0.0.1:9',
    );
  });

  testWidgets('stop while idle throws not_recording', (
    WidgetTester tester,
  ) async {
    await expectLater(
      SoundableProudp.stop(),
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          SoundableProudpException.notRecording,
        ),
      ),
    );
  });

  testWidgets('start reports recording time and cancel resets state', (
    WidgetTester tester,
  ) async {
    if (!await SoundableProudp.hasPermission()) {
      markTestSkipped('Microphone permission is not granted.');
      return;
    }
    final ticks = <int>[];
    final secondTick = Completer<void>();
    await SoundableProudp.start(
      user: _user,
      onRecording: (seconds) {
        ticks.add(seconds);
        if (ticks.length == 2 && !secondTick.isCompleted) secondTick.complete();
      },
    );
    expect(SoundableProudp.state, SoundableProudpState.recording);
    await expectLater(
      SoundableProudp.start(user: _user),
      throwsA(
        isA<SoundableProudpException>().having(
          (e) => e.code,
          'code',
          SoundableProudpException.alreadyRecording,
        ),
      ),
    );

    await secondTick.future.timeout(const Duration(seconds: 5));
    await SoundableProudp.cancel();

    expect(SoundableProudp.state, SoundableProudpState.idle);
    expect(ticks.first, greaterThan(0));
  });

  testWidgets(
    'stop reports upload failure',
    (WidgetTester tester) async {
      if (!await SoundableProudp.hasPermission()) {
        markTestSkipped('Microphone permission is not granted.');
        return;
      }
      await SoundableProudp.start(user: _user);
      await Future<void>.delayed(const Duration(seconds: 2));

      await expectLater(
        SoundableProudp.stop().timeout(const Duration(seconds: 60)),
        throwsA(
          isA<SoundableProudpException>().having(
            (e) => e.code,
            'code',
            SoundableProudpException.analysisFailed,
          ),
        ),
      );
      expect(SoundableProudp.state, SoundableProudpState.idle);
    },
    // SoundableProudpLib (iOS) does not report upload failures; the plugin
    // reports a timeout after 150 seconds instead.
    skip: Platform.isIOS,
  );
}
