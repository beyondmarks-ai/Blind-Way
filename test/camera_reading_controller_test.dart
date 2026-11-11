import 'dart:async';
import 'dart:typed_data';
import 'package:blind_way/src/services/api_service.dart';
import 'package:blind_way/src/services/camera_service.dart';
import 'package:blind_way/src/services/foreground_service.dart';
import 'package:blind_way/src/services/speech_service.dart';
import 'package:blind_way/src/services/text_recognition_service.dart';
import 'package:blind_way/src/state/app_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCamera extends Mock implements CameraService {}

class MockSpeech extends Mock implements SpeechService {}

class MockOcr extends Mock implements TextRecognitionService {}

class MockApi extends Mock implements ApiService {}

class MockForeground extends Mock implements ForegroundService {}

class CameraTestController extends AppController {
  CameraTestController(this.initial);
  final AppState initial;
  @override
  AppState build() => initial;
  void replace(AppState value) => state = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const camera = CameraConnection(
    baseUrl: 'http://camera.local',
    supportsReading: true,
  );
  final jpeg = Uint8List.fromList([255, 216, 255, 217]);
  setUpAll(() {
    registerFallbackValue(camera);
    registerFallbackValue(Uint8List(0));
  });
  late MockCamera cameras;
  late MockSpeech speech;
  late MockOcr ocr;
  late MockApi api;
  late MockForeground foreground;
  late ProviderContainer container;
  late CameraTestController controller;
  setUp(() {
    cameras = MockCamera();
    speech = MockSpeech();
    ocr = MockOcr();
    api = MockApi();
    foreground = MockForeground();
    when(() => cameras.captureReading(any())).thenAnswer((_) async => jpeg);
    when(() => speech.stop()).thenAnswer((_) async {});
    when(
      () => speech.speak(
        any(),
        queueKey: any(named: 'queueKey'),
        interrupt: any(named: 'interrupt'),
        localOnly: any(named: 'localOnly'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => ocr.recognize(any()),
    ).thenAnswer((_) async => 'Exit on the left.');
    when(
      () => foreground.start(includeLocation: any(named: 'includeLocation')),
    ).thenAnswer((_) async {});
    controller = CameraTestController(const AppState(camera: camera));
    container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(() => controller),
        cameraServiceProvider.overrideWithValue(cameras),
        speechServiceProvider.overrideWithValue(speech),
        textRecognitionServiceProvider.overrideWithValue(ocr),
        apiServiceProvider.overrideWithValue(api),
        foregroundServiceProvider.overrideWithValue(foreground),
      ],
    );
    container.read(appControllerProvider);
  });
  tearDown(() => container.dispose());
  test(
    'reading recognizes locally, speaks locally, and clears busy state',
    () async {
      await controller.readCameraText();
      final state = container.read(appControllerProvider);
      expect(state.recognizedText, 'Exit on the left.');
      expect(state.isReadingText, isFalse);
      verify(() => cameras.captureReading(camera)).called(1);
      verify(
        () => speech.speak(
          'Exit on the left.',
          localOnly: true,
          queueKey: 'camera-reading',
        ),
      ).called(1);
      verifyNever(() => api.analyze(any(), language: any(named: 'language')));
    },
  );
  test(
    'capture failure clears reading state and stale recognized text',
    () async {
      controller.replace(
        const AppState(camera: camera, recognizedText: 'Old result'),
      );
      when(
        () => cameras.captureReading(any()),
      ).thenThrow(StateError('Camera disconnected'));
      await controller.readCameraText();
      final state = container.read(appControllerProvider);
      expect(state.isReadingText, isFalse);
      expect(state.recognizedText, isEmpty);
      expect(state.error, contains('Camera disconnected'));
      verifyNever(() => ocr.recognize(any()));
    },
  );
  test(
    'stopping reading while capture is pending suppresses its late text',
    () async {
      final started = Completer<void>();
      final capture = Completer<Uint8List>();
      when(() => cameras.captureReading(any())).thenAnswer((_) {
        started.complete();
        return capture.future;
      });
      final operation = controller.readCameraText();
      await started.future;
      await controller.stopReadingSpeech();
      capture.complete(jpeg);
      await operation;
      expect(container.read(appControllerProvider).recognizedText, isEmpty);
      expect(container.read(appControllerProvider).isReadingText, isFalse);
      verifyNever(() => ocr.recognize(any()));
    },
  );
  test('reading does not start during SOS countdown', () async {
    controller.replace(const AppState(camera: camera, sosCountdown: 3));
    await controller.readCameraText();
    verifyNever(() => cameras.captureReading(any()));
  });
  test(
    'navigation stays enabled after reading and resumes scheduling',
    () async {
      controller.replace(const AppState(camera: camera, isAssisting: true));
      await controller.readCameraText();
      expect(container.read(appControllerProvider).isAssisting, isTrue);
      expect(container.read(appControllerProvider).isReadingText, isFalse);
      controller.replace(const AppState(camera: camera));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    },
  );
  test(
    'pre-reading navigation capture cannot publish a late scene cue',
    () async {
      final started = Completer<void>();
      final capture = Completer<Uint8List>();
      when(() => cameras.capture(any())).thenAnswer((_) {
        started.complete();
        return capture.future;
      });
      controller.replace(
        const AppState(camera: camera, voiceEmergencyListening: true),
      );
      final navigation = controller.startAssistance();
      await started.future;
      await controller.readCameraText();
      controller.replace(const AppState(camera: camera));
      capture.complete(jpeg);
      await navigation;
      verifyNever(() => api.analyze(any(), language: any(named: 'language')));
    },
  );
}
