import 'dart:math' as math;

class NavPoint {
  const NavPoint(this.latitude, this.longitude);
  final double latitude, longitude;
  factory NavPoint.json(Map<String, dynamic> j) => NavPoint(
    (j['latitude'] as num).toDouble(),
    (j['longitude'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
  double distance(NavPoint p) {
    const r = 6371000.0;
    final a = latitude * math.pi / 180, b = p.latitude * math.pi / 180;
    final d = (p.latitude - latitude) * math.pi / 180,
        l = (p.longitude - longitude) * math.pi / 180;
    final h =
        math.pow(math.sin(d / 2), 2) +
        math.cos(a) * math.cos(b) * math.pow(math.sin(l / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.clamp(0, 1)));
  }
}

List<NavPoint> decodePolyline(String encoded) {
  final points = <NavPoint>[];
  int index = 0, lat = 0, lng = 0;
  int number() {
    int value = 0, shift = 0, b;
    do {
      if (index >= encoded.length || shift > 30) {
        throw const FormatException('Invalid route geometry');
      }
      b = encoded.codeUnitAt(index++) - 63;
      value |= (b & 31) << shift;
      shift += 5;
    } while (b >= 32);
    return (value & 1) != 0 ? ~(value >> 1) : value >> 1;
  }

  while (index < encoded.length) {
    lat += number();
    lng += number();
    points.add(NavPoint(lat / 1e5, lng / 1e5));
  }
  return points;
}

class NavPlace {
  NavPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.attributions = const [],
  });
  final String id, name, address;
  final NavPoint location;
  final List<String> attributions;
  factory NavPlace.json(Map<String, dynamic> j) => NavPlace(
    id: j['id'],
    name: j['name'],
    address: j['address'],
    location: NavPoint.json(j['location']),
    attributions: (j['attributions'] as List? ?? [])
        .map((a) => a['provider']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(),
  );
}

class NavStep {
  NavStep({
    required this.instruction,
    required this.start,
    required this.end,
    required this.distance,
    required this.points,
  });
  final String instruction;
  final NavPoint start, end;
  final double distance;
  final List<NavPoint> points;
  factory NavStep.json(Map<String, dynamic> j) => NavStep(
    instruction: j['instruction'],
    start: NavPoint.json(j['start']),
    end: NavPoint.json(j['end']),
    distance: (j['distanceMeters'] as num).toDouble(),
    points: decodePolyline(j['polyline'] ?? ''),
  );
}

class WalkingRoute {
  WalkingRoute({
    required this.steps,
    required this.points,
    required this.distance,
    required this.seconds,
    required this.warnings,
  });
  final List<NavStep> steps;
  final List<NavPoint> points;
  final double distance;
  final int seconds;
  final List<String> warnings;
  factory WalkingRoute.json(Map<String, dynamic> j) => WalkingRoute(
    steps: (j['steps'] as List).map((s) => NavStep.json(s)).toList(),
    points: decodePolyline(j['polyline']),
    distance: (j['distanceMeters'] as num).toDouble(),
    seconds: j['durationSeconds'],
    warnings: List<String>.from(j['warnings']),
  );
}

class NavigationState {
  const NavigationState({
    this.busy = false,
    this.active = false,
    this.paused = false,
    this.places = const [],
    this.destination,
    this.route,
    this.position,
    this.step = 0,
    this.message = '',
    this.guidance = '',
    this.error,
    this.confirmation = 'none',
    this.candidateIndex = 0,
  });
  final bool busy, active, paused;
  final List<NavPlace> places;
  final NavPlace? destination;
  final WalkingRoute? route;
  final NavPoint? position;
  final int step;
  final String message, guidance;
  final String? error;
  final String confirmation;
  final int candidateIndex;
  NavigationState copyWith({
    bool? busy,
    bool? active,
    bool? paused,
    List<NavPlace>? places,
    NavPlace? destination,
    WalkingRoute? route,
    NavPoint? position,
    int? step,
    String? message,
    String? guidance,
    String? error,
    bool clearError = false,
    String? confirmation,
    int? candidateIndex,
  }) => NavigationState(
    busy: busy ?? this.busy,
    active: active ?? this.active,
    paused: paused ?? this.paused,
    places: places ?? this.places,
    destination: destination ?? this.destination,
    route: route ?? this.route,
    position: position ?? this.position,
    step: step ?? this.step,
    message: message ?? this.message,
    guidance: guidance ?? this.guidance,
    error: clearError ? null : error ?? this.error,
    confirmation: confirmation ?? this.confirmation,
    candidateIndex: candidateIndex ?? this.candidateIndex,
  );
}

/// Geometric progress only. Never treats a map route as proof of walking safety.
class WalkingProgress {
  WalkingProgress(this.route);
  final WalkingRoute route;
  int step = 0, offRouteFixes = 0, arrivalFixes = 0;
  double traveled = 0;
  NavPoint? previous;
  DateTime? previousTime;
  bool get arrived => arrivalFixes >= 2;
  String update(
    NavPoint point,
    double accuracy,
    DateTime timestamp,
    DateTime now,
  ) {
    if (accuracy > 25 ||
        accuracy < 0 ||
        now.difference(timestamp).inSeconds > 12 ||
        timestamp.isAfter(now.add(const Duration(seconds: 5)))) {
      return 'gps';
    }
    if (previousTime != null && !timestamp.isAfter(previousTime!)) {
      return 'ignored';
    }
    if (previous != null) {
      final seconds = timestamp.difference(previousTime!).inMilliseconds / 1000;
      final delta = previous!.distance(point);
      if (delta > math.max(50, seconds * 5 + accuracy * 2)) return 'gps';
      traveled += delta;
    }
    previous = point;
    previousTime = timestamp;
    final current = route.steps[step];
    final points = current.points.length > 1
        ? current.points
        : [current.start, current.end];
    final lineDistance = distanceToLine(point, points);
    if (lineDistance > math.max(35, accuracy * 2)) {
      offRouteFixes++;
      return offRouteFixes >= 3 ? 'offRoute' : 'uncertain';
    }
    offRouteFixes = 0;
    final remaining = point.distance(current.end);
    if (remaining < 12 && traveled >= math.min(10, current.distance * .5)) {
      if (step == route.steps.length - 1) {
        arrivalFixes++;
        return arrived ? 'arrived' : 'near';
      }
      step++;
      traveled = 0;
      return 'step';
    }
    arrivalFixes = 0;
    return remaining < 40 ? 'approaching' : 'ok';
  }

  static double distanceToLine(NavPoint p, List<NavPoint> points) {
    var best = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final scale = math.cos(p.latitude * math.pi / 180);
      final ax = (a.longitude - p.longitude) * 111320 * scale,
          ay = (a.latitude - p.latitude) * 111320;
      final bx = (b.longitude - p.longitude) * 111320 * scale,
          by = (b.latitude - p.latitude) * 111320;
      final dx = bx - ax, dy = by - ay, den = dx * dx + dy * dy;
      final t = den == 0 ? 0.0 : (-(ax * dx + ay * dy) / den).clamp(0.0, 1.0);
      best = math.min(
        best,
        math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
      );
    }
    return best;
  }
}
