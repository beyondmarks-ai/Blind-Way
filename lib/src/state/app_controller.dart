import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../config/languages.dart';
import '../models/navigation.dart';
import '../services/walking_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/bluetooth_service.dart';
import '../services/camera_service.dart';
import '../services/foreground_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/provisioning_service.dart';
import '../services/speech_service.dart';
import '../services/text_recognition_service.dart';
import '../services/voice_emergency_service.dart';
import '../services/voice_capture_service.dart';
import '../services/gemini_live_service.dart';
import '../services/scene_change_service.dart';

final authServiceProvider = Provider((ref) {
  final service = AuthService();
  ref.onDispose(service.dispose);
  return service;
});
final apiServiceProvider = Provider(
  (ref) => ApiService(
    accessTokenProvider: ref.read(authServiceProvider).accessToken,
  ),
);
final cameraServiceProvider = Provider((ref) {
  final service = CameraService();
  ref.onDispose(service.dispose);
  return service;
});
final textRecognitionServiceProvider = Provider(
  (ref) => TextRecognitionService(),
);
final speechServiceProvider = Provider((ref) {
  final service = SpeechService(ref.read(apiServiceProvider));
  ref.onDispose(service.dispose);
  return service;
});
final locationServiceProvider = Provider((ref) => LocationService());
final foregroundServiceProvider = Provider((ref) => ForegroundService());
final bluetoothServiceProvider = Provider((ref) => BluetoothService());
final provisioningServiceProvider = Provider((ref) => ProvisioningService());
final voiceEmergencyServiceProvider = Provider((ref) {
  final service = VoiceEmergencyService();
  ref.onDispose(service.dispose);
  return service;
});
final voiceCaptureServiceProvider = Provider((ref) => VoiceCaptureService());
final geminiLiveServiceProvider = Provider((ref) {
  final service = GeminiLiveService(ref.read(authServiceProvider).accessToken);
  ref.onDispose(service.dispose);
  return service;
});

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppState {
  const AppState({
    this.navigation = const NavigationState(),
    this.session,
    this.selectedRole,
    this.camera,
    this.isAssisting = false,
    this.isBusy = false,
    this.isReadingText = false,
    this.recognizedText = '',
    this.readingStatus = '',
    this.handsFreeQuestions = false,
    this.geminiLive = false,
    this.autoNarration = false,
    this.memoryStatus = '',
    this.liveConnecting = false,
    this.isAsking = false,
    this.questionStatus = '',
    this.lastQuestion = '',
    this.lastAnswer = '',
    this.currentCue,
    this.activeAlert,
    this.contacts = const [],
    this.inviteCode,
    this.sosCountdown,
    this.bluetoothAudio = false,
    this.voiceEmergencyAvailable = true,
    this.voiceEmergencyListening = false,
    this.voiceEmergencyMode = VoiceEmergencyMode.unavailable,
    this.language = 'en-IN',
    this.error,
    this.otpSent = false,
    this.loginPending = false,
    this.otpPhone = '',
    this.otpMessage = '',
    this.resendAvailableAt = 0,
  });

  final UserSession? session;
  final NavigationState navigation;
  final UserRole? selectedRole;
  final CameraConnection? camera;
  final bool isAssisting;
  final bool isBusy;
  final bool isReadingText;
  final String recognizedText;
  final String readingStatus;
  final bool handsFreeQuestions;
  final bool geminiLive;
  final bool autoNarration;
  final String memoryStatus;
  final bool liveConnecting;
  final bool isAsking;
  final String questionStatus;
  final String lastQuestion;
  final String lastAnswer;
  final SceneCue? currentCue;
  final EmergencyAlert? activeAlert;
  final List<TrustedContact> contacts;
  final String? inviteCode;
  final int? sosCountdown;
  final bool bluetoothAudio;
  final bool voiceEmergencyAvailable;
  final bool voiceEmergencyListening;
  final VoiceEmergencyMode voiceEmergencyMode;
  final String language;
  final String? error;
  final bool otpSent;
  final bool loginPending;
  final String otpPhone, otpMessage;
  final int resendAvailableAt;

  AppState copyWith({
    NavigationState? navigation,
    UserSession? session,
    UserRole? selectedRole,
    CameraConnection? camera,
    bool? isAssisting,
    bool? isBusy,
    bool? isReadingText,
    String? recognizedText,
    String? readingStatus,
    bool? handsFreeQuestions,
    bool? geminiLive,
    bool? autoNarration,
    String? memoryStatus,
    bool? liveConnecting,
    bool? isAsking,
    String? questionStatus,
    String? lastQuestion,
    String? lastAnswer,
    SceneCue? currentCue,
    EmergencyAlert? activeAlert,
    List<TrustedContact>? contacts,
    String? inviteCode,
    int? sosCountdown,
    bool clearCountdown = false,
    bool? bluetoothAudio,
    bool? voiceEmergencyAvailable,
    bool? voiceEmergencyListening,
    VoiceEmergencyMode? voiceEmergencyMode,
    String? language,
    String? error,
    bool? otpSent,
    bool? loginPending,
    String? otpPhone,
    String? otpMessage,
    int? resendAvailableAt,
    bool clearError = false,
    bool clearAlert = false,
    bool clearInvite = false,
  }) => AppState(
    navigation: navigation ?? this.navigation,
    session: session ?? this.session,
    selectedRole: selectedRole ?? this.selectedRole,
    camera: camera ?? this.camera,
    isAssisting: isAssisting ?? this.isAssisting,
    isBusy: isBusy ?? this.isBusy,
    isReadingText: isReadingText ?? this.isReadingText,
    recognizedText: recognizedText ?? this.recognizedText,
    readingStatus: readingStatus ?? this.readingStatus,
    handsFreeQuestions: handsFreeQuestions ?? this.handsFreeQuestions,
    geminiLive: geminiLive ?? this.geminiLive,
    autoNarration: autoNarration ?? this.autoNarration,
    memoryStatus: memoryStatus ?? this.memoryStatus,
    liveConnecting: liveConnecting ?? this.liveConnecting,
    isAsking: isAsking ?? this.isAsking,
    questionStatus: questionStatus ?? this.questionStatus,
    lastQuestion: lastQuestion ?? this.lastQuestion,
    lastAnswer: lastAnswer ?? this.lastAnswer,
    currentCue: currentCue ?? this.currentCue,
    activeAlert: clearAlert ? null : activeAlert ?? this.activeAlert,
    contacts: contacts ?? this.contacts,
    inviteCode: clearInvite ? null : inviteCode ?? this.inviteCode,
    sosCountdown: clearCountdown ? null : sosCountdown ?? this.sosCountdown,
    bluetoothAudio: bluetoothAudio ?? this.bluetoothAudio,
    voiceEmergencyAvailable:
        voiceEmergencyAvailable ?? this.voiceEmergencyAvailable,
    voiceEmergencyListening:
        voiceEmergencyListening ?? this.voiceEmergencyListening,
    voiceEmergencyMode: voiceEmergencyMode ?? this.voiceEmergencyMode,
    language: language ?? this.language,
    error: clearError ? null : error ?? this.error,
    otpSent: otpSent ?? this.otpSent,
    loginPending: loginPending ?? this.loginPending,
    otpPhone: otpPhone ?? this.otpPhone,
    otpMessage: otpMessage ?? this.otpMessage,
    resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
  );
}

class AppController extends Notifier<AppState> {
  WalkingNavigation? _navigation;
  bool _navigationSpeaking = false, _navigationCommandActive = false;
  Map<String, dynamic>? _pendingNavigationCommand;
  Timer? _navigationReplyTimer;
  String _questionNavigationPrompt = 'none';
  WalkingNavigation get navigation => _navigation ??= WalkingNavigation(
    api: _api,
    location: ref.read(locationServiceProvider),
    language: () =>
        state.language == 'auto' ? _lastDetectedLanguage : state.language,
    publish: (value) {
      if (ref.mounted) state = state.copyWith(navigation: value);
    },
    say: _speakNavigation,
  );

