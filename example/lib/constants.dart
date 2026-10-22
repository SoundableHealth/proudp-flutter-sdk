// Contact dev@soundable.health to get the server configuration keys.
// Set them here or pass them with --dart-define, e.g.
// flutter run --dart-define=SOUNDABLE_API_KEY=... --dart-define=SOUNDABLE_SERVER_URL=... --dart-define=SOUNDABLE_SOCKET_URL=...
const String apiKey = String.fromEnvironment('SOUNDABLE_API_KEY');
const String serverUrl = String.fromEnvironment('SOUNDABLE_SERVER_URL');
const String socketUrl = String.fromEnvironment('SOUNDABLE_SOCKET_URL');

// TODO: change to the user's de-identified ID, gender and clinic (or company) name.
const String userId = 'soundableTest';
const String clinic = 'soundable';
