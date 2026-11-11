import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:blind_way/src/services/location_service.dart';
import 'package:blind_way/src/services/api_service.dart';
import 'package:blind_way/src/services/speech_service.dart';
import 'package:blind_way/src/services/foreground_service.dart';
import 'package:blind_way/src/services/voice_capture_service.dart';
import 'package:blind_way/src/services/voice_emergency_service.dart';
import 'package:blind_way/src/state/app_controller.dart';

class VoiceApi extends Mock implements ApiService {}

class VoiceSpeech extends Mock implements SpeechService {}

class VoiceForeground extends Mock implements ForegroundService {}

class EmergencyVoice extends Mock implements VoiceEmergencyService {}

class NavigationGps extends Mock implements LocationService {}

class Capture extends VoiceCaptureService {
  int id = 0;
  @override
  Future<void> start() async {}
  @override
  Future<void> record(int captureId) async {
    id = captureId;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> mute(bool muted) async {}
}

class QuestionController extends AppController {
  int dispatched = 0;
  void enableHandsFreeForTest() =>
      state = state.copyWith(handsFreeQuestions: true);
  @override
  Future<void> dispatchEmergency() async {
    dispatched++;
  }

  @override
  AppState build() => const AppState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  late ProviderContainer container;
  late QuestionController controller;
  late VoiceApi api;
  late VoiceSpeech speech;
  late Capture capture;
  late NavigationGps gps;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'requestPermissions' ? {7: 1} : 1,
        );
    api = VoiceApi();
    speech = VoiceSpeech();
    capture = Capture();
    gps = NavigationGps();
    final foreground = VoiceForeground();
    final emergency = EmergencyVoice();
    when(() => speech.stop()).thenAnswer((_) async {});
    when(() => speech.setLanguage(any())).thenAnswer((_) async {});
    when(
      () => speech.speak(
        any(),
        queueKey: any(named: 'queueKey'),
        interrupt: any(named: 'interrupt'),
        localOnly: any(named: 'localOnly'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => foreground.start(includeLocation: any(named: 'includeLocation')),
    ).thenAnswer((_) async {});
    when(() => foreground.stop()).thenAnswer((_) async {});
    when(() => emergency.stop()).thenAnswer((_) async {});
    controller = QuestionController();
    container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(() => controller),
        apiServiceProvider.overrideWithValue(api),
        speechServiceProvider.overrideWithValue(speech),
        voiceCaptureServiceProvider.overrideWithValue(capture),
        voiceEmergencyServiceProvider.overrideWithValue(emergency),
        foregroundServiceProvider.overrideWithValue(foreground),
        locationServiceProvider.overrideWithValue(gps),
      ],
    );
    container.read(appControllerProvider);
  });
  tearDown(() => container.dispose());
  void audio([int? id]) => controller.handleQuestionEvent({
    'type': 'audio',
    'captureId': id ?? capture.id,
    'wav': Uint8List(44),
  });
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  test(
    'hands-free address prompt opens reply capture and sends its confirmation context',
    () async {
      controller.enableHandsFreeForTest();
      when(() => gps.navigationFix()).thenAnswer(
        (_) async => Position(
          latitude: 12,
          longitude: 77,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 5,
          heading: 0,
          headingAccuracy: 5,
          speed: 0,
          speedAccuracy: 1,
        ),
      );
      when(() => api.navigation('search', any())).thenAnswer(
        (_) async => {
          'places': [
            {
              'id': 'park',
              'name': 'Park',
              'address': 'Road',
              'location': {'latitude': 12, 'longitude': 77},
            },
          ],
        },
      );
      when(
        () => api.askQuestion(
          any(),
          any(),
          language: any(named: 'language'),
          navigationPrompt: 'destination',
        ),
      ).thenAnswer(
        (_) async => {
          'question': 'No',
          'language': 'en-IN',
          'navigation': {'action': 'reject'},
        },
      );
      await controller.navigationCommand({
        'action': 'search',
        'destination': 'Park',
      });
      expect(capture.id, 0);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(capture.id, greaterThan(0));
      expect(container.read(appControllerProvider).isAsking, true);
      audio();
      await tick();
      verify(
        () => api.askQuestion(
          any(),
          any(),
          language: any(named: 'language'),
          navigationPrompt: 'destination',
        ),
      ).called(1);
      expect(controller.navigation.state.active, false);
      expect(controller.navigation.state.places, isEmpty);
      await controller.cancelQuestion();
      await controller.navigation.stop(silent: true);
    },
  );
  test('cancelled question cannot play a delayed answer', () async {
    final pending = Completer<Map<String, dynamic>>();
    when(
      () => api.askQuestion(any(), any(), language: any(named: 'language')),
    ).thenAnswer((_) => pending.future);
    await controller.askQuestion();
    audio();
    await tick();
    await controller.cancelQuestion();
    pending.complete({
      'answer': 'Late reply',
      'question': 'Question',
      'language': 'hi-IN',
    });
    await tick();
    expect(container.read(appControllerProvider).isAsking, false);
    verifyNever(() => speech.speak('Late reply', queueKey: 'assistant-answer'));
  });
  test(
    'old microphone events are ignored after a new question starts',
    () async {
      await controller.askQuestion();
      final old = capture.id;
      await controller.cancelQuestion();
      await controller.askQuestion();
      audio(old);
      await tick();
      verifyNever(
        () => api.askQuestion(any(), any(), language: any(named: 'language')),
      );
      await controller.cancelQuestion();
    },
  );
  test('successive questions automatically change speech language', () async {
    await controller.setLanguage('auto');
    for (final language in ['hi-IN', 'ta-IN']) {
      when(() => api.askQuestion(any(), any(), language: 'auto')).thenAnswer(
        (_) async => {
          'answer': 'Reply',
          'question': 'Question',
          'language': language,
        },
      );
      await controller.askQuestion();
      audio();
      await tick();
      expect(container.read(appControllerProvider).language, 'auto');
      expect(container.read(appControllerProvider).isAsking, false);
      verify(() => speech.setLanguage(language)).called(1);
    }
  });
  test('SOS takes priority over a pending AI answer', () async {
    final pending = Completer<Map<String, dynamic>>();
    when(
      () => api.askQuestion(any(), any(), language: any(named: 'language')),
    ).thenAnswer((_) => pending.future);
    await controller.askQuestion();
    audio();
    await tick();
    await controller.triggerVoiceEmergency();
    pending.complete({'answer': 'Late reply', 'language': 'hi-IN'});
    await tick();
    expect(container.read(appControllerProvider).sosCountdown, 3);
    verifyNever(() => speech.speak('Late reply', queueKey: 'assistant-answer'));
    await controller.cancelSosCountdown();
  });
  test(
    'navigation uses the language detected in the current voice request',
    () async {
      await controller.setLanguage('auto');
      when(() => api.askQuestion(any(), any(), language: 'auto')).thenAnswer(
        (_) async => {
          'question': 'Take me to the park',
          'language': 'kn-IN',
          'navigation': {'action': 'search', 'destination': 'Park'},
        },
      );
      when(() => gps.navigationFix()).thenAnswer(
        (_) async => Position(
          latitude: 12,
          longitude: 77,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 5,
          heading: 0,
          headingAccuracy: 5,
          speed: 0,
          speedAccuracy: 1,
        ),
      );
      when(
        () => api.navigation('search', any()),
      ).thenAnswer((_) async => {'places': []});
      await controller.askQuestion();
      audio();
      await tick();
      final body =
          verify(() => api.navigation('search', captureAny())).captured.single
              as Map;
      expect(body['language'], 'kn-IN');
      expect(body['query'], 'Park');
      expect(
        container.read(appControllerProvider).lastQuestion,
        'Take me to the park',
      );
      await controller.navigation.stop(silent: true);
    },
  );
  testWidgets('cancelling during the spoken announcement cannot restart SOS', (
    tester,
  ) async {
    final announcement = Completer<void>();
    when(
      () => speech.speak(
        'Emergency alert in 3 seconds. Tap cancel to stop.',
        interrupt: true,
      ),
    ).thenAnswer((_) => announcement.future);
    final started = controller.triggerVoiceEmergency();
    await tester.pump();
    expect(container.read(appControllerProvider).sosCountdown, 3);
    await controller.cancelSosCountdown();
    announcement.complete();
    await started;
    await tester.pump(const Duration(seconds: 4));
    expect(container.read(appControllerProvider).sosCountdown, isNull);
    expect(controller.dispatched, 0);
  });
}
