import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:blind_way/src/services/camera_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in: flutter test test/camera_device_test.dart --dart-define=CAMERA_DEVICE_URL=http://10.67.29.164
void main() {
  const address = String.fromEnvironment('CAMERA_DEVICE_URL');
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real camera connects, captures both sizes, and restores navigation',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final service = CameraService();
      addTearDown(service.dispose);
      final camera = await service.connect(address);
      expect(camera.supportsReading, isTrue);
      for (final reading in [false, true, false]) {
        final bytes = reading
            ? await service.captureReading(camera)
            : await service.capture(camera);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, reading ? 1600 : 320);
        expect(frame.image.height, reading ? 1200 : 240);
        frame.image.dispose();
        codec.dispose();
      }
    },
    skip: address.isEmpty,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real camera delivers ten bounded live captures',
    () async {
      HttpOverrides.global = null;
      final service = CameraService();
      addTearDown(service.dispose);
      final connection = CameraConnection(baseUrl: address);
      final timings = <int>[];
      for (var i = 0; i < 10; i++) {
        final clock = Stopwatch()..start();
        final bytes = await service.captureLive(connection);
        timings.add(clock.elapsedMilliseconds);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 320);
        expect(frame.image.height, 240);
        frame.image.dispose();
        codec.dispose();
      }
      // Timings are measured on this workstation, not on the Android phone.
      debugPrint('Live capture durations (ms): $timings');
    },
    skip: address.isEmpty,
    timeout: const Timeout(Duration(seconds: 50)),
  );
}
