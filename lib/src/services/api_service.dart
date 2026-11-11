import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/models.dart';

Uri navigationMediaUri(String liveUrl, String path) {
  final base = Uri.parse(liveUrl);
  return Uri(
    scheme: 'https',
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: path,
  );
}

class ApiService {
  Future<Map<String, dynamic>> navigation(
    String action,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post('/v1/navigation/$action', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  ApiService({Future<String?> Function()? accessTokenProvider})
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 25),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    if (accessTokenProvider != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            try {
              final token = await accessTokenProvider();
              setAccessToken(token);
              options.headers.remove('Authorization');
              if (token != null) {
                options.headers['Authorization'] = 'Bearer $token';
              }
              handler.next(options);
            } catch (_) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  error:
                      'Could not refresh your session. Check your connection or sign in again.',
                ),
              );
            }
          },
        ),
      );
    }
  }

  final Dio _dio;
  Uri _liveEndpoint(String path) =>
      navigationMediaUri(AppConfig.geminiLiveUrl, path);

  Future<Uint8List> navigationSpeech(String text, String language) async {
    final response = await _dio.post<List<int>>(
      _liveEndpoint('/speech').toString(),
      data: {'text': text, 'language': language},
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<List<String>> translateNavigation(
    List<String> texts,
    String language,
  ) async {
    final response = await _dio.post(
      _liveEndpoint('/navigation/translate').toString(),
      data: {'texts': texts, 'language': language},
    );
    return List<String>.from(response.data['texts']);
  }

  String? _token;

  void setAccessToken(String? token) => _token = token;
  Future<void> testNotification() async {
    await _dio.post<void>('/v1/notifications/test', options: _options);
  }

  Future<Map<String, dynamic>> askQuestion(
    Uint8List wav,
    Uint8List? image, {
    String language = 'auto',
    String navigationPrompt = 'none',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/assistant/ask',
      data: {
        'audioBase64': base64Encode(wav),
        if (navigationPrompt != 'none') 'navigationPrompt': navigationPrompt,
        'language': language,
        if (image != null) 'imageBase64': base64Encode(image),
      },
      options: Options(
        headers: _options.headers,
        receiveTimeout: const Duration(seconds: 40),
      ),
    );
    return response.data ?? const {};
  }

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

  Future<void> registerProfile({
    required UserRole role,
    required String displayName,
  }) => _dio.post<void>(
    '/v1/profile',
    data: {'role': role.name, 'displayName': displayName},
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
