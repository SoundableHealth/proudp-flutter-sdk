# proudP Flutter SDK usage guide

Flutter plugin for the Soundable Health proudP SDK.
It records voiding sound, uploads the file to the Soundable Health server and returns the analysis result.

The plugin wraps the native SDKs, so recording, upload and analysis work the same as in native apps.

| Platform | Native SDK |
| --- | --- |
| Android | [`io.github.soundablehealth:sdk:1.0.6`](https://github.com/SoundableHealth/proudp-android-sdk-sample) (Maven Central) |
| iOS | [`SoundableProudpLib`](https://github.com/SoundableHealth/SoundableProudpLib) (Swift Package Manager) |

### Repository structure

```
proudp-flutter-sdk/
├── soundable_proudp/   # Flutter SDK (plugin package)
└── example/            # Sample app
```

### Requirements

- Flutter 3.47 or later (tested with Flutter 3.47.7)
- Android: minSdk 28 or later (tested with Android Gradle Plugin 9.1.0, Kotlin 2.4.0)
- iOS: 15.0 or later

---

### 1. Add the soundable_proudp package

Add the dependency to the `pubspec.yaml` of your app.

```yaml
dependencies:
  soundable_proudp:
    git:
      url: https://github.com/SoundableHealth/proudp-flutter-sdk.git
      path: soundable_proudp
      ref: main # or a release tag
```

Then run `flutter pub get`.

### 2. Android setup

1. Set `minSdk` to 28 or later in `android/app/build.gradle.kts`.

```kotlin
android {
    defaultConfig {
        minSdk = 28
    }
}
```

2. `mavenCentral()` must be in your repositories (it is included in the default Flutter project).
3. `RECORD_AUDIO`, `INTERNET` and `ACCESS_NETWORK_STATE` permissions are added to your manifest automatically.

### 3. iOS setup

1. Add "Privacy - Microphone Usage Description" (`NSMicrophoneUsageDescription`) to `ios/Runner/Info.plist`.

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone is used to record voiding sound for analysis.</string>
```

2. Set `version` in your `pubspec.yaml` (e.g. `version: 1.0.0+1`). The app version is included in the recorded file name.
3. Both Swift Package Manager (Flutter default) and CocoaPods are supported. No additional setup is needed.
   - With Swift Package Manager, `SoundableProudpLib` is downloaded from GitHub.
   - With CocoaPods, a copy of `SoundableProudpLib` included in the plugin is used.

### 4. Initialize SDK

- Set 3 server keys to connect to the Soundable Health server.
- Please contact dev@soundable.health to get these keys.

```dart
import 'package:soundable_proudp/soundable_proudp.dart';

await SoundableProudp.init(
  apiKey: 'SERVER_API_KEY',
  serverUrl: 'SERVER_URL',
  socketUrl: 'WEBSOCKET_URL',
);
```

### 5. Check microphone permission

- Audio recording permission is required before recording.
- `requestPermission()` shows the system permission dialog if needed and returns whether the permission is granted.

```dart
final bool granted = await SoundableProudp.requestPermission();

// Check only, without showing the dialog
final bool hasPermission = await SoundableProudp.hasPermission();
```

### 6. Start recording

- Enter 3 key values before recording
    - id: user's de-identified ID
    - gender: `Gender.male` or `Gender.female`
    - clinic: clinic name or company name
- Recording is stopped automatically after 3 minutes (`SoundableProudp.maxRecordingSeconds`).

```dart
try {
  await SoundableProudp.start(
    user: const SoundableUser(
      id: 'USER_ID',
      gender: Gender.male,
      clinic: 'CLINIC_NAME',
    ),
    onRecording: (int seconds) {
      // TODO, record time callback (called every second)
    },
    onAutoStop: () {
      // TODO, max recording time reached. Recording is stopped and analysis is started.
      //  Call SoundableProudp.stop() to receive the result.
    },
    onCallInterrupted: () {
      // TODO, recording was cancelled due to an incoming call.
      //  Close recording UI, show an alert to the user, etc.
    },
  );
} on SoundableProudpException catch (e) {
  // TODO, handle recording error (e.code, e.message)
}
```

### 7. Cancel recording

- Cancel recording and delete the recorded file.
- If called while analyzing, the pending `stop()` throws `SoundableProudpException` with code `cancelled`.

```dart
await SoundableProudp.cancel();
```

### 8. Stop recording and get result

- Finish recording and upload the recording file to the server.
- The analysis result is returned when the analysis is finished.
- If the recording was already stopped automatically (`onAutoStop`), `stop()` returns the result of that recording.

```dart
try {
  final AnalysisResult result = await SoundableProudp.stop();
  // TODO, handle the received result
  print(result.result);
  print(result.qmax);
  print(result.volume);
  print(result.recordDate);
  print(result.flowList);
  print(result.available);
  print(result.url);
} on SoundableProudpException catch (e) {
  // TODO, handle error (upload failure, timeout, etc.)
}
```

`AnalysisResult` fields

| Field | Type | Server key |
| --- | --- | --- |
| `result` | `String` | `result` |
| `qmax` | `String` | `qmax` |
| `volume` | `String` | `volume` |
| `recordDate` | `String` | `record_date` |
| `flowList` | `List<String>` | `flow_list` |
| `available` | `bool` | `available` |
| `url` | `String` | `url` |

### 9. Recording state

```dart
SoundableProudp.state;       // SoundableProudpState.idle / recording / analyzing
SoundableProudp.isRecording;
SoundableProudp.isAnalyzing;
```

### 10. Handling app lifecycle

- Recording in the background is not supported.
- We recommend cancelling the recording when the app goes to the background.

```dart
final listener = AppLifecycleListener(
  onHide: () {
    if (SoundableProudp.isRecording) SoundableProudp.cancel();
  },
);
```

### 11. Error codes

All errors are thrown as `SoundableProudpException` with `code` and `message`.

| Code | Description |
| --- | --- |
| `invalid_argument` | `init()` was called with an empty key |
| `not_initialized` | `start()` was called before `init()` |
| `permission_denied` | Microphone permission is not granted |
| `already_recording` | `start()` was called while recording |
| `analyzing` | `start()` was called while the previous recording is being analyzed |
| `not_recording` | `stop()` was called while not recording |
| `start_failed` | Recording could not be started |
| `analysis_failed` | Upload or analysis failed |
| `timeout` | No analysis result was received in time |
| `cancelled` | The analysis was cancelled by `cancel()` |

---

### Sample app

[`example/`](example) shows how to use the SDK (record, stop, cancel, show result).

1. Contact dev@soundable.health to get the server configuration keys.
2. Set the keys in `example/lib/constants.dart`, or pass them when running the app.

```sh
cd example
flutter run \
  --dart-define=SOUNDABLE_API_KEY=SERVER_API_KEY \
  --dart-define=SOUNDABLE_SERVER_URL=SERVER_URL \
  --dart-define=SOUNDABLE_SOCKET_URL=WEBSOCKET_URL
```

### Tests

```sh
# Dart unit tests
cd soundable_proudp && flutter test

# Android native unit tests (build the example once first)
cd example/android && ./gradlew :soundable_proudp:testDebugUnitTest

# Integration tests on a device or simulator
# Recording tests run only when the microphone permission is granted:
#   adb shell pm grant health.soundable.soundable_proudp_example android.permission.RECORD_AUDIO
#   xcrun simctl privacy booted grant microphone health.soundable.soundableProudpExample
cd example && flutter test integration_test
```

### Updating native SDKs (for maintainers)

- Android: change the version of `io.github.soundablehealth:sdk` in `soundable_proudp/android/build.gradle.kts`.
- iOS:
  1. Change the `SoundableProudpLib` revision in `soundable_proudp/ios/soundable_proudp/Package.swift`.
  2. Copy the source files of the same revision to `soundable_proudp/ios/Classes/SoundableProudpLib/` (used for CocoaPods).
