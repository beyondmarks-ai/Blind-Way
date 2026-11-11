import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraConnection {
  const CameraConnection({
    required this.baseUrl,
    this.token,
    this.supportsReading = false,
  });

  final String baseUrl;
  final String? token;
  final bool supportsReading;
}

class CameraService {
  CameraService({
    Dio? dio,
    this.liveCaptureTimeout = const Duration(seconds: 4),
  }) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.sendTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 8);
    _dio.options.followRedirects = false;
  }

  static const _urlKey = 'camera_url';
  static const _tokenKey = 'camera_token';
  static const _readingKey = 'camera_supports_reading';
  final Dio _dio;
  final Duration liveCaptureTimeout;
  static String captureErrorMessage(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.cancel ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => 'The camera response timed out.',
        DioExceptionType.connectionError =>
          'The phone could not reach the camera.',
        DioExceptionType.badResponse =>
          'The camera returned an error (${error.response?.statusCode ?? 0}).',
        _ => 'The camera connection was interrupted.',
      };
    }
    if (error is TimeoutException) {
      return 'The camera image arrived too late to use.';
    }
    if (error is StateError) return error.message.toString();
    return 'A fresh camera image could not be received.';
  }

  Future<void> _pending = Future<void>.value();

  void dispose() => _dio.close(force: true);

  static String normalizeAddress(String value) {
    var address = value.trim();
    if (address.isEmpty) {
      throw const FormatException('Enter the camera IP address.');
    }
    if (!address.contains('://')) address = 'http://$address';
    final uri = Uri.parse(address);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        RegExp(r'\s').hasMatch(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Enter only the camera address, for example http://10.67.29.164.',
      );
    }
    return uri.replace(path: '').toString();
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Map<String, String> _headers(CameraConnection connection) => {
    'Cache-Control': 'no-cache',
    if (connection.token?.isNotEmpty == true)
      'Authorization': 'Bearer ${connection.token}',
  };

  Future<CameraConnection?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey);
    if (url == null || url.isEmpty) return null;
    return CameraConnection(
      baseUrl: url,
      token: prefs.getString(_tokenKey),
      supportsReading: prefs.getBool(_readingKey) ?? false,
    );
  }

  Future<CameraConnection> connect(String value, {String? token}) async {
    final url = normalizeAddress(value);
    final candidate = CameraConnection(baseUrl: url, token: token?.trim());
    var supportsReading = false;
    try {
      final status = await _exclusive(
        () => _dio.get<dynamic>(
          '$url/status',
          options: Options(headers: _headers(candidate)),
        ),
      );
      final data = status.data;
      if (data is Map) {
        if (data['ready'] == false) {
          throw StateError(
            'The camera reports that its sensor is unavailable.',
          );
        }
        supportsReading =
            data['reading'] == '1600x1200' && data['navigation'] == '320x240';
      }
    } on DioException catch (error) {
      // Legacy CameraWebServer builds may not expose /status.
      if (![404, 405].contains(error.response?.statusCode)) rethrow;
    }
    final connection = CameraConnection(
      baseUrl: url,
      token: candidate.token,
      supportsReading: supportsReading,
    );
    await capture(connection);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, connection.baseUrl);
    await prefs.setBool(_readingKey, connection.supportsReading);
    if (connection.token?.isNotEmpty == true) {
      await prefs.setString(_tokenKey, connection.token!);
    } else {
      await prefs.remove(_tokenKey);
    }
    return connection;
  }

  Future<String?> discover() async {
    final client = MDnsClient(rawDatagramSocketFactory: _bindMdnsSocket);
    try {
      await client.start();
      await for (final record
          in client
              .lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4('blindway-camera.local'),
              )
              .timeout(const Duration(seconds: 4))) {
        return 'http://${record.address.address}';
      }
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } finally {
      client.stop();
    }
    return null;
  }

  // Some Android vendor kernels (including this Vivo device) reject
  // SO_REUSEPORT even though multicast_dns requests it. SO_REUSEADDR is
  // sufficient for the mDNS listener and works across those devices.
  static Future<RawDatagramSocket> _bindMdnsSocket(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 1,
  }) {
    return RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: reuseAddress,
      reusePort: false,
      ttl: ttl,
    );
  }

  Future<Uint8List> capture(CameraConnection connection) =>
      _exclusive(() => _capture(connection, reading: false));

  /// Start the deadline after acquiring the camera, and cancel the HTTP request
  /// itself so an abandoned capture cannot delay subsequent frames.
  Future<Uint8List> captureLive(CameraConnection connection) => _exclusive(
    () async {
      final cancel = CancelToken();
      final deadline = Timer(
        liveCaptureTimeout,
        () => cancel.cancel('Live camera request timed out'),
      );
      try {
        return await _capture(connection, reading: false, cancelToken: cancel);
      } finally {
        deadline.cancel();
      }
    },
  );

  Future<Uint8List> captureReading(CameraConnection connection) {
    if (!connection.supportsReading) {
      throw StateError(
        'This camera firmware does not support high-resolution reading. Reconnect after installing the navigation/text-reader firmware.',
      );
    }
    return _exclusive(() => _capture(connection, reading: true));
  }

  Future<Uint8List> _capture(
    CameraConnection connection, {
    required bool reading,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.request<List<int>>(
      '${connection.baseUrl}/${reading ? 'read' : 'capture'}',
      cancelToken: cancelToken,
      options: Options(
        method: reading ? 'POST' : 'GET',
        responseType: ResponseType.bytes,
        receiveTimeout: Duration(seconds: reading ? 60 : 8),
        headers: _headers(connection),
      ),
    );
    final data = Uint8List.fromList(response.data ?? const []);
    if (data.length < 4 ||
        data.length > 5 * 1024 * 1024 ||
        data[0] != 0xff ||
        data[1] != 0xd8 ||
        data[data.length - 2] != 0xff ||
        data.last != 0xd9) {
      throw StateError('The camera did not return a valid JPEG image.');
    }
    return data;
  }
}