  Future<void> _speakNavigation(String text, bool localized) async {
    if (!ref.mounted ||
        state.activeAlert != null ||
        state.sosCountdown != null) {
      return;
    }
    _navigationSpeaking = true;
    try {
      if (state.isAsking) {
        final automatic = state.autoNarration;
        await cancelQuestion();
        state = state.copyWith(autoNarration: automatic);
      }
      await _captureVoice.mute(true);
      await _speech.setLanguage(
        state.language == 'auto' ? _lastDetectedLanguage : state.language,
      );
      await _speech.speak(text, queueKey: 'walking-navigation');
    } finally {
      _navigationSpeaking = false;
      await _speech.setLanguage(
        state.language == 'auto' ? _lastDetectedLanguage : state.language,
      );
      if (state.handsFreeQuestions &&
          !state.isAsking &&
          state.activeAlert == null &&
          state.sosCountdown == null) {
        await _captureVoice.mute(false);
      }
    }
  }

  Future<void> navigationCommand(Map<String, dynamic> command) async {
    if (state.activeAlert != null || state.sosCountdown != null) return;
    _navigationReplyTimer?.cancel();
    final spokenLanguage = command['spokenLanguage'];
    if (state.language == 'auto' &&
        spokenLanguage is String &&
        spokenLanguage != 'auto' &&
        command['action'] == 'search' &&
        AppLanguages.labels.containsKey(spokenLanguage)) {
      _lastDetectedLanguage = spokenLanguage;
    }
    _navigationCommandActive = true;
    try {
      switch (command['action']) {
        case 'language':
          await navigation.changeLanguage();
        case 'search':
          final destination = (command['destination'] as String? ?? '').trim();
          if (destination.length >= 2) await navigation.search(destination);
        case 'select':
          await navigation.choose((command['index'] as num? ?? 1).toInt());
        case 'confirm':
          await navigation.reply(true);
        case 'reject':
        case 'next':
          await navigation.reply(false);
        case 'start':
          await navigation.start();
        case 'repeat':
        case 'status':
          await navigation.repeat();
        case 'pause':
          await _speech.stop();
          await navigation.pause();
        case 'resume':
          await navigation.resume();
        case 'reroute':
          if (state.navigation.destination != null) await navigation.reroute();
        case 'stop':
          await _speech.stop();
          await navigation.stop();
      }
    } finally {
      _navigationCommandActive = false;
      if (ref.mounted &&
          navigation.prompt != 'none' &&
          state.handsFreeQuestions) {
        final prompt = navigation.prompt;
        _navigationReplyTimer = Timer(const Duration(milliseconds: 900), () {
          if (ref.mounted &&
              navigation.prompt == prompt &&
              !state.isAsking &&
              state.handsFreeQuestions &&
              state.activeAlert == null &&
              state.sosCountdown == null) {
            unawaited(askQuestion());
          }
        });
      }
    }
  }

  StreamSubscription<PhoneAuthEvent>? _phoneAuthEvents;
  StreamSubscription<Map<String, dynamic>>? _liveEvents;
  Timer? _liveFrameTimer;
  Timer? _liveReplyTimer;
  bool _liveFrameBusy = false;
  int _liveFrameFailures = 0;
  bool _liveAudioStarted = false;
  bool _liveEnded = false, _liveReconnectAfterReply = false;
  final _sceneChanges = SceneChangeService();
  DateTime? _lastLiveFinished;
  String _lastDetectedLanguage = 'en-IN';
  Future<void> _languageChange = Future<void>.value();
  int _liveModeEpoch = 0;
  DateTime? _liveFrameAt;
  GeminiLiveService get _live => ref.read(geminiLiveServiceProvider);
  Uint8List? get liveFrame =>
      state.geminiLive &&
          _liveFrameAt != null &&
          DateTime.now().difference(_liveFrameAt!) <=
              const Duration(milliseconds: 2500)
      ? _latestFrame
      : null;
  StreamSubscription<Map<String, dynamic>>? _questionEvents;
  StreamSubscription<bool>? _speechEvents;
  int _questionEpoch = 0;
  int _sosEpoch = 0;
  int? _answerEpoch;
  VoiceCaptureService get _captureVoice =>
      ref.read(voiceCaptureServiceProvider);
  Timer? _visionTimer;
  Timer? _countdownTimer;
  Timer? _locationTimer;
  Timer? _alertRefreshTimer;
  StreamSubscription<RemoteMessage>? _notificationSubscription;
  StreamSubscription<RemoteMessage>? _foregroundNotificationSubscription;
  StreamSubscription<String?>? _authTokenSubscription;
  StreamSubscription<String>? _pushTokenSubscription;
  bool _visionInFlight = false;
  int _visionEpoch = 0;
  int _readingEpoch = 0;
  int? _activeReadingEpoch;
  Uint8List? _latestFrame;
  DateTime? _latestFrameCapturedAt;
  String _pendingTriggerSource = 'button';
  String? _lastSpokenCue;
  DateTime? _lastWarningAt;

  AuthService get _auth => ref.read(authServiceProvider);
  ApiService get _api => ref.read(apiServiceProvider);
  CameraService get _camera => ref.read(cameraServiceProvider);
  SpeechService get _speech => ref.read(speechServiceProvider);
  LocationService get _location => ref.read(locationServiceProvider);
  ForegroundService get _foreground => ref.read(foregroundServiceProvider);
  BluetoothService get _bluetooth => ref.read(bluetoothServiceProvider);
  ProvisioningService get _provisioning =>
      ref.read(provisioningServiceProvider);
  VoiceEmergencyService get _voice => ref.read(voiceEmergencyServiceProvider);

  bool get _alwaysOnWakeWordEnabled =>
      state.session?.role == UserRole.blindUser && state.handsFreeQuestions;

  @override
  AppState build() {
    ref.onDispose(() {
      _navigationReplyTimer?.cancel();
      _navigation?.dispose();
      _phoneAuthEvents?.cancel();
      _liveEvents?.cancel();
      _liveFrameTimer?.cancel();
      _liveReplyTimer?.cancel();
      _questionEvents?.cancel();
      _speechEvents?.cancel();
      _visionTimer?.cancel();
      _countdownTimer?.cancel();
      _locationTimer?.cancel();
      _alertRefreshTimer?.cancel();
      _notificationSubscription?.cancel();
      _foregroundNotificationSubscription?.cancel();
      _authTokenSubscription?.cancel();
      _pushTokenSubscription?.cancel();
      unawaited(_voice.stop());
    });
    Future.microtask(_initialize);
    return const AppState();
  }

