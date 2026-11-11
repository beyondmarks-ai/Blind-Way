import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:blind_way/src/models/navigation.dart';
import 'package:blind_way/src/services/walking_navigation.dart';
import 'package:blind_way/src/services/location_service.dart';
import 'package:blind_way/src/services/api_service.dart';

class MapsApi extends Mock implements ApiService {}

class Gps extends Mock implements LocationService {}

Position fix() => Position(
  latitude: 12,
  longitude: 77,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 5,
  heading: 0,
  headingAccuracy: 5,
  speed: 0,
  speedAccuracy: 1,
);
Map<String, dynamic> routeJson() => {
  'distanceMeters': 111,
  'durationSeconds': 100,
  'polyline': '',
  'warnings': ['Use caution'],
  'steps': [
    {
      'distanceMeters': 111,
      'instruction': 'Head north',
      'start': {'latitude': 12.0, 'longitude': 77.0},
      'end': {'latitude': 12.001, 'longitude': 77.0},
      'polyline': '',
    },
  ],
};
void main() {
  test(
    'changing route language stops tracking and obtains translated directions before reconfirming',
    () async {
      final api = MapsApi(), gps = Gps(), spoken = <String>[];
      final positions = StreamController<Position>();
      var language = 'kn-IN';
      when(() => gps.navigationFix()).thenAnswer((_) async => fix());
      when(() => gps.navigationUpdates()).thenAnswer((_) => positions.stream);
      when(() => api.navigation('search', any())).thenAnswer(
        (_) async => {
          'places': [
            {
              'id': 'Park',
              'name': 'Park',
              'address': 'Road 12',
              'location': {'latitude': 12, 'longitude': 77},
            },
          ],
        },
      );
      when(
        () => api.navigation('route', any()),
      ).thenAnswer((_) async => routeJson());
      when(() => api.translateNavigation(any(), any())).thenAnswer(
        (call) async => (call.positionalArguments[0] as List<String>)
            .map((text) => '$language: $text')
            .toList(),
      );
      final nav = WalkingNavigation(
        api: api,
        location: gps,
        language: () => language,
        publish: (_) {},
        say: (text, _) async {
          spoken.add(text);
        },
      );
      await nav.search('Park');
      expect(spoken.last, contains('Road 12'));
      expect(spoken.last, isNot(contains('Is this the place')));
      await nav.reply(true);
      expect(nav.state.route!.steps.first.instruction, 'kn-IN: Head north');
      expect(
        spoken.last,
        isNot(contains('Do you want to start spoken directions')),
      );
      await nav.reply(true);
      expect(nav.state.active, true);
      language = 'de-DE';
      await nav.changeLanguage();
      expect(positions.hasListener, false);
      expect(nav.state.active, false);
      expect(nav.prompt, 'start');
      expect(nav.state.route!.steps.first.instruction, 'de-DE: Head north');
      expect(spoken.last, contains('Möchten Sie'));
      await nav.stop(silent: true);
      await positions.close();
      nav.dispose();
    },
  );
  test(
    'spoken no advances one address, yes previews, and a second yes starts',
    () async {
      final api = MapsApi(), gps = Gps(), spoken = <String>[];
      final positions = StreamController<Position>();
      when(() => gps.navigationFix()).thenAnswer((_) async => fix());
      when(() => gps.navigationUpdates()).thenAnswer((_) => positions.stream);
      when(() => api.navigation('search', any())).thenAnswer(
        (_) async => {
          'places': [
            for (final name in ['First Park', 'Second Park'])
              {
                'id': name,
                'name': name,
                'address': '$name Road',
                'location': {'latitude': 12, 'longitude': 77},
              },
          ],
        },
      );
      when(
        () => api.navigation('route', any()),
      ).thenAnswer((_) async => routeJson());
      final nav = WalkingNavigation(
        api: api,
        location: gps,
        language: () => 'en-IN',
        publish: (_) {},
        say: (text, _) async {
          spoken.add(text);
        },
      );
      await nav.search('Park');
      expect(nav.prompt, 'destination');
      expect(spoken.last, contains('First Park'));
      expect(spoken.last, isNot(contains('Second Park')));
      await nav.reply(false);
      expect(spoken.last, contains('Second Park'));
      verifyNever(() => api.navigation('route', any()));
      await nav.reply(true);
      expect(nav.state.destination!.name, 'Second Park');
      expect(nav.prompt, 'start');
      expect(nav.state.active, false);
      verifyNever(() => gps.navigationUpdates());
      await nav.reply(true);
      expect(nav.state.active, true);
      expect(nav.prompt, 'none');
      await nav.stop(silent: true);
      await nav.reply(true);
      expect(nav.state.active, false);
      verify(() => gps.navigationUpdates()).called(1);
      await positions.close();
      nav.dispose();
    },
  );
  test('stopping during a spoken address cannot reopen confirmation', () async {
    final api = MapsApi(), gps = Gps(), speech = Completer<void>();
    when(() => gps.navigationFix()).thenAnswer((_) async => fix());
    when(() => api.navigation('search', any())).thenAnswer(
      (_) async => {
        'places': [
          {
            'id': 'park',
            'name': 'Park',
            'address': 'Road',
            'location': {'latitude': 12, 'longitude': 77},
          },
        ],
      },
    );
    final nav = WalkingNavigation(
      api: api,
      location: gps,
      language: () => 'en-IN',
      publish: (_) {},
      say: (_, _) => speech.future,
    );
    final searching = nav.search('Park');
    await Future<void>.delayed(Duration.zero);
    await nav.stop(silent: true);
    speech.complete();
    await searching;
    expect(nav.prompt, 'none');
    await nav.reply(true);
    verifyNever(() => api.navigation('route', any()));
    nav.dispose();
  });
  test('GPS error and jumps never advance or announce arrival', () {
    final progress = WalkingProgress(WalkingRoute.json(routeJson()));
    final now = DateTime.now();
    expect(progress.update(const NavPoint(12, 77), 5, now, now), 'ok');
    expect(
      progress.update(
        const NavPoint(12.001, 77),
        100,
        now.add(const Duration(seconds: 1)),
        now.add(const Duration(seconds: 1)),
      ),
      'gps',
    );
    expect(
      progress.update(
        const NavPoint(12.001, 77),
        5,
        now.add(const Duration(seconds: 1)),
        now.add(const Duration(seconds: 1)),
      ),
      'gps',
    );
    expect(progress.arrived, false);
    expect(
      progress.update(
        const NavPoint(12.001, 77),
        5,
        now,
        now.add(const Duration(minutes: 2)),
      ),
      'gps',
    );
  });
  test(
    'arrival needs progression and two distinct accurate fixes near the end',
    () {
      final progress = WalkingProgress(WalkingRoute.json(routeJson()));
      final start = DateTime.now();
      for (var i = 0; i <= 9; i++) {
        final time = start.add(Duration(seconds: i * 5));
        progress.update(NavPoint(12 + i * .0001, 77), 5, time, time);
      }
      expect(progress.arrived, false);
      final later = start.add(const Duration(seconds: 55));
      expect(
        progress.update(const NavPoint(12.001, 77), 5, later, later),
        'arrived',
      );
      expect(progress.arrived, true);
    },
  );
  test('off-route requires three reliable fixes away from the path', () {
    final p = WalkingProgress(WalkingRoute.json(routeJson()));
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      final t = now.add(Duration(seconds: i * 3));
      expect(
        p.update(const NavPoint(12, 77.001), 5, t, t),
        i < 2 ? 'uncertain' : 'offRoute',
      );
    }
  });
  test('polyline decoding matches the Google reference example', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.length, 3);
    expect(points.first.latitude, 38.5);
    expect(points.last.longitude, -126.453);
  });
  test(
    'cancelling an outstanding search cannot restore a destination',
    () async {
      final api = MapsApi(),
          gps = Gps(),
          pending = Completer<Map<String, dynamic>>();
      when(() => gps.navigationFix()).thenAnswer((_) async => fix());
      when(
        () => api.navigation(any(), any()),
      ).thenAnswer((_) => pending.future);
      final nav = WalkingNavigation(
        api: api,
        location: gps,
        language: () => 'en-IN',
        publish: (_) {},
        say: (_, _) async {},
      );
      final task = nav.search('Park');
      await Future<void>.delayed(Duration.zero);
      await nav.stop(silent: true);
      pending.complete({
        'places': [
          {
            'id': 'park-1',
            'name': 'Park',
            'address': 'Road',
            'location': {'latitude': 12, 'longitude': 77},
          },
        ],
      });
      await task;
      expect(nav.state.places, isEmpty);
      expect(nav.state.active, false);
      nav.dispose();
    },
  );
  test(
    'choosing a destination previews a route but never starts tracking without confirmation',
    () async {
      final api = MapsApi(), gps = Gps();
      when(() => gps.navigationFix()).thenAnswer((_) async => fix());
      when(() => api.navigation('search', any())).thenAnswer(
        (_) async => {
          'places': [
            {
              'id': 'park-1',
              'name': 'Park',
              'address': 'Road',
              'location': {'latitude': 12.001, 'longitude': 77},
            },
          ],
        },
      );
      when(
        () => api.navigation('route', any()),
      ).thenAnswer((_) async => routeJson());
      final nav = WalkingNavigation(
        api: api,
        location: gps,
        language: () => 'en-IN',
        publish: (_) {},
        say: (_, _) async {},
      );
      await nav.search('Park');
      await nav.choose(1);
      expect(nav.state.active, false);
      expect(nav.state.route, isNotNull);
      verifyNever(() => gps.navigationUpdates());
      final positions = StreamController<Position>();
      when(() => gps.navigationUpdates()).thenAnswer((_) => positions.stream);
      await nav.start();
      expect(nav.state.active, true);
      expect(nav.state.guidance, 'Head north');
      verify(() => gps.navigationUpdates()).called(1);
      await nav.pause();
      nav.gpsLost();
      expect(nav.state.paused, true);
      expect(nav.state.error, isNull);
      await nav.stop(silent: true);
      expect(positions.hasListener, false);
      await positions.close();
      nav.dispose();
    },
  );
}
