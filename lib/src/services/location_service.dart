import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> navigationFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on phone location for walking directions.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Precise location permission is required for walking directions.',
      );
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 15),
      ),
    );
    if (p.accuracy > 30 ||
        DateTime.now().difference(p.timestamp).inSeconds > 20) {
      throw StateError(
        'GPS is not precise enough. Try outdoors and request the route again.',
      );
    }
    return p;
  }

  Stream<Position> navigationUpdates() => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Blind Way walking route',
        notificationText: 'GPS guidance is active. Open Blind Way to stop.',
        enableWakeLock: true,
      ),
    ),
  );
  Future<Position?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return Geolocator.getLastKnownPosition();
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }
}
