class AppConfig {
  const AppConfig._();
  static const cameraAddress = String.fromEnvironment(
    'CAMERA_ADDRESS',
    defaultValue: 'http://10.67.29.164',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:7071/api',
  );
  static const speechStreamUrl = String.fromEnvironment('SPEECH_STREAM_URL');
  static const wakeWordPhrase = 'Hey Jarvis';
  static const geminiLiveUrl = String.fromEnvironment('GEMINI_LIVE_URL');
  // True only after the backend's FCM delivery has been configured and tested.
  static const guardianPushConfigured = bool.fromEnvironment(
    'GUARDIAN_PUSH_CONFIGURED',
  );
}
