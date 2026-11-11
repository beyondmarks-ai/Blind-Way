import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  bool get pushAvailable => Firebase.apps.isNotEmpty;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Stream<RemoteMessage> get openedAlerts =>
      FirebaseMessaging.onMessageOpenedApp;

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _local.initialize(settings: settings);
    const emergencyChannel = AndroidNotificationChannel(
      'emergency_alerts',
      'Emergency alerts',
      description: 'Urgent alerts from trusted Blind Way users',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(emergencyChannel);
    if (!pushAvailable) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: false,
    );
    FirebaseMessaging.onMessage.listen(showRemoteMessage);
  }

  Future<void> showRemoteMessage(RemoteMessage message) => _local.show(
    id: message.messageId.hashCode,
    title: message.notification?.title ?? 'Blind Way emergency',
    body: message.notification?.body ?? 'A trusted user needs help.',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'emergency_alerts',
        'Emergency alerts',
        channelDescription: 'Urgent alerts from trusted Blind Way users',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
      ),
    ),
    payload: message.data['alertId'] as String?,
  );

  Future<String?> token() async {
    if (!pushAvailable) return null;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return null;
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> clearToken() async {
    if (!pushAvailable) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Registration transfers this installation to its next signed-in account.
    }
  }
}
