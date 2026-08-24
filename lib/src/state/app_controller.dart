import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/bluetooth_service.dart';
import '../services/camera_service.dart';
import '../services/foreground_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/provisioning_service.dart';
import '../services/speech_service.dart';
import '../services/voice_emergency_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final apiServiceProvider = Provider((ref) => ApiService());
final cameraServiceProvider = Provider((ref) => CameraService());
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

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppState {
  const AppState({
    this.session,
    this.selectedRole,
    this.camera,
    this.isAssisting = false,
    this.isBusy = false,
    this.currentCue,
    this.activeAlert,
    this.contacts = const [],
    this.inviteCode,
    this.sosCountdown,
    this.bluetoothAudio = false,
    this.voiceEmergencyAvailable = true,
    this.voiceEmergencyListening = false,
    this.voiceEmergencyMode = VoiceEmergencyMode.unavailable,
    this.language = 'English',
    this.error,
  });

  final UserSession? session;
  final UserRole? selectedRole;
  final CameraConnection? camera;
  final bool isAssisting;
  final bool isBusy;
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

  AppState copyWith({
    UserSession? session,
    UserRole? selectedRole,
    CameraConnection? camera,
    bool? isAssisting,
    bool? isBusy,
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
    bool clearError = false,
    bool clearAlert = false,
    bool clearInvite = false,
  }) => AppState(
    session: session ?? this.session,
    selectedRole: selectedRole ?? this.selectedRole,
    camera: camera ?? this.camera,
    isAssisting: isAssisting ?? this.isAssisting,
    isBusy: isBusy ?? this.isBusy,
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
  );
}

class AppController extends Notifier<AppState> {
  Timer? _visionTimer;
  Timer? _countdownTimer;
  Timer? _locationTimer;
  Timer? _alertRefreshTimer;
  StreamSubscription<RemoteMessage>? _notificationSubscription;
  StreamSubscription<RemoteMessage>? _foregroundNotificationSubscription;
  bool _visionInFlight = false;
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
      state.session?.role == UserRole.blindUser &&
      AppConfig.offlineWakeWordConfigured &&
      state.voiceEmergencyMode != VoiceEmergencyMode.speechRecognition;

  @override
  AppState build() {
    ref.onDispose(() {
      _visionTimer?.cancel();
      _countdownTimer?.cancel();
      _locationTimer?.cancel();
      _alertRefreshTimer?.cancel();
      _notificationSubscription?.cancel();
      _foregroundNotificationSubscription?.cancel();
      unawaited(_voice.stop());
    });
    Future.microtask(_initialize);
    return const AppState();
  }

  Future<void> _initialize() async {
    await _speech.initialize();
    _foreground.initialize();
    final camera = await _camera.restore();
    final bluetoothAudio = await _bluetooth.hasBluetoothAudio();
    state = state.copyWith(camera: camera, bluetoothAudio: bluetoothAudio);
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerPushToken);
    _notificationSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => refreshActiveAlerts(),
    );
    _foregroundNotificationSubscription = FirebaseMessaging.onMessage.listen(
      (_) => refreshActiveAlerts(),
    );
  }

  void selectRole(UserRole role) => state = state.copyWith(selectedRole: role);

  Future<void> login() => _login();

  Future<void> loginWithPhoneOtp() => _login(connection: 'sms');

  Future<void> _login({String? connection}) async {
    final role = state.selectedRole;
    if (role == null) return;
    await _guard(() async {
      final session = await _auth.login(role, connection: connection);
      await _completeLogin(session);
    });
  }

  Future<bool> requestPhoneOtp(String phoneNumber) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _auth.sendPhoneOtp(phoneNumber);
      return true;
    } catch (error) {
      state = state.copyWith(error: _message(error));
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<bool> verifyPhoneOtp(
    String phoneNumber,
    String verificationCode,
  ) async {
    final role = state.selectedRole;
    if (role == null) return false;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final session = await _auth.loginWithPhoneOtp(
        role,
        phoneNumber: phoneNumber,
        verificationCode: verificationCode,
      );
      await _completeLogin(session);
      return true;
    } catch (error) {
      state = state.copyWith(error: _message(error));
      return false;
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> _completeLogin(UserSession session) async {
    _api.setAccessToken(session.accessToken);
    state = state.copyWith(session: session, clearError: true);
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
    await stopAssistance();
    _alertRefreshTimer?.cancel();
    _alertRefreshTimer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    await _voice.stop();
    await _auth.logout();
    _api.setAccessToken(null);
    state = AppState(camera: state.camera, selectedRole: state.selectedRole);
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

  Future<void> connectCamera(String url, {String? token}) => _guard(() async {
    final camera = await _camera.connect(url, token: token);
    state = state.copyWith(camera: camera, clearError: true);
    await _speech.speak('Camera connected');
  });

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

  Future<void> startAssistance() async {
    if (state.camera == null) {
      state = state.copyWith(
        error: 'Connect the camera before starting assistance.',
      );
      return;
    }
    state = state.copyWith(isAssisting: true, clearError: true);
    if (!state.voiceEmergencyListening) {
      await _startVoiceEmergencyDetection();
    }
    await _foreground.start();
    unawaited(_speech.speak('Vision assistance started'));
    await _analyzeNextFrame();
  }

  Future<void> stopAssistance() async {
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
    if (!state.isAssisting || _visionInFlight || state.camera == null) return;
    _visionInFlight = true;
    var nextDelay = const Duration(seconds: 3);
    try {
      final frame = await _camera.capture(state.camera!);
      _latestFrame = frame;
      _latestFrameCapturedAt = DateTime.now().toUtc();
      final cue = await _api.analyze(frame, language: state.language);
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
      state = state.copyWith(error: 'Vision unavailable: ${_message(error)}');
      if (_lastSpokenCue != 'Vision unavailable') {
        await _speech.speak('Vision unavailable');
        _lastSpokenCue = 'Vision unavailable';
      }
      nextDelay = const Duration(seconds: 5);
    } finally {
      _visionInFlight = false;
      if (state.isAssisting) {
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
    await _voice.stop();
    _pendingTriggerSource = voiceTriggered ? 'voice' : 'button';
    final countdownSeconds = voiceTriggered ? 3 : 5;
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
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
    _countdownTimer?.cancel();
    state = state.copyWith(clearCountdown: true);
    await _speech.speak('Emergency alert cancelled', interrupt: true);
    if (state.isAssisting || _alwaysOnWakeWordEnabled) {
      await _startVoiceEmergencyDetection();
    }
  }

  Future<void> dispatchEmergency() => _guard(() async {
    if (state.camera != null &&
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
      'Emergency alert sent to your trusted contacts',
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

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    await _speech.setLanguage(language);
    if (state.isAssisting || _alwaysOnWakeWordEnabled) {
      await _startVoiceEmergencyDetection();
    }
  }

  Future<void> _startVoiceEmergencyDetection() async {
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
    await _startVoiceEmergencyDetection();
    if (state.voiceEmergencyMode == VoiceEmergencyMode.offlineWakeWord) {
      await _foreground.start();
    } else {
      // Short-command speech recognition is a session fallback, not a safe
      // always-on detector. Keep it off until vision assistance is started.
      await _voice.stop();
      state = state.copyWith(voiceEmergencyListening: false);
    }
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
