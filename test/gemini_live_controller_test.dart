import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blind_way/src/config/languages.dart';
import 'package:blind_way/src/services/gemini_live_service.dart';
import 'package:blind_way/src/services/voice_capture_service.dart';
import 'package:blind_way/src/services/voice_emergency_service.dart';
import 'package:blind_way/src/services/camera_service.dart';
import 'package:blind_way/src/services/speech_service.dart';
import 'package:blind_way/src/services/foreground_service.dart';
import 'package:blind_way/src/state/app_controller.dart';

class LiveFake extends GeminiLiveService {
  LiveFake() : super(() async => 'test');
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  final List<String> sent = [];
  String? connectedLanguage;
  int connections = 0;
  Completer<void>? languageWait;
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> connect({String language = 'auto'}) async {
    connections++;
    connectedLanguage = language;
    ready = true;
  }

  @override
  Future<void> changeLanguage(String language) async {
    await languageWait?.future;
    connectedLanguage = language;
    ready = true;
  }

  @override
  Future<void> close() async {
    ready = false;
    sent.add('close');
  }

  @override
  void frame(Uint8List jpeg) {
    sent.add('frame');
  }

  @override
  void observe(int turn, String language) {
    sent.add('observe:$turn');
  }

  @override
  void played(int turn) {
    sent.add('played:$turn');
  }

  @override
  void begin(int turn) {
    sent.add('begin:$turn');
  }

  @override
  void audio(int turn, Uint8List pcm) {
    sent.add('audio:$turn');
  }

  @override
  void end(int turn) {
    sent.add('end:$turn');
  }

  @override
  void cancel() {
    ready = false;
    sent.add('cancel');
  }
}

class LiveCapture extends VoiceCaptureService {
  int id = 0, played = 0, stopped = 0;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    stopped++;
  }

  @override
  Future<void> mute(bool muted) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> recordLive(int captureId) async {
    id = captureId;
  }

  @override
  Future<void> startPlayback(int turn) async {}
  @override
  Future<void> playChunk(int turn, Uint8List pcm) async {
    played++;
  }

  @override
  Future<void> endPlayback(int turn) async {}
  @override
  Future<void> stopPlayback() async {
    stopped++;
  }
}

class LiveCamera extends Mock implements CameraService {}

class LiveSpeech extends Mock implements SpeechService {}

class LiveForeground extends Mock implements ForegroundService {}

class LiveEmergency extends Mock implements VoiceEmergencyService {}

