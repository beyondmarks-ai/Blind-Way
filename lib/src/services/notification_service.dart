import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
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

  Future<String?> token() => FirebaseMessaging.instance.getToken();
}