  Future<void> _initialize() async {
    await _speech.initialize();
    _foreground.initialize();
    final preferences = await SharedPreferences.getInstance();
    final language = AppLanguages.normalize(
      preferences.getString('response_language') ?? 'en-IN',
    );
    state = state.copyWith(language: language);
    await _speech.setLanguage(language == 'auto' ? 'en-IN' : language);
    final camera = await _camera.restore();
    final bluetoothAudio = await _bluetooth.hasBluetoothAudio();
    state = state.copyWith(camera: camera, bluetoothAudio: bluetoothAudio);
    _authTokenSubscription = _auth.tokenChanges.listen(_api.setAccessToken);
    _phoneAuthEvents = _auth.phoneEvents.listen(handlePhoneAuthEvent);
    _questionEvents = _captureVoice.events.listen(handleQuestionEvent);
    _speechEvents = _speech.speakingChanges.listen((speaking) {
      if (state.handsFreeQuestions || state.isAsking) {
        unawaited(
          _captureVoice
              .mute(speaking || state.isAsking || _navigationSpeaking)
              .catchError((_) {}),
        );
      }
    });
    if (NotificationService.instance.pushAvailable) {
      _pushTokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        _registerPushToken,
      );
    }
    _notificationSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => refreshActiveAlerts(),
    );
    _foregroundNotificationSubscription = FirebaseMessaging.onMessage.listen(
      (_) => refreshActiveAlerts(),
    );
    await retryLogin();
  }

  Future<void> retryLogin() async {
    if (state.isBusy) return;
    final attempt = _auth.attempt;
    state = state.copyWith(
      isBusy: true,
      loginPending: true,
      otpSent: false,
      otpMessage: 'Opening your account...',
      clearError: true,
    );
    try {
      final restored = await _auth.restore();
      if (!ref.mounted || attempt != _auth.attempt) return;
      if (restored == null) {
        state = state.copyWith(
          isBusy: false,
          loginPending: false,
          otpMessage: '',
        );
        return;
      }
      await _completeLogin(restored);
    } catch (error) {
      if (!ref.mounted || attempt != _auth.attempt) return;
      final expired =
          error is FirebaseAuthException &&
          [
            'user-disabled',
            'invalid-user-token',
            'user-token-expired',
            'user-not-found',
          ].contains(error.code);
      if (expired) {
        await _auth.logout();
        if (!ref.mounted) return;
      }
      state = state.copyWith(
        isBusy: false,
        loginPending: !expired,
        otpMessage: '',
        error: expired
            ? 'Your sign-in has expired. Request a new OTP.'
            : _loginError(error),
      );
    }
  }

  String _loginError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 409) {
        return 'This number already has a different account role. Choose Change number or cancel, then select your original role.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'Your phone is verified, but the account service could not be reached. Check mobile data or Wi-Fi, then tap Retry sign-in. No new OTP is needed.';
      }
      return 'The account service could not complete sign-in. Tap Retry sign-in. Your verified login has been kept.';
    }
    return 'Could not reconnect to your account. Check your internet connection, then tap Retry sign-in.';
  }

  void selectRole(UserRole role) => state = state.copyWith(selectedRole: role);

  Future<void> sendOtp({
    required String phoneNumber,
    required String displayName,
    bool resend = false,
  }) async {
    final role = state.selectedRole;
    if (role == null || state.isBusy || state.loginPending) return;
    if (DateTime.now().millisecondsSinceEpoch < state.resendAvailableAt) return;
    try {
      final phone = AuthService.normalizePhone(phoneNumber);
      if (displayName.trim().isEmpty) {
        throw const FormatException('Enter your name.');
      }
      state = state.copyWith(
        isBusy: true,
        otpPhone: phone,
        otpMessage: 'Requesting your SMS code…',
        clearError: true,
        resendAvailableAt: DateTime.now().millisecondsSinceEpoch + 60000,
      );
      await _auth.requestOtp(
        phoneNumber: phone,
        role: role,
        displayName: displayName,
        resend: resend,
      );
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          isBusy: false,
          error: _message(error),
          otpMessage: '',
        );
      }
    }
  }

  Future<void> verifyOtp(String code) async {
    if (state.isBusy) return;
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      otpMessage: 'Verifying your code…',
    );
    try {
      await _auth.verifyOtp(code);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(isBusy: false, error: _message(error));
      }
    }
  }

  Future<void> resetPhoneSignIn() async {
    _auth.cancelOtp();
    _api.setAccessToken(null);
    state = state.copyWith(
      isBusy: true,
      otpSent: false,
      otpPhone: '',
      otpMessage: '',
      loginPending: false,
      resendAvailableAt: 0,
      clearError: true,
    );
    await _auth.logout();
    if (ref.mounted) state = state.copyWith(isBusy: false);
  }

  @visibleForTesting
  Future<void> handlePhoneAuthEvent(PhoneAuthEvent event) async {
    if (!ref.mounted || event.generation != _auth.attempt) return;
    switch (event.type) {
      case PhoneAuthEventType.codeSent:
        state = state.copyWith(
          isBusy: false,
          otpSent: true,
          otpMessage: 'Enter the 6-digit code sent to ${state.otpPhone}.',
          clearError: true,
        );
      case PhoneAuthEventType.timeout:
        state = state.copyWith(
          isBusy: false,
          otpSent: true,
          otpMessage: event.message,
        );
      case PhoneAuthEventType.failed:
        state = state.copyWith(
          isBusy: false,
          error: event.message,
          otpMessage: '',
        );
      case PhoneAuthEventType.authenticated:
        state = state.copyWith(isBusy: false);
        await retryLogin();
    }
  }

  Future<void> _completeLogin(UserSession session) async {
    final attempt = _auth.attempt;
    _api.setAccessToken(session.accessToken);
    await _api.registerProfile(
      role: session.role,
      displayName: session.displayName,
    );
    if (!ref.mounted || attempt != _auth.attempt) return;
    state = state.copyWith(
      session: session,
      isBusy: false,
      loginPending: false,
      otpSent: false,
      otpMessage: '',
      clearError: true,
    );
    final token = await NotificationService.instance.token();
    if (token != null) await _registerPushToken(token);
    await refreshContacts();
    await refreshActiveAlerts();
    if (session.role == UserRole.blindUser && state.activeAlert == null) {
      await _enableAlwaysOnWakeWord();
    }
    if (session.role == UserRole.emergencyContact) {
      _alertRefreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => refreshActiveAlerts(),
      );
    }
  }

  Future<void> logout() async {
    await _navigation?.stop(silent: true);
    if (state.geminiLive || state.liveConnecting) await setGeminiLive(false);
    _sosEpoch++;
    _countdownTimer?.cancel();
    _questionEpoch++;
    await _captureVoice.stop();
    _readingEpoch++;
    _activeReadingEpoch = null;
    await stopAssistance();
    _alertRefreshTimer?.cancel();
    _alertRefreshTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    await _voice.stop();
    await NotificationService.instance.clearToken();
    await _auth.logout();
    _api.setAccessToken(null);
    state = AppState(
      camera: state.camera,
      selectedRole: state.selectedRole,
      language: state.language,
    );
  }

  Future<void> _registerPushToken(String token) async {
    if (state.session == null) return;
    try {
      await _api.registerDevice(
        token,
        role: state.session!.role,
        displayName: state.session!.displayName,
      );
    } catch (_) {
      // Token refresh will retry; login remains usable while notifications recover.
    }
  }

  Future<String?> discoverCamera() async {
    state = state.copyWith(isBusy: true, clearError: true);
    final discovered = await _camera.discover();
    state = state.copyWith(
      isBusy: false,
      error: discovered == null
          ? 'No Blind Way camera was found on this Wi-Fi.'
          : null,
      clearError: discovered != null,
    );
    return discovered;
  }

  Future<bool> connectCamera(String url, {String? token}) async {
    if (state.isReadingText || state.isAsking) return false;
    var connected = false;
    await _guard(() async {
      final camera = await _camera.connect(url, token: token);
      _visionEpoch++;
      state = state.copyWith(camera: camera, clearError: true);
      connected = true;
      await _speech.speak('Camera connected');
    });
    return connected;
  }

  Future<void> readCameraText() async {
    if (state.geminiLive || state.liveConnecting) return;
    if (state.isAsking) return;
    final camera = state.camera;
    if (state.isReadingText ||
        state.sosCountdown != null ||
        state.activeAlert != null) {
      return;
    }
    if (camera == null || !camera.supportsReading) {
      state = state.copyWith(
        error:
            'Connect a camera with the navigation/text-reader firmware first.',
      );
      return;
    }
    final epoch = ++_readingEpoch;
    _activeReadingEpoch = epoch;
    _visionEpoch++;
    _visionTimer?.cancel();
    state = state.copyWith(
      isReadingText: true,
      recognizedText: '',
      readingStatus:
          'Hold steady. Capturing a 1600 × 1200 photo (about 12 seconds).',
      clearError: true,
    );
    try {
      await _speech.stop();
      await _speech.speak(
        'Hold steady. Taking a photo for reading.',
        localOnly: true,
      );
      if (!ref.mounted || epoch != _readingEpoch) return;
      final image = await _camera.captureReading(camera);
      if (!ref.mounted || epoch != _readingEpoch) return;
      state = state.copyWith(
        readingStatus: 'Recognizing English text on this phone…',
      );
      final text = await ref
          .read(textRecognitionServiceProvider)
          .recognize(image);
      if (!ref.mounted || epoch != _readingEpoch) return;
      final message = text.isEmpty
          ? 'No readable text found. Move closer, improve the light, and hold steady.'
          : 'Text ready. Recognition can contain mistakes.';
      state = state.copyWith(recognizedText: text, readingStatus: message);
      await _speech.speak(
        text.isEmpty ? message : text,
        localOnly: true,
        queueKey: 'camera-reading',
      );
    } catch (error) {
      if (ref.mounted && epoch == _readingEpoch) {
        state = state.copyWith(
          readingStatus: 'Reading failed. Please try again.',
          error: 'Text reading unavailable: ${_message(error)}',
        );
      }
    } finally {
      if (ref.mounted && _activeReadingEpoch == epoch) {
        _activeReadingEpoch = null;
        state = state.copyWith(isReadingText: false);
        if (state.isAssisting && !_visionInFlight) {
          _visionTimer?.cancel();
          _visionTimer = Timer(
            const Duration(milliseconds: 100),
            _analyzeNextFrame,
          );
        }
      }
    }
  }

  Future<void> repeatReadText() async {
    if (state.recognizedText.isNotEmpty &&
        !state.isReadingText &&
        state.sosCountdown == null &&
        state.activeAlert == null) {
      await _speech.speak(
        state.recognizedText,
        localOnly: true,
        queueKey: 'camera-reading',
      );
    }
  }

  Future<void> stopReadingSpeech() async {
    _readingEpoch++;
    await _speech.stop();
  }

  Future<void> provisionCamera({
    required String deviceName,
    required String proofOfPossession,
    required String ssid,
    required String password,
  }) => _guard(() async {
    await _provisioning.provision(
      deviceName: deviceName,
      proofOfPossession: proofOfPossession,
      ssid: ssid,
      password: password,
    );
    await _speech.speak('Camera connected to Wi-Fi');
  });

  Future<void> setGeminiLive(bool enabled) async {
    if (enabled &&
        (state.isAsking ||
            state.liveConnecting ||
            state.isReadingText ||
            state.sosCountdown != null ||
            state.activeAlert != null)) {
      return;
    }
    final mode = ++_liveModeEpoch;
    if (!enabled) {
      _pendingNavigationCommand = null;
      _questionEpoch++;
      _liveReplyTimer?.cancel();
      _liveFrameTimer?.cancel();
      state = state.copyWith(
        geminiLive: false,
        liveConnecting: false,
        handsFreeQuestions: false,
        isAsking: false,
        questionStatus: 'Live camera and microphone stopped.',
      );
      _liveFrameAt = null;
      _latestFrame = null;
      _liveFrameFailures = 0;
      _sceneChanges.reset();
      _liveReconnectAfterReply = false;
      await _live.close();
      await _captureVoice.stopPlayback();
      await _captureVoice.stop();
      if (!state.isAssisting && state.activeAlert == null) {
        await _foreground.stop();
      }
      return;
    }
    if (state.camera == null) {
      state = state.copyWith(error: 'Connect the camera first.');
      return;
    }
    if (!(await Permission.microphone.request()).isGranted) {
      state = state.copyWith(
        error: 'Allow microphone access for live questions.',
      );
      return;
    }
    if (Platform.isAndroid) await Permission.bluetoothConnect.request();
    state = state.copyWith(
      liveConnecting: true,
      questionStatus: 'Connecting Gemini Live…',
      clearError: true,
    );
    try {
      await stopAssistance();
      await _voice.stop();
      await _speech.stop();
      _liveEvents ??= _live.events.listen(handleLiveEvent);
      await _foreground.start();
      await _live.connect(language: state.language);
      if (mode != _liveModeEpoch || !ref.mounted) return;
      await _captureVoice.start();
      if (mode != _liveModeEpoch || !ref.mounted) return;
      state = state.copyWith(
        geminiLive: true,
        liveConnecting: false,
        handsFreeQuestions: true,
        voiceEmergencyListening: false,
        questionStatus: 'Gemini Live ready. Say Hey Jarvis, pause, then ask.',
      );
      await _captureVoice.mute(false);
      await _sendLiveFrame();
      if (mode == _liveModeEpoch && state.geminiLive) {
        _liveFrameTimer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _sendLiveFrame(),
        );
      }
    } catch (_) {
      if (mode == _liveModeEpoch && ref.mounted) {
        await _failLive(
          'Could not start Gemini Live. Check internet and sign-in, then try again.',
        );
      }
    }
  }

  Future<void> _failLive(String message) async {
    final mode = _liveModeEpoch;
    await setGeminiLive(false);
    if (ref.mounted && _liveModeEpoch == mode + 1) {
      state = state.copyWith(error: message, questionStatus: message);
      final announcement = message.startsWith('Live camera image lost')
          ? 'Camera disconnected. Check camera power and the phone hotspot.'
          : 'Voice assistance stopped. Please restart Gemini Live.';
      unawaited(
        _speech
            .speak(
              announcement,
              localOnly: true,
              interrupt: true,
              queueKey: 'live-connection',
            )
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _restartIdleLive() async {
    final mode = _liveModeEpoch;
    await setGeminiLive(false);
    if (ref.mounted && _liveModeEpoch == mode + 1) await setGeminiLive(true);
  }

  Future<void> _sendLiveFrame() async {
    if (!state.geminiLive ||
        !_live.ready ||
        _liveFrameBusy ||
        state.camera == null) {
      return;
    }
    _liveFrameBusy = true;
    final mode = _liveModeEpoch;
    final camera = state.camera!;
    try {
      final requestedAt = DateTime.now();
      final frame = await _camera.captureLive(camera);
      if (mode != _liveModeEpoch || !ref.mounted || !state.geminiLive) return;
      // Conservatively age the image from request start, including queue time.
      if (DateTime.now().difference(requestedAt) >
          const Duration(milliseconds: 2500)) {
        throw TimeoutException('Camera image arrived too late');
      }
      final recovering = _liveFrameFailures > 0;
      _liveFrameFailures = 0;
      _latestFrame = frame;
      _latestFrameCapturedAt = DateTime.now().toUtc();
      _liveFrameAt = requestedAt;
      try {
        _live.frame(frame);
      } catch (_) {
        await _failLive(
          'Could not send the camera image to Gemini Live. Check phone internet and restart live mode.',
        );
        return;
      }
      await _considerAutomaticDescription(frame, mode);
      if (recovering && !state.isAsking) {
        state = state.copyWith(
          clearError: true,
          questionStatus:
              'Camera reconnected. Say Hey Jarvis, pause, then ask.',
        );
      }
    } catch (error) {
      if (mode == _liveModeEpoch && ref.mounted) {
        _liveFrameAt = null;
        _latestFrame = null;
        _liveFrameFailures++;
        if (_liveFrameFailures >= 3 && !(state.isAsking && _liveAudioStarted)) {
          await _failLive(
            'Live camera image lost at ${camera.baseUrl}. ${CameraService.captureErrorMessage(error)} Check the camera connection and retry.',
          );
        } else {
          state = state.copyWith(
            questionStatus:
                'Waiting for a fresh camera image. Retrying ($_liveFrameFailures/3)…',
          );
        }
      }
    } finally {
      _liveFrameBusy = false;
    }
  }

  void setAutoNarration(bool enabled) {
    _sceneChanges.reset();
    _lastLiveFinished = null;
    state = state.copyWith(
      autoNarration: enabled,
      questionStatus: enabled
          ? 'Automatic descriptions enabled. Watching for changes...'
          : 'Automatic descriptions paused. Say Hey Jarvis to ask.',
    );
    if (enabled && state.geminiLive) unawaited(_sendLiveFrame());
  }

  Future<void> _considerAutomaticDescription(Uint8List frame, int mode) async {
    if (_navigationSpeaking ||
        _navigationCommandActive ||
        (_navigation?.prompt ?? 'none') != 'none' ||
        !state.autoNarration ||
        state.isAsking ||
        state.isReadingText ||
        state.sosCountdown != null ||
        state.activeAlert != null ||
        (_lastLiveFinished != null &&
            DateTime.now().difference(_lastLiveFinished!) <
                const Duration(seconds: 2))) {
      return;
    }
    try {
      final sample = await _sceneChanges.sample(frame);
      if (!ref.mounted ||
          mode != _liveModeEpoch ||
          !state.geminiLive ||
          !state.autoNarration ||
          state.isAsking ||
          !_sceneChanges.changed(sample)) {
        return;
      }
      _sceneChanges.mark(sample);
      await describeLiveScene();
    } catch (_) {
      // Image comparison must not tear down a working audio session.
    }
  }

  @visibleForTesting
  Future<void> describeLiveScene() async {
    if (!state.geminiLive ||
        !state.autoNarration ||
        !_live.ready ||
        state.isAsking ||
        state.sosCountdown != null ||
        state.activeAlert != null ||
        state.isReadingText ||
        _liveFrameAt == null ||
        DateTime.now().difference(_liveFrameAt!) >
            const Duration(milliseconds: 2500)) {
      return;
    }
    final epoch = ++_questionEpoch;
    _liveAudioStarted = false;
    _liveEnded = false;
    state = state.copyWith(
      isAsking: true,
      lastQuestion: '',
      lastAnswer: '',
      questionStatus: 'Checking the changed surroundings...',
      clearError: true,
    );
    await _captureVoice.mute(true);
    if (!ref.mounted || epoch != _questionEpoch || !state.geminiLive) return;
    _live.observe(epoch, state.language);
    _armLiveDeadline(epoch);
  }

  void _armLiveDeadline(int epoch) {
    _liveReplyTimer?.cancel();
    _liveReplyTimer = Timer(const Duration(seconds: 60), () {
      if (ref.mounted && state.isAsking && epoch == _questionEpoch) {
        unawaited(_failLive('Live answer stalled. Please restart live mode.'));
      }
    });
  }

  Future<void> _askLiveQuestion() async {
    if (state.isAsking ||
        state.sosCountdown != null ||
        state.activeAlert != null) {
      return;
    }
    if (!_live.ready ||
        _liveFrameAt == null ||
        DateTime.now().difference(_liveFrameAt!) >
            const Duration(milliseconds: 2500)) {
      state = state.copyWith(
        error: 'Wait for a fresh live camera image, then ask again.',
      );
      await _captureVoice.mute(false);
      return;
    }
    final epoch = ++_questionEpoch;
    _liveAudioStarted = false;
    _liveEnded = false;
    state = state.copyWith(
      isAsking: true,
      lastQuestion: '',
      lastAnswer: '',
      questionStatus: 'Listening…',
      clearError: true,
    );
    await _speech.stop();
    await _captureVoice.stopPlayback();
    if (epoch != _questionEpoch || !state.geminiLive) return;
    _live.navigationPrompt(
      _questionNavigationPrompt,
      language: state.language == 'auto'
          ? _lastDetectedLanguage
          : state.language,
    );
    _live.begin(epoch);
    await HapticFeedback.lightImpact();
    await SystemSound.play(SystemSoundType.click);
    if (epoch != _questionEpoch || !state.geminiLive) return;
    await _captureVoice.recordLive(epoch);
    _armLiveDeadline(epoch);
  }

  @visibleForTesting
  void handleLiveEvent(Map<String, dynamic> event) {
    if (!ref.mounted) return;
    if (event['type'] == 'memory') {
      state = state.copyWith(
        memoryStatus: event['available'] == true
            ? 'Azure memory: 7 days - ${event['count'] ?? 0} recent conversations'
            : 'Azure memory unavailable. This session can still continue.',
      );
      return;
    }
    if (!state.geminiLive) return;
    if (event['type'] == 'navigation' &&
        state.isAsking &&
        event['turn'] == _questionEpoch) {
      _pendingNavigationCommand = Map<String, dynamic>.from(
        event['command'] as Map,
      );
      return;
    }
    if (event['type'] == 'ready') {
      state = state.copyWith(
        questionStatus: 'Gemini Live ready. Say Hey Jarvis.',
      );
      unawaited(_sendLiveFrame());
      if (!state.isAsking && !_navigationSpeaking) {
        unawaited(_captureVoice.mute(false));
      }
      return;
    }
    if (['error', 'closed', 'reconnect'].contains(event['type'])) {
      if (state.isAsking && _liveAudioStarted && _liveEnded) {
        _liveReconnectAfterReply = true;
        return;
      }
      if (!state.isAsking && event['type'] != 'error') {
        unawaited(_restartIdleLive());
        return;
      }
      unawaited(
        _failLive(
          event['message'] as String? ??
              'Live connection ended. Tap Start Gemini Live to reconnect.',
        ),
      );
      return;
    }
    if (!state.isAsking || event['turn'] != _questionEpoch) return;
    switch (event['type']) {
      case 'transcript':
        state = state.copyWith(
          lastQuestion: state.lastQuestion + (event['text'] as String? ?? ''),
        );
      case 'answer':
        state = state.copyWith(
          lastAnswer: state.lastAnswer + (event['text'] as String? ?? ''),
        );
      case 'audio':
        _armLiveDeadline(_questionEpoch);
        if (!_liveAudioStarted) {
          _liveAudioStarted = true;
          unawaited(_captureVoice.startPlayback(_questionEpoch));
        }
        state = state.copyWith(
          questionStatus: 'Preparing a smooth voice reply…',
        );
        unawaited(
          _captureVoice.playChunk(
            _questionEpoch,
            base64Decode(event['data'] as String),
          ),
        );
      case 'end':
        _liveEnded = true;
        _liveReplyTimer?.cancel();
        if (_liveAudioStarted) {
          state = state.copyWith(questionStatus: 'Gemini is speaking…');
          unawaited(_captureVoice.endPlayback(_questionEpoch));
        } else {
          _liveReplyTimer?.cancel();
          unawaited(_finishQuestion(_questionEpoch));
        }
      case 'interrupted':
        unawaited(cancelQuestion());
      case 'sos':
        unawaited(triggerVoiceEmergency());
    }
  }

  Future<void> startAssistance() async {
    if (!AppLanguages.sarvam.contains(state.language)) {
      state = state.copyWith(
        error:
            'Start Gemini Live for ${AppLanguages.name(state.language)} voice.',
      );
      return;
    }
    if (state.geminiLive || state.liveConnecting) return;
    if (state.isReadingText || state.isAsking) return;
    if (state.camera == null) {
      state = state.copyWith(
        error: 'Connect the camera before starting assistance.',
      );
      return;
    }
    state = state.copyWith(isAssisting: true, clearError: true);
    if (!state.voiceEmergencyListening && !state.handsFreeQuestions) {
      await _startVoiceEmergencyDetection();
    }
    await _foreground.start();
    unawaited(_speech.speak('Vision assistance started'));
    await _analyzeNextFrame();
  }

  Future<void> setHandsFreeQuestions(bool enabled) async {
    if (state.isAsking ||
        state.sosCountdown != null ||
        state.activeAlert != null) {
      return;
    }
    if (enabled) {
      if (!(await Permission.microphone.request()).isGranted) {
        state = state.copyWith(
          error: 'Allow microphone access to use the wake phrase.',
        );
        return;
      }
      await _voice.stop();
      try {
        await _foreground.start();
        await _captureVoice.start();
        state = state.copyWith(
          handsFreeQuestions: true,
          voiceEmergencyListening: false,
          questionStatus: 'Say Hey Jarvis, then ask your question.',
          clearError: true,
        );
      } catch (_) {
        state = state.copyWith(
          error: 'Wake listening could not start. Try Ask a question.',
        );
        if (state.isAssisting) await _startVoiceEmergencyDetection();
      }
    } else {
      await _captureVoice.stop();
      state = state.copyWith(handsFreeQuestions: false, questionStatus: '');
      if (state.isAssisting) {
        await _startVoiceEmergencyDetection();
      } else {
        await _foreground.stop();
      }
    }
  }

  Future<void> askQuestion() async {
    if (_navigationSpeaking) return;
    _navigationReplyTimer?.cancel();
    _questionNavigationPrompt = _navigation?.prompt ?? 'none';
    if (!state.geminiLive && !AppLanguages.sarvam.contains(state.language)) {
      state = state.copyWith(
        error:
            'Start Gemini Live for ${AppLanguages.name(state.language)} voice.',
      );
      return;
    }
    if (state.geminiLive) {
      try {
        await _askLiveQuestion();
      } catch (_) {
        await _failLive(
          'Could not start live recording. Check microphone access and restart live mode.',
        );
      }
      return;
    }
    if (state.isAsking ||
        state.isReadingText ||
        state.sosCountdown != null ||
        state.activeAlert != null) {
      return;
    }
    if (!(await Permission.microphone.request()).isGranted) {
      state = state.copyWith(
        error: 'Allow microphone access to ask a question.',
      );
      return;
    }
    final epoch = ++_questionEpoch;
    _visionEpoch++;
    _visionTimer?.cancel();
    state = state.copyWith(
      isAsking: true,
      questionStatus: 'Listening… speak your question.',
      lastQuestion: '',
      lastAnswer: '',
      clearError: true,
    );
    try {
      await _voice.stop();
      await _speech.stop();
      await _foreground.start();
      if (epoch != _questionEpoch) return;
      await _captureVoice.start();
      await HapticFeedback.lightImpact();
      if (epoch != _questionEpoch || !ref.mounted) return;
      await SystemSound.play(SystemSoundType.click);
      await _captureVoice.record(epoch);
    } catch (_) {
      if (epoch == _questionEpoch) {
        state = state.copyWith(
          error: 'Could not record your question. Check the microphone.',
        );
        await _finishQuestion(epoch);
      }
    }
  }

  @visibleForTesting
  void handleQuestionEvent(Map<String, dynamic> event) {
    if (!ref.mounted) return;
    switch (event['type']) {
      case 'liveAudio':
        if (state.geminiLive &&
            state.isAsking &&
            event['captureId'] == _questionEpoch &&
            event['pcm'] is Uint8List) {
          _live.audio(_questionEpoch, event['pcm'] as Uint8List);
        }
      case 'liveEnd':
        if (state.geminiLive &&
            state.isAsking &&
            event['captureId'] == _questionEpoch) {
          _live.end(_questionEpoch);
          state = state.copyWith(questionStatus: 'Gemini is answering…');
        }
      case 'playbackDone':
        if (state.geminiLive &&
            state.isAsking &&
            event['captureId'] == _questionEpoch) {
          _liveReplyTimer?.cancel();
          _live.played(_questionEpoch);
          _lastLiveFinished = DateTime.now();
          if (_liveFrameFailures >= 3) {
            unawaited(
              _failLive(
                'Live camera image lost. Check camera power and the phone hotspot.',
              ),
            );
            return;
          }
          if (_liveReconnectAfterReply) {
            state = state.copyWith(isAsking: false);
            unawaited(_restartIdleLive());
            return;
          }
          state = state.copyWith(
            questionStatus: state.autoNarration
                ? 'Watching for changes. Say Hey Jarvis to ask.'
                : 'Say Hey Jarvis for another question.',
          );
          unawaited(_finishQuestion(_questionEpoch));
        }
      case 'playbackError':
        if (state.geminiLive && event['captureId'] == _questionEpoch) {
          unawaited(
            _failLive(
              'Audio playback failed. Reconnect your earbuds and restart live mode.',
            ),
          );
        }
      case 'wake':
        if (state.handsFreeQuestions) {
          if (state.isReadingText ||
              state.isAsking ||
              state.sosCountdown != null ||
              state.activeAlert != null) {
            unawaited(_captureVoice.mute(false).catchError((_) {}));
          } else {
            unawaited(askQuestion());
          }
        }
      case 'audio':
        if (state.isAsking &&
            event['captureId'] == _questionEpoch &&
            event['wav'] is Uint8List) {
          unawaited(_answerQuestion(event['wav'] as Uint8List, _questionEpoch));
        }
      case 'noSpeech':
        if (state.isAsking && event['captureId'] == _questionEpoch) {
          state = state.copyWith(error: 'No speech detected. Try again.');
          if (state.geminiLive) {
            unawaited(cancelQuestion());
          } else {
            unawaited(_finishQuestion(_questionEpoch));
          }
        }
      case 'error':
        if (state.geminiLive) {
          unawaited(_failLive('Microphone interrupted. Restart live mode.'));
          return;
        }
        state = state.copyWith(
          error: 'Microphone interrupted. Restart voice listening.',
          handsFreeQuestions: false,
        );
        unawaited(_finishQuestion(_questionEpoch));
    }
  }

  Future<void> _answerQuestion(Uint8List wav, int epoch) async {
    if (_answerEpoch == epoch || epoch != _questionEpoch) return;
    _answerEpoch = epoch;
    state = state.copyWith(questionStatus: 'Understanding your question…');
    try {
      Uint8List? image;
      if (state.camera != null) {
        try {
          image = await _camera
              .capture(state.camera!)
              .timeout(const Duration(milliseconds: 1500));
        } catch (_) {
          /* Tell AI no camera image is available. */
        }
      }
      if (epoch != _questionEpoch || !ref.mounted) return;
      final result = _questionNavigationPrompt == 'none'
          ? await _api.askQuestion(wav, image, language: state.language)
          : await _api.askQuestion(
              wav,
              image,
              language: state.language,
              navigationPrompt: _questionNavigationPrompt,
            );
      if (epoch != _questionEpoch || !ref.mounted) return;
      if (result['emergency'] == true) {
        await triggerVoiceEmergency();
        return;
      }
      final language = result['language'] as String? ?? 'en-IN';
      if (_questionNavigationPrompt == 'none') _lastDetectedLanguage = language;
      if (result['navigation'] is Map) {
        state = state.copyWith(
          lastQuestion: result['question'] as String? ?? '',
          questionStatus: 'Handling your walking navigation request.',
        );
        _pendingNavigationCommand = Map<String, dynamic>.from(
          result['navigation'] as Map,
        );
        return;
      }
      final answer = result['answer'] as String? ?? '';
      state = state.copyWith(
        lastQuestion: result['question'] as String? ?? '',
        lastAnswer: answer,
        questionStatus: result['languageFallback'] == true
            ? 'This spoken language is not supported by Sarvam voice yet. Replying in English.'
            : 'Replying in $language.',
      );
      await _speech.setLanguage(language);
      await _speech.speak(answer, queueKey: 'assistant-answer');
    } catch (_) {
      if (ref.mounted && epoch == _questionEpoch) {
        state = state.copyWith(
          error: 'Voice answer unavailable. Check internet and try again.',
        );
      }
    } finally {
      if (_answerEpoch == epoch) _answerEpoch = null;
      await _finishQuestion(epoch);
    }
  }

  Future<void> _finishQuestion(int epoch) async {
    if (!ref.mounted || epoch != _questionEpoch) return;
    state = state.copyWith(isAsking: false);
    final command = _pendingNavigationCommand;
    _pendingNavigationCommand = null;
    if (command != null) await navigationCommand(command);
    try {
      if (state.handsFreeQuestions &&
          state.sosCountdown == null &&
          state.activeAlert == null) {
        await _captureVoice.mute(false);
      } else {
        await _captureVoice.stop();
        if (state.isAssisting &&
            state.sosCountdown == null &&
            state.activeAlert == null) {
          await _startVoiceEmergencyDetection();
        } else if (state.activeAlert == null && state.sosCountdown == null) {
          await _foreground.stop();
        }
      }
    } catch (_) {}
    if (state.isAssisting &&
        !state.isReadingText &&
        state.sosCountdown == null &&
        state.activeAlert == null) {
      _visionTimer = Timer(
        const Duration(milliseconds: 100),
        _analyzeNextFrame,
      );
    }
  }

  Future<void> cancelQuestion() async {
    _navigationReplyTimer?.cancel();
    _pendingNavigationCommand = null;
    if (state.geminiLive) {
      _questionEpoch++;
      state = state.copyWith(autoNarration: false);
      _lastLiveFinished = DateTime.now();
      _liveReplyTimer?.cancel();
      await _captureVoice.cancel();
      await _captureVoice.stopPlayback();
      _live.cancel();
      state = state.copyWith(
        isAsking: false,
        questionStatus: 'Question cancelled. Reconnecting live session…',
      );
      return;
    }
    final epoch = ++_questionEpoch;
    await _captureVoice.cancel();
    await _speech.stop();
    state = state.copyWith(questionStatus: 'Question cancelled.');
    await _finishQuestion(epoch);
  }

  Future<void> stopAssistance() async {
    _visionEpoch++;
    _visionTimer?.cancel();
    state = state.copyWith(isAssisting: false);
    await _speech.stop();
    if (!_alwaysOnWakeWordEnabled) {
      await _voice.stop();
      state = state.copyWith(voiceEmergencyListening: false);
      if (state.activeAlert == null) await _foreground.stop();
    }
  }

  Future<void> _analyzeNextFrame() async {
    if (!state.isAssisting ||
        state.isAsking ||
        state.isReadingText ||
        _visionInFlight ||
        state.camera == null) {
      return;
    }
    final epoch = _visionEpoch;
    _visionInFlight = true;
    var nextDelay = const Duration(seconds: 3);
    try {
      final frame = await _camera.capture(state.camera!);
      if (!ref.mounted || epoch != _visionEpoch || !state.isAssisting) return;
      _latestFrame = frame;
      _latestFrameCapturedAt = DateTime.now().toUtc();
      final cue = await _api.analyze(
        frame,
        language: state.language == 'auto'
            ? _lastDetectedLanguage
            : state.language,
      );
      if (!ref.mounted || epoch != _visionEpoch || !state.isAssisting) return;
      state = state.copyWith(currentCue: cue, clearError: true);
      if (_shouldSpeak(cue)) {
        unawaited(
          _speech.speak(
            cue.cue,
            queueKey: 'vision-guidance',
            interrupt: cue.risk == RiskLevel.danger,
          ),
        );
        _lastSpokenCue = cue.cue;
        if (cue.risk == RiskLevel.caution || cue.risk == RiskLevel.danger) {
          _lastWarningAt = DateTime.now();
        }
      }
      nextDelay = cue.risk == RiskLevel.clear
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 100);
    } catch (error) {
      if (!ref.mounted || epoch != _visionEpoch || !state.isAssisting) return;
      state = state.copyWith(error: 'Vision unavailable: ${_message(error)}');
      if (_lastSpokenCue != 'Vision unavailable') {
        await _speech.speak('Vision unavailable');
        _lastSpokenCue = 'Vision unavailable';
      }
      nextDelay = const Duration(seconds: 5);
    } finally {
      _visionInFlight = false;
      if (ref.mounted && state.isAssisting && !state.isReadingText) {
        _visionTimer = Timer(nextDelay, _analyzeNextFrame);
      }
    }
  }

  bool _shouldSpeak(SceneCue cue) {
    final changed = cue.cue != _lastSpokenCue;
    if (cue.risk == RiskLevel.clear) return changed && cue.confidence >= .55;
    if (cue.risk == RiskLevel.caution || cue.risk == RiskLevel.danger) {
      final repeatDue =
          _lastWarningAt == null ||
          DateTime.now().difference(_lastWarningAt!) >=
              const Duration(seconds: 5);
      return cue.confidence >= .35 && (changed || repeatDue);
    }
    return changed && cue.confidence >= .45;
  }

  Future<void> beginSosCountdown() => _beginSosCountdown(voiceTriggered: false);

  Future<void> triggerVoiceEmergency() =>
      _beginSosCountdown(voiceTriggered: true);

  Future<void> _beginSosCountdown({required bool voiceTriggered}) async {
    if (state.activeAlert != null || state.sosCountdown != null) return;
    await _navigation?.stop(silent: true);
    _pendingNavigationCommand = null;
    if (state.geminiLive || state.liveConnecting) await setGeminiLive(false);
    final sosEpoch = ++_sosEpoch;
    final countdownSeconds = voiceTriggered ? 3 : 5;
    final stopCapture = state.handsFreeQuestions || state.isAsking;
    _questionEpoch++;
    _readingEpoch++;
    state = state.copyWith(isAsking: false, sosCountdown: countdownSeconds);
    if (stopCapture) await _captureVoice.stop();
    await _voice.stop();
    if (!ref.mounted || sosEpoch != _sosEpoch) return;
    _pendingTriggerSource = voiceTriggered ? 'voice' : 'button';
    HapticFeedback.heavyImpact();
    state = state.copyWith(
      sosCountdown: countdownSeconds,
      voiceEmergencyListening: false,
      clearError: true,
    );
    await _speech.speak(
      'Emergency alert in $countdownSeconds seconds. Tap cancel to stop.',
      interrupt: true,
    );
    if (!ref.mounted || sosEpoch != _sosEpoch) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!ref.mounted || sosEpoch != _sosEpoch) {
        timer.cancel();
        return;
      }
      final remaining = (state.sosCountdown ?? 1) - 1;
      if (remaining <= 0) {
        timer.cancel();
        state = state.copyWith(clearCountdown: true);
        dispatchEmergency();
      } else {
        state = state.copyWith(sosCountdown: remaining);
        _speech.speak('$remaining');
      }
    });
  }

  Future<void> cancelSosCountdown() async {
    _sosEpoch++;
    _countdownTimer?.cancel();
    state = state.copyWith(clearCountdown: true);
    await _speech.speak('Emergency alert cancelled', interrupt: true);
    if (state.isAssisting || _alwaysOnWakeWordEnabled) {
      await _startVoiceEmergencyDetection();
    }
  }

  Future<void> dispatchEmergency() => _guard(() async {
    if (state.camera != null &&
        !state.isReadingText &&
        !_visionInFlight &&
        (_latestFrameCapturedAt == null ||
            DateTime.now().difference(_latestFrameCapturedAt!) >
                const Duration(seconds: 10))) {
      try {
        _latestFrame = await _camera.capture(state.camera!);
        _latestFrameCapturedAt = DateTime.now().toUtc();
      } catch (_) {
        // The last successful frame remains available if a fresh capture fails.
      }
    }
    final position = await _location.current();
    final alert = await _api.createAlert(
      idempotencyKey: const Uuid().v4(),
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
      triggerSource: _pendingTriggerSource,
      lastFrame: _latestFrame,
      lastCue: state.currentCue,
      snapshotCapturedAt: _latestFrameCapturedAt,
    );
    state = state.copyWith(activeAlert: alert, clearCountdown: true);
    await _foreground.stop();
    await _foreground.start(includeLocation: true);
    await _speech.speak(
      'Emergency recorded. Notifying your trusted contacts.',
      interrupt: true,
    );
    _locationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _uploadLocation(),
    );
  });

  Future<void> _uploadLocation() async {
    final alert = state.activeAlert;
    if (alert == null) return;
    final position = await _location.current();
    if (position == null) return;
    try {
      await _api.updateLocation(
        alert.id,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      // A guardian may have resolved the alert since the previous upload.
      // Refreshing lets the blind user's screen and safety service close cleanly.
      await refreshActiveAlerts();
    }
  }

  Future<void> closeAlert(String action) => _guard(() async {
    final alert = state.activeAlert;
    if (alert == null) return;
    await _api.alertAction(alert.id, action);
    if (action == 'acknowledge' &&
        state.session?.role == UserRole.emergencyContact) {
      await refreshActiveAlerts();
      await _speech.speak('Emergency acknowledged', interrupt: true);
      return;
    }
    _locationTimer?.cancel();
    _locationTimer = null;
    state = state.copyWith(clearAlert: true);
    await _foreground.stop();
    if (state.isAssisting || _alwaysOnWakeWordEnabled) {
      await _startVoiceEmergencyDetection();
      await _foreground.start();
    }
    await _speech.speak(
      'Emergency ${action == 'resolve' ? 'resolved' : 'cancelled'}',
      interrupt: true,
    );
  });

  Future<void> refreshContacts() async {
    if (state.session == null) return;
    try {
      final contacts = await _api.contacts();
      state = state.copyWith(contacts: contacts);
    } catch (_) {}
  }

  Future<void> refreshActiveAlerts() async {
    if (state.session == null) return;
    try {
      final alerts = await _api.activeAlerts();
      if (alerts.isEmpty) {
        final closedRemoteAlert = state.activeAlert != null;
        state = state.copyWith(clearAlert: true);
        if (closedRemoteAlert && state.session?.role == UserRole.blindUser) {
          _locationTimer?.cancel();
          _locationTimer = null;
          await _foreground.stop();
          if (state.isAssisting || _alwaysOnWakeWordEnabled) {
            await _startVoiceEmergencyDetection();
            await _foreground.start();
          }
        }
        return;
      }
      state = state.copyWith(activeAlert: alerts.first);
      if (state.session?.role == UserRole.blindUser && _locationTimer == null) {
        await _foreground.start(includeLocation: true);
        _locationTimer = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _uploadLocation(),
        );
      }
    } catch (_) {
      // Push notifications remain the fast path; polling recovers missed pushes.
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> createInvite() => _guard(() async {
    final code = await _api.createInvite();
    state = state.copyWith(inviteCode: code);
  });

  Future<void> redeemInvite(String code) => _guard(() async {
    await _api.redeemInvite(code);
    await refreshContacts();
  });

  Future<void> setLanguage(String language) {
    _languageChange = _languageChange.then((_) => _applyLanguage(language));
    return _languageChange;
  }

  Future<void> _applyLanguage(String language) async {
    if (!ref.mounted ||
        state.liveConnecting ||
        state.isReadingText ||
        state.sosCountdown != null ||
        state.activeAlert != null) {
      return;
    }
    final value = AppLanguages.normalize(language);
    if (state.language == value) return;
    _navigationReplyTimer?.cancel();
    if (_navigation?.state.active == true &&
        _navigation?.state.paused == false) {
      await _navigation!.pause();
    }
    final wasLive = state.geminiLive;
    if (state.isAsking && !wasLive) return;
    final mode = wasLive ? ++_liveModeEpoch : _liveModeEpoch;
    if (wasLive) {
      _questionEpoch++;
      _liveReplyTimer?.cancel();
      _liveFrameAt = null;
      _latestFrame = null;
      _lastLiveFinished = null;
      _liveReconnectAfterReply = false;
      _sceneChanges.reset();
      state = state.copyWith(
        geminiLive: false,
        liveConnecting: true,
        isAsking: false,
        questionStatus:
            'Switching Gemini Live to ${AppLanguages.name(value)}...',
      );
    }
    state = state.copyWith(language: value, clearError: true);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('response_language', value);
      // Android voice packs are independent of Gemini's cloud audio.
      unawaited(
        Future<void>.sync(
          () => _speech.setLanguage(value == 'auto' ? 'en-IN' : value),
        ).timeout(const Duration(seconds: 2)).catchError((Object _) {}),
      );
      if (!wasLive) {
        await _speech.stop();
        if (_navigation != null) {
          await navigationCommand({'action': 'language'});
        }
        return;
      }
      await _captureVoice.cancel();
      await _captureVoice.stopPlayback();
      if (!ref.mounted || mode != _liveModeEpoch) return;
      await _live.changeLanguage(value);
      if (!ref.mounted || mode != _liveModeEpoch) return;
      state = state.copyWith(
        geminiLive: true,
        liveConnecting: false,
        questionStatus:
            'Gemini Live ready in ${AppLanguages.name(value)}. Say Hey Jarvis.',
      );
      await _captureVoice.mute(false);
      await _sendLiveFrame();
      await _speech.stop();
      if (_navigation != null) await navigationCommand({'action': 'language'});
    } catch (_) {
      if (!ref.mounted || mode != _liveModeEpoch) return;
      if (wasLive) {
        await _failLive(
          'Could not switch Gemini Live language. Check internet and tap Start Gemini Live to retry.',
        );
      } else {
        state = state.copyWith(
          error: 'Could not save the language. Please try again.',
        );
      }
    }
  }

  Future<void> testNotification() => _guard(() async {
    final token = await NotificationService.instance.token();
    if (token == null) {
      throw StateError(
        'Allow notifications in Android settings and try again.',
      );
    }
    await _registerPushToken(token);
    await _api.testNotification();
    await _speech.speak(
      'Test notification requested for this account. This is not an emergency.',
      localOnly: true,
    );
  });

  Future<void> _startVoiceEmergencyDetection() async {
    if (state.isAsking) return;
    if (state.handsFreeQuestions) {
      await _captureVoice.start();
      return;
    }
    final microphone = await Permission.microphone.request();
    if (!microphone.isGranted) {
      state = state.copyWith(
        voiceEmergencyAvailable: false,
        voiceEmergencyListening: false,
        voiceEmergencyMode: VoiceEmergencyMode.unavailable,
        error: 'Microphone permission is required for the emergency wake word.',
      );
      return;
    }
    final result = await _voice.start(
      language: state.language,
      onHelp: triggerVoiceEmergency,
      onListeningChanged: (listening) {
        state = state.copyWith(voiceEmergencyListening: listening);
      },
    );
    state = state.copyWith(
      voiceEmergencyAvailable: result.available,
      voiceEmergencyListening: result.available,
      voiceEmergencyMode: result.mode,
      error: result.available
          ? null
          : 'Voice emergency detection is unavailable. Check microphone permission.',
      clearError: result.available,
    );
  }

  Future<void> _enableAlwaysOnWakeWord() async {
    if (!_alwaysOnWakeWordEnabled) return;
    await _captureVoice.start();
    await _foreground.start();
  }

  Future<void> openBluetoothSettings() async {
    await _bluetooth.openSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
    state = state.copyWith(
      bluetoothAudio: await _bluetooth.hasBluetoothAudio(),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await action();
    } catch (error) {
      state = state.copyWith(error: _message(error));
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