class LiveController extends AppController {
  @override
  AppState build() =>
      const AppState(camera: CameraConnection(baseUrl: 'http://camera.local'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => registerFallbackValue(
      const CameraConnection(baseUrl: 'http://camera.local'),
    ),
  );
  late ProviderContainer container;
  late LiveController controller;
  late LiveFake live;
  late LiveCapture capture;
  late LiveCamera camera;
  late LiveSpeech speech;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'requestPermissions' ? {7: 1} : 1,
        );
    live = LiveFake();
    capture = LiveCapture();
    camera = LiveCamera();
    speech = LiveSpeech();
    final foreground = LiveForeground();
    final emergency = LiveEmergency();
    when(
      () => camera.captureLive(any()),
    ).thenAnswer((_) async => Uint8List.fromList([255, 216, 255, 217]));
    when(() => speech.stop()).thenAnswer((_) async {});
    when(() => speech.setLanguage(any())).thenAnswer((_) async {});
    when(
      () => speech.speak(
        any(),
        interrupt: any(named: 'interrupt'),
        queueKey: any(named: 'queueKey'),
        localOnly: any(named: 'localOnly'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => foreground.start(includeLocation: any(named: 'includeLocation')),
    ).thenAnswer((_) async {});
    when(() => foreground.stop()).thenAnswer((_) async {});
    when(() => emergency.stop()).thenAnswer((_) async {});
    controller = LiveController();
    container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(() => controller),
        geminiLiveServiceProvider.overrideWithValue(live),
        voiceCaptureServiceProvider.overrideWithValue(capture),
        cameraServiceProvider.overrideWithValue(camera),
        speechServiceProvider.overrideWithValue(speech),
        foregroundServiceProvider.overrideWithValue(foreground),
        voiceEmergencyServiceProvider.overrideWithValue(emergency),
      ],
    );
    container.read(appControllerProvider);
  });
  tearDown(() async {
    await controller.setGeminiLive(false);
    await live.bus.close();
    container.dispose();
  });
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  void audio(int turn) => controller.handleLiveEvent({
    'type': 'audio',
    'turn': turn,
    'data': base64Encode(Uint8List(20)),
  });
  test(
    'every selected language is saved without stopping the Live connection',
    () async {
      await controller.setGeminiLive(true);
      expect(live.connectedLanguage, 'en-IN');
      for (final language in AppLanguages.labels.keys) {
        await controller.setLanguage(language);
        expect(live.connectedLanguage, language);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'response_language',
          ),
          language,
        );
        expect(container.read(appControllerProvider).geminiLive, true);
        expect(container.read(appControllerProvider).language, language);
      }
      expect(live.connections, 1);
      expect(live.sent.where((event) => event == 'close'), isEmpty);
    },
  );
  test(
    'missing Android voice pack cannot stop Gemini language switching',
    () async {
      await controller.setGeminiLive(true);
      when(
        () => speech.setLanguage('kn-IN'),
      ).thenThrow(StateError('Voice pack absent'));
      await controller.setLanguage('kn-IN');
      expect(container.read(appControllerProvider).geminiLive, true);
      expect(live.connectedLanguage, 'kn-IN');
    },
  );
  test(
    'switching during a reply discards its late audio and allows another question',
    () async {
      await controller.setGeminiLive(true);
      await controller.askQuestion();
      final previous = capture.id;
      await controller.setLanguage('kn-IN');
      audio(previous);
      await tick();
      expect(capture.played, 0);
      await controller.askQuestion();
      expect(capture.id, greaterThan(previous));
      expect(container.read(appControllerProvider).isAsking, true);
    },
  );
  test('queued selections finish with the latest language', () async {
    await controller.setGeminiLive(true);
    await Future.wait([
      controller.setLanguage('ta-IN'),
      controller.setLanguage('kn-IN'),
    ]);
    expect(live.connectedLanguage, 'kn-IN');
    expect(container.read(appControllerProvider).geminiLive, true);
    expect(live.connections, 1);
  });
  test(
    'stopping while a language change is pending cannot restart Live',
    () async {
      await controller.setGeminiLive(true);
      live.languageWait = Completer<void>();
      final switching = controller.setLanguage('kn-IN');
      await tick();
      await controller.setGeminiLive(false);
      live.languageWait!.complete();
      await switching;
      expect(container.read(appControllerProvider).geminiLive, false);
    },
  );
  test(
    'forwards streaming chunks to the player and waits for playback completion',
    () async {
      await controller.setGeminiLive(true);
      await controller.askQuestion();
      final id = capture.id;
      controller.handleQuestionEvent({
        'type': 'liveAudio',
        'captureId': id,
        'pcm': Uint8List(2560),
      });
      expect(live.sent, contains('audio:$id'));
      expect(live.sent, isNot(contains('end:$id')));
      controller.handleQuestionEvent({'type': 'liveEnd', 'captureId': id});
      expect(live.sent, contains('end:$id'));
      audio(id);
      await tick();
      expect(capture.played, 1);
      expect(container.read(appControllerProvider).isAsking, true);
      controller.handleLiveEvent({'type': 'end', 'turn': id});
      controller.handleQuestionEvent({'type': 'playbackDone', 'captureId': id});
      await tick();
      expect(container.read(appControllerProvider).isAsking, false);
    },
  );
  test('cancel drops late model audio and old microphone chunks', () async {
    await controller.setGeminiLive(true);
    await controller.askQuestion();
    final id = capture.id;
    await controller.cancelQuestion();
    audio(id);
    controller.handleQuestionEvent({
      'type': 'liveAudio',
      'captureId': id,
      'pcm': Uint8List(2560),
    });
    await tick();
    expect(capture.played, 0);
    expect(live.sent, contains('cancel'));
    expect(live.sent, isNot(contains('audio:$id')));
  });
  test('connection loss stops live mode and microphone', () async {
    await controller.setGeminiLive(true);
    await controller.askQuestion();
    controller.handleLiveEvent({'type': 'closed'});
    await tick();
    expect(container.read(appControllerProvider).geminiLive, false);
    expect(container.read(appControllerProvider).isAsking, false);
    expect(capture.stopped, greaterThan(0));
  });
  test(
    'an expired idle session reconnects without replaying microphone audio',
    () async {
      await controller.setGeminiLive(true);
      controller.handleLiveEvent({'type': 'reconnect'});
      await tick();
      await tick();
      expect(container.read(appControllerProvider).geminiLive, true);
      expect(
        live.sent.where((message) => message.startsWith('audio:')),
        isEmpty,
      );
    },
  );
  test('SOS preempts live playback and ignores its late chunks', () async {
    await controller.setGeminiLive(true);
    await controller.askQuestion();
    final id = capture.id;
    await controller.triggerVoiceEmergency();
    audio(id);
    await tick();
    expect(container.read(appControllerProvider).sosCountdown, 3);
    expect(capture.played, 0);
    expect(container.read(appControllerProvider).geminiLive, false);
    await controller.cancelSosCountdown();
  });
  test(
    'camera failure refuses live questions rather than reusing stale images',
    () async {
      when(() => camera.captureLive(any())).thenThrow(StateError('offline'));
      await controller.setGeminiLive(true);
      expect(container.read(appControllerProvider).geminiLive, true);
      await controller.askQuestion();
      expect(capture.id, 0);
      controller.handleLiveEvent({'type': 'ready'});
      await tick();
      controller.handleLiveEvent({'type': 'ready'});
      await tick();
      expect(container.read(appControllerProvider).geminiLive, false);
      expect(
        container.read(appControllerProvider).error,
        contains('camera image lost'),
      );
      verify(
        () => speech.speak(
          'Camera disconnected. Check camera power and the phone hotspot.',
          localOnly: true,
          interrupt: true,
          queueKey: 'live-connection',
        ),
      ).called(1);
    },
  );
  test('a frame slower than the old 1.5 second limit remains usable', () async {
    when(() => camera.captureLive(any())).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      return Uint8List.fromList([255, 216, 255, 217]);
    });
    await controller.setGeminiLive(true);
    expect(container.read(appControllerProvider).geminiLive, true);
    expect(live.sent, contains('frame'));
    await controller.askQuestion();
    expect(capture.id, greaterThan(0));
  });
  test(
    'one failed capture recovers without closing Gemini or admitting stale questions',
    () async {
      when(
        () => camera.captureLive(any()),
      ).thenThrow(StateError('temporary interruption'));
      await controller.setGeminiLive(true);
      expect(controller.liveFrame, isNull);
      await controller.askQuestion();
      expect(capture.id, 0);
      when(
        () => camera.captureLive(any()),
      ).thenAnswer((_) async => Uint8List.fromList([255, 216, 255, 217]));
      controller.handleLiveEvent({'type': 'ready'});
      await tick();
      expect(container.read(appControllerProvider).geminiLive, true);
      expect(controller.liveFrame, isNotNull);
      expect(container.read(appControllerProvider).error, isNull);
      await controller.askQuestion();
      expect(capture.id, greaterThan(0));
    },
  );
  test(
    'transient camera failure during speech does not cut off playback',
    () async {
      await controller.setGeminiLive(true);
      await controller.askQuestion();
      final id = capture.id;
      audio(id);
      when(() => camera.captureLive(any())).thenThrow(StateError('offline'));
      controller.handleLiveEvent({'type': 'ready'});
      await tick();
      expect(container.read(appControllerProvider).geminiLive, true);
      expect(container.read(appControllerProvider).isAsking, true);
      expect(controller.liveFrame, isNull);
      controller.handleLiveEvent({'type': 'end', 'turn': id});
      controller.handleQuestionEvent({'type': 'playbackDone', 'captureId': id});
      await tick();
      expect(container.read(appControllerProvider).isAsking, false);
      expect(live.sent, contains('played:$id'));
    },
  );
  test(
    'automatic description needs a fresh frame and never overlaps a turn',
    () async {
      await controller.setGeminiLive(true);
      controller.setAutoNarration(true);
      await controller.describeLiveScene();
      expect(live.sent.where((x) => x.startsWith('observe:')).length, 1);
      await controller.describeLiveScene();
      expect(live.sent.where((x) => x.startsWith('observe:')).length, 1);
      await controller.cancelQuestion();
      expect(container.read(appControllerProvider).autoNarration, false);
    },
  );
  test('late images are discarded and cannot start a question', () async {
    when(() => camera.captureLive(any())).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      return Uint8List.fromList([255, 216, 255, 217]);
    });
    await controller.setGeminiLive(true);
    expect(container.read(appControllerProvider).geminiLive, true);
    expect(live.sent, isNot(contains('frame')));
    expect(controller.liveFrame, isNull);
    await controller.askQuestion();
    expect(capture.id, 0);
  });
}
