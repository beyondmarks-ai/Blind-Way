class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:7071/api',
  );
  static const speechStreamUrl = String.fromEnvironment('SPEECH_STREAM_URL');
  static const porcupineAccessKey = String.fromEnvironment(
    'PORCUPINE_ACCESS_KEY',
  );
  static const wakeWordKeywordPath = String.fromEnvironment(
    'WAKE_WORD_KEYWORD_PATH',
  );
  static const wakeWordPhrase = String.fromEnvironment(
    'WAKE_WORD_PHRASE',
    defaultValue: 'Jarvis',
  );
  static const auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
  static const auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
  static const auth0Audience = String.fromEnvironment(
    'AUTH0_AUDIENCE',
    defaultValue: 'https://api.blindway.beyondmarks.ai',
  );

  static bool get authConfigured =>
      auth0Domain.isNotEmpty && auth0ClientId.isNotEmpty;

  static bool get offlineWakeWordConfigured => porcupineAccessKey.isNotEmpty;
}
