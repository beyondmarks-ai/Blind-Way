import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:blind_way/src/services/camera_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int statusCode = 200;
  bool ready = true;
  bool validJpeg = true;
  Completer<void>? readingGate;
  final readingStarted = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.path.endsWith('/status')) {
      return ResponseBody.fromString(
        jsonEncode({
          'ready': ready,
          'reading': '1600x1200',
          'navigation': '320x240',
        }),
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (options.path.endsWith('/read') && readingGate != null) {
      readingStarted.complete();
      await readingGate!.future;
    }
    return ResponseBody.fromBytes(
      validJpeg ? [255, 216, 255, 217] : [255, 216, 1, 2],
      200,
      headers: {
        Headers.contentTypeHeader: ['image/jpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraAdapter adapter;
  late CameraService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adapter = CameraAdapter();
    service = CameraService(dio: Dio()..httpClientAdapter = adapter);
  });
  tearDown(() => service.dispose());
  test(
    'normalizes manual address and rejects endpoint paths and credentials',
    () {
      expect(
        CameraService.normalizeAddress(' 10.67.29.164/ '),
        'http://10.67.29.164',
      );
      expect(
        CameraService.normalizeAddress('http://192.168.1.2:8080'),
        'http://192.168.1.2:8080',
      );
      for (final value in [
        '',
        'ftp://camera',
        'http://user:pass@camera',
        'http://camera/capture',
        'http://camera?token=secret',
      ]) {
        expect(
          () => CameraService.normalizeAddress(value),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'connect verifies JPEG, negotiates reading, and restores saved capabilities',
    () async {
      final camera = await service.connect(
        '10.67.29.164',
        token: ' camera-secret ',
      );
      expect(camera.supportsReading, isTrue);
      expect(adapter.requests.map((r) => r.uri.path), ['/status', '/capture']);
      expect(
        adapter.requests.every(
          (r) => r.headers['Authorization'] == 'Bearer camera-secret',
        ),
        isTrue,
      );
      expect(adapter.requests.every((r) => !r.followRedirects), isTrue);
      final restored = await service.restore();
      expect(restored!.baseUrl, camera.baseUrl);
      expect(restored.supportsReading, isTrue);
    },
  );
  test('legacy firmware remains usable for navigation', () async {
    adapter.statusCode = 404;
    final camera = await service.connect('camera.local');
    expect(camera.supportsReading, isFalse);
    expect(() => service.captureReading(camera), throwsStateError);
  });
  test(
    'auth failure does not fall back or overwrite saved connection',
    () async {
      await service.connect('camera.local');
      adapter.statusCode = 401;
      await expectLater(
        service.connect('other.local'),
        throwsA(isA<DioException>()),
      );
      expect((await service.restore())!.baseUrl, 'http://camera.local');
    },
  );
  test('unavailable sensor and truncated JPEG fail connection', () async {
    adapter.ready = false;
    await expectLater(service.connect('camera.local'), throwsStateError);
    adapter.ready = true;
    adapter.validJpeg = false;
    await expectLater(service.connect('camera.local'), throwsStateError);
    expect(await service.restore(), isNull);
  });
  test(
    'reading uses POST with longer timeout and serializes navigation behind it',
    () async {
      const camera = CameraConnection(
        baseUrl: 'http://camera.local',
        supportsReading: true,
      );
      adapter.readingGate = Completer<void>();
      final reading = service.captureReading(camera);
      final navigation = service.capture(camera);
      await adapter.readingStarted.future.timeout(const Duration(seconds: 2));
      expect(adapter.requests.length, 1);
      expect(adapter.requests.single.method, 'POST');
      expect(
        adapter.requests.single.receiveTimeout,
        const Duration(seconds: 60),
      );
      adapter.readingGate!.complete();
      await reading;
      await navigation;
      expect(adapter.requests.last.uri.path, '/capture');
      expect(adapter.requests.last.receiveTimeout, const Duration(seconds: 8));
    },
  );
  test('a failed camera request does not poison the queue', () async {
    const camera = CameraConnection(baseUrl: 'http://camera.local');
    adapter.validJpeg = false;
    await expectLater(service.capture(camera), throwsStateError);
    adapter.validJpeg = true;
    expect(await service.capture(camera), isNotEmpty);
  });
  test(
    'timed-out live HTTP capture releases the camera for the next request',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) {
        requests++;
        if (requests == 1) {
          return; // Deliberately never answer the first capture.
        }
        request.response.headers.contentType = ContentType('image', 'jpeg');
        request.response.add([255, 216, 255, 217]);
        unawaited(request.response.close());
      });
      final client = CameraService(
        liveCaptureTimeout: const Duration(milliseconds: 150),
      );
      final connection = CameraConnection(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      try {
        await expectLater(
          client.captureLive(connection),
          throwsA(isA<DioException>()),
        );
        final frame = await client
            .captureLive(connection)
            .timeout(const Duration(seconds: 2));
        expect(frame, [255, 216, 255, 217]);
        expect(requests, 2);
      } finally {
        client.dispose();
        await server.close(force: true);
        HttpOverrides.global = previousOverrides;
      }
    },
  );
  test(
    'live deadline starts after a queued reading capture finishes',
    () async {
      final client = CameraService(
        dio: Dio()..httpClientAdapter = adapter,
        liveCaptureTimeout: const Duration(milliseconds: 80),
      );
      adapter.readingGate = Completer<void>();
      const connection = CameraConnection(
        baseUrl: 'http://camera.local',
        supportsReading: true,
      );
      final reading = client.captureReading(connection);
      await adapter.readingStarted.future;
      final live = client.captureLive(connection);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(adapter.requests.length, 1);
      adapter.readingGate!.complete();
      await reading;
      expect(await live, [255, 216, 255, 217]);
      client.dispose();
    },
  );
}
