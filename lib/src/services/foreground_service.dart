import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void assistanceTaskEntryPoint() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_AssistanceTaskHandler());
}

class _AssistanceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class ForegroundService {
  void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'assistance_service',
        channelName: 'Blind Way safety service',
        channelDescription:
            'Shows while voice safety listening or vision assistance is active.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
        stopWithTask: false,
      ),
    );
  }

  Future<void> start({bool includeLocation = false}) async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 4101,
      serviceTypes: [
        ForegroundServiceTypes.specialUse,
        ForegroundServiceTypes.connectedDevice,
        ForegroundServiceTypes.microphone,
        if (includeLocation) ForegroundServiceTypes.location,
      ],
      notificationTitle: 'Blind Way safety is active',
      notificationText:
          'Listening for the emergency wake word and camera guidance.',
      notificationButtons: const [NotificationButton(id: 'stop', text: 'Stop')],
      callback: assistanceTaskEntryPoint,
    );
  }

  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
