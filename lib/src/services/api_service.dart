import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';

class ApiService {
  ApiService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 25),
          headers: {'Accept': 'application/json'},
        ),
      );

  final Dio _dio;
  String? _token;

  void setAccessToken(String? token) => _token = token;

  Uri speechUri(String text, String language) {
    final base = AppConfig.speechStreamUrl.isNotEmpty
        ? AppConfig.speechStreamUrl
        : '${AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/speech';
    return Uri.parse(
      base,
    ).replace(queryParameters: {'text': text, 'language': language});
  }

  Uri bufferedSpeechUri(String text, String language) => Uri.parse(
    '${AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/speech',
  ).replace(queryParameters: {'text': text, 'language': language});

  bool get hasSpeechStream => AppConfig.speechStreamUrl.isNotEmpty;

  Map<String, String>? get speechHeaders =>
      _token == null ? null : {'Authorization': 'Bearer $_token'};

  Uri alertSnapshotUri(String alertId) => Uri.parse(
    '${AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/alerts/$alertId/snapshot',
  );

  Options get _options => Options(
    headers: _token == null ? null : {'Authorization': 'Bearer $_token'},
  );

  Future<SceneCue> analyze(
    Uint8List jpeg, {
    String language = 'English',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/vision/analyze',
      data: jpeg,
      queryParameters: {'language': language},
      options: Options(
        contentType: 'image/jpeg',
        headers: _token == null ? null : {'Authorization': 'Bearer $_token'},
      ),
    );
    return SceneCue.fromJson(response.data ?? const {});
  }

  Future<void> registerDevice(
    String fcmToken, {
    required UserRole role,
    required String displayName,
  }) => _dio.post<void>(
    '/v1/devices/register',
    data: {
      'platform': 'android',
      'pushToken': fcmToken,
      'role': role.name,
      'displayName': displayName,
    },
    options: _options,
  );

  Future<EmergencyAlert> createAlert({
    required String idempotencyKey,
    required double? latitude,
    required double? longitude,
    required double? accuracy,
    required String triggerSource,
    Uint8List? lastFrame,
    SceneCue? lastCue,
    DateTime? snapshotCapturedAt,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/alerts',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'triggerSource': triggerSource,
        if (lastFrame != null) 'imageBase64': base64Encode(lastFrame),
        if (lastCue != null) 'lastCue': lastCue.cue,
        if (lastCue != null) 'lastDetails': lastCue.details,
        if (lastCue != null) 'lastRisk': lastCue.risk.name,
        if (lastCue != null) 'lastConfidence': lastCue.confidence,
        if (snapshotCapturedAt != null)
          'snapshotCapturedAt': snapshotCapturedAt.toUtc().toIso8601String(),
      },
      options: Options(
        headers: {
          if (_token != null) 'Authorization': 'Bearer $_token',
          'Idempotency-Key': idempotencyKey,
        },
      ),
    );
    return EmergencyAlert.fromJson(response.data ?? const {});
  }

  Future<void> updateLocation(
    String alertId, {
    required double latitude,
    required double longitude,
    required double accuracy,
  }) => _dio.put<void>(
    '/v1/alerts/$alertId/location',
    data: {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    },
    options: _options,
  );

  Future<void> alertAction(String alertId, String action) =>
      _dio.post<void>('/v1/alerts/$alertId/$action', options: _options);

  Future<List<EmergencyAlert>> activeAlerts() async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/alerts/active',
      options: _options,
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmergencyAlert.fromJson)
        .toList();
  }

  Future<String> createInvite() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/contacts/invites',
      options: _options,
    );
    return response.data?['code'] as String? ?? '';
  }

  Future<void> redeemInvite(String code) => _dio.post<void>(
    '/v1/contacts/invites/redeem',
    data: {'code': code.trim()},
    options: _options,
  );

  Future<List<TrustedContact>> contacts() async {
    final response = await _dio.get<List<dynamic>>(
      '/v1/contacts',
      options: _options,
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TrustedContact.fromJson)
        .toList();
  }
}
