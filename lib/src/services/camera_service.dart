import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraConnection {
  const CameraConnection({required this.baseUrl, this.token});

  final String baseUrl;
  final String? token;
}

class CameraService {
  CameraService() : _dio = Dio();

  static const _urlKey = 'camera_url';
  static const _tokenKey = 'camera_token';
  final Dio _dio;

  Future<CameraConnection?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_urlKey);
    if (url == null || url.isEmpty) return null;
    return CameraConnection(baseUrl: url, token: prefs.getString(_tokenKey));
  }

  Future<CameraConnection> connect(String value, {String? token}) async {
    var url = value.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    final connection = CameraConnection(baseUrl: url, token: token?.trim());
    await capture(connection);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, connection.baseUrl);
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

  Future<Uint8List> capture(CameraConnection connection) async {
    final response = await _dio.get<List<int>>(
      '${connection.baseUrl}/capture',
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          if (connection.token?.isNotEmpty == true)
            'Authorization': 'Bearer ${connection.token}',
        },
      ),
    );
    final data = Uint8List.fromList(response.data ?? const []);
    if (data.length < 4 || data[0] != 0xff || data[1] != 0xd8) {
      throw StateError('The camera did not return a valid JPEG image.');
    }
    return data;
  }
}
