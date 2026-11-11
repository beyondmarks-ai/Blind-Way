import 'dart:async';
import '../config/navigation_strings.dart';
import 'package:geolocator/geolocator.dart';
import '../models/navigation.dart';
import 'location_service.dart';
import 'api_service.dart';

class WalkingNavigation {
  WalkingNavigation({
    required this.api,
    required this.location,
    required this.language,
    required this.publish,
    required this.say,
  });
  final ApiService api;
  final LocationService location;
  final String Function() language;
  final void Function(NavigationState) publish;
  final Future<void> Function(String, bool) say;
  NavigationState state = const NavigationState();
  StreamSubscription<Position>? _positions;
  Timer? _watchdog;
  WalkingProgress? _progress;
  int _epoch = 0;
  int _approachStep = -1;
  DateTime? _lastFix;
  bool _announcing = false;
  Future<void> _speechQueue = Future<void>.value();
  String _lastAnnouncement = '';
  DateTime? _replyUntil;
  String _routeLanguage = '';
  String t(String source, [Map<String, Object> values = const {}]) =>
      NavigationStrings(language()).text(source, values);
  String get prompt =>
      _replyUntil != null && DateTime.now().isBefore(_replyUntil!)
      ? state.confirmation
      : 'none';

  Future<void> askConfirmation(String text, String kind) async {
    final epoch = _epoch;
    _replyUntil = null;
    update(state.copyWith(confirmation: 'none', message: text));
    _lastAnnouncement = '';
    await announce(text);
    if (epoch != _epoch) return;
    _replyUntil = DateTime.now().add(const Duration(seconds: 60));
    update(state.copyWith(confirmation: kind));
  }

  Future<void> offer(int index) async {
    if (index >= state.places.length) {
      await stop(silent: true);
      await announce(
        'There are no more matches. Say take me to, followed by the place name and area, to search again.',
      );
      return;
    }
    final place = state.places[index];
    update(state.copyWith(candidateIndex: index));
    await askConfirmation(
      t(
        'I found {name}, {address}. Is this the place you mean? After the beep, say yes to choose this place, no for another place, or say repeat to hear this address again.',
        {'name': place.name, 'address': place.address},
      ),
      'destination',
    );
  }

  Future<void> reply(bool yes) async {
    final pending = prompt;
    if (pending == 'none' || state.busy) return;
    _replyUntil = null;
    update(state.copyWith(confirmation: 'none'));
    if (pending == 'destination') {
      if (yes) {
        await choose(state.candidateIndex + 1);
      } else {
        await offer(state.candidateIndex + 1);
      }
    } else if (yes) {
      await start();
    } else {
      await stop(silent: true);
      await announce(
        'Okay, walking guidance has not started. Say take me to a place whenever you are ready.',
      );
    }
  }

  void update(NavigationState value) {
    state = value.copyWith(
      message: t(value.message),
      guidance: t(value.guidance),
      error: value.error == null ? null : t(value.error!),
    );
    publish(state);
  }

  Map<String, dynamic> origin(Position p) => {
    'latitude': p.latitude,
    'longitude': p.longitude,
    'accuracy': p.accuracy,
    'recordedAt': p.timestamp.toUtc().toIso8601String(),
  };
  Future<void> announce(String text, {bool localized = false}) async {
    text = t(text);
    if (text == _lastAnnouncement) return;
    _lastAnnouncement = text;
    final epoch = _epoch;
    _speechQueue = _speechQueue.then((_) async {
      if (epoch != _epoch ||
          (localized && (state.error != null || state.paused))) {
        return;
      }
      _announcing = true;
      try {
        await say(text, localized);
      } catch (_) {
        /* Route remains visible if voice fails. */
      } finally {
        _announcing = false;
      }
    });
    await _speechQueue;
  }

  Future<void> search(String query) async {
    await stop(silent: true);
    final epoch = ++_epoch;
    update(
      NavigationState(
        busy: true,
        message: 'Finding your location and destination...',
      ),
    );
    try {
      final p = await location.navigationFix();
      if (epoch != _epoch) return;
      final data = await api.navigation('search', {
        'query': query,
        'origin': origin(p),
        'language': language(),
      });
      if (epoch != _epoch) return;
      final places = (data['places'] as List)
          .map((j) => NavPlace.json(j))
          .toList();
      update(
        state.copyWith(
          busy: false,
          position: NavPoint(p.latitude, p.longitude),
          places: places,
          message: places.isEmpty
              ? 'No matching place. Try a name with its area.'
              : 'Confirm the destination by voice.',
        ),
      );
      if (places.isEmpty) {
        await announce(state.message);
      } else {
        await offer(0);
      }
    } catch (_) {
      if (epoch == _epoch) {
        await fail(
          'Could not find the destination. Check precise location and internet, then try again.',
        );
      }
    }
  }

  Future<void> choose(int index) async {
    _replyUntil = null;
    if (index < 1 || index > state.places.length) {
      await announce('Choose a place number from the search results.');
      return;
    }
    final epoch = ++_epoch, place = state.places[index - 1];
    await _positions?.cancel();
    _watchdog?.cancel();
    _progress = null;
    update(
      NavigationState(
        busy: true,
        places: state.places,
        position: state.position,
        destination: place,
        message: 'Getting a walking route...',
      ),
    );
    try {
      final p = await location.navigationFix();
      if (epoch != _epoch) return;
      final data = await api.navigation('route', {
        'placeId': place.id,
        'origin': origin(p),
        'language': language(),
      });
      if (epoch != _epoch) return;
      // Google may return warnings or unsupported locales in English. Translate
      // only while preparing the route, never at each GPS update.
      if (!language().startsWith('en-')) {
        final steps = (data['steps'] as List).cast<Map>();
        final warnings = List<String>.from(data['warnings']);
        final source = [
          ...steps.map((s) => s['instruction'] as String),
          ...warnings,
        ];
        final translated = <String>[];
        for (var offset = 0; offset < source.length; offset += 20) {
          final end = (offset + 20).clamp(0, source.length);
          translated.addAll(
            await api.translateNavigation(
              source.sublist(offset, end),
              language(),
            ),
          );
          if (epoch != _epoch) return;
        }
        if (translated.length != source.length) {
          throw StateError('Incomplete route translation');
        }
        for (var i = 0; i < steps.length; i++) {
          steps[i]['instruction'] = translated[i];
        }
        data['warnings'] = translated.sublist(steps.length);
      }
      final route = WalkingRoute.json(data);
      _routeLanguage = language();
      update(
        state.copyWith(
          busy: false,
          route: route,
          position: NavPoint(p.latitude, p.longitude),
          step: 0,
          message: 'Route ready. Confirm to start.',
          guidance: route.steps.first.instruction,
        ),
      );
      await askConfirmation(
        t(
          '{name}. Walking distance: {metres} metres. Estimated time: {minutes} minutes. {warnings} Do you want to start spoken directions? After the beep, say yes to start, or no to cancel.',
          {
            'name': place.name,
            'metres': route.distance.round(),
            'minutes': (route.seconds / 60).ceil(),
            'warnings': route.warnings.map(t).join(' '),
          },
        ),
        'start',
      );
    } catch (_) {
      if (epoch == _epoch) {
        await fail(
          'A walking route is unavailable. Check GPS and internet, or choose another destination.',
        );
      }
    }
  }

  Future<void> start() async {
    if (state.busy) return;
    _replyUntil = null;
    update(state.copyWith(confirmation: 'none'));
    if (state.route == null) {
      if (state.places.length == 1) {
        await choose(1);
      } else {
        await announce('First choose a destination from the search results.');
      }
      return;
    }
    if (_routeLanguage != language()) {
      await changeLanguage();
      return;
    }
    final epoch = ++_epoch;
    try {
      final p = await location.navigationFix();
      if (epoch != _epoch) return;
      if (NavPoint(
            p.latitude,
            p.longitude,
          ).distance(state.route!.steps.first.start) >
          40) {
        await choose(state.places.indexOf(state.destination!) + 1);
        return;
      }
      await _positions?.cancel();
      _watchdog?.cancel();
      _progress = WalkingProgress(state.route!);
      _approachStep = -1;
      _lastFix = DateTime.now();
      update(
        state.copyWith(
          active: true,
          paused: false,
          clearError: true,
          step: 0,
          message: 'Walking route active.',
          guidance: state.route!.steps.first.instruction,
          position: NavPoint(p.latitude, p.longitude),
        ),
      );
      _positions = location.navigationUpdates().listen(
        onPosition,
        onError: (Object _) => gpsLost(),
      );
      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (state.active &&
            _lastFix != null &&
            DateTime.now().difference(_lastFix!).inSeconds > 15) {
          gpsLost();
        }
      });
      await announce(state.route!.steps.first.instruction, localized: true);
    } catch (_) {
      if (epoch == _epoch) {
        await fail(
          'Cannot start walking guidance without a precise current GPS location.',
        );
      }
    }
  }

  void onPosition(Position p) {
    if (!state.active || state.paused || _progress == null) return;
    final point = NavPoint(p.latitude, p.longitude),
        result = _progress!.update(
          point,
          p.accuracy,
          p.timestamp,
          DateTime.now(),
        );
    if (result == 'gps') {
      gpsLost();
      return;
    }
    if (result == 'ignored') return;
    _lastFix = DateTime.now();
    update(
      state.copyWith(
        position: point,
        step: _progress!.step,
        clearError: true,
        message: 'Walking route active.',
      ),
    );
    if (result == 'offRoute') {
      update(
        state.copyWith(
          paused: true,
          message: 'You may be off the mapped route. Guidance paused.',
        ),
      );
      unawaited(
        announce(
          'You may be off the mapped route. Guidance is paused. Say reroute to get a new walking route from your current location.',
        ),
      );
      return;
    }
    if (result == 'uncertain') return;
    if (result == 'arrived') {
      update(
        state.copyWith(
          active: false,
          message: 'Near the destination. Entrance not verified.',
        ),
      );
      _positions?.cancel();
      _watchdog?.cancel();
      unawaited(
        announce(
          t(
            'You are near {name}. GPS cannot identify the entrance. Confirm it with your usual mobility aid or ask for assistance.',
            {'name': state.destination!.name},
          ),
        ),
      );
      return;
    }
    final step = state.route!.steps[state.step];
    if (result == 'step') {
      update(state.copyWith(guidance: step.instruction));
      unawaited(announce(step.instruction, localized: true));
    } else if (result == 'approaching' &&
        _approachStep != state.step &&
        !_announcing &&
        state.step + 1 < state.route!.steps.length) {
      final next = state.route!.steps[state.step + 1];
      _approachStep = state.step;
      final metres = (point.distance(step.end) / 10).round().clamp(1, 4) * 10;
      unawaited(
        announce(
          t(
            'Prepare for the next instruction in about {metres} metres. {instruction}',
            {'metres': metres, 'instruction': next.instruction},
          ),
          localized: true,
        ),
      );
    }
  }

  void gpsLost() {
    if (!state.active || state.paused || state.error != null) return;
    update(
      state.copyWith(
        error:
            'GPS is inaccurate or unavailable. Waiting for a precise location.',
        message: 'Direction updates paused until GPS recovers.',
      ),
    );
    unawaited(
      announce(
        'GPS is inaccurate or unavailable. Directions are paused until location improves.',
      ),
    );
  }

  Future<void> changeLanguage() async {
    if (state.destination != null && state.route != null) {
      await choose(state.places.indexOf(state.destination!) + 1);
    } else if (state.places.isNotEmpty) {
      ++_epoch;
      await offer(state.candidateIndex);
    }
  }

  Future<void> repeat() async {
    if (state.route != null && _routeLanguage != language()) {
      await changeLanguage();
      return;
    }
    if (state.confirmation != 'none') {
      await askConfirmation(state.message, state.confirmation);
      return;
    }
    if (state.paused || state.error != null) {
      _lastAnnouncement = '';
      await announce(state.error ?? state.message);
      return;
    }
    _lastAnnouncement = '';
    await announce(
      state.guidance.isNotEmpty
          ? state.guidance
          : 'No walking route is active.',
      localized: state.guidance.isNotEmpty,
    );
  }

  Future<void> pause() async {
    update(state.copyWith(paused: true, message: 'Walking guidance paused.'));
    await announce('Walking guidance paused.');
  }

  Future<void> resume() async {
    if (!state.active) return;
    try {
      final epoch = _epoch, p = await location.navigationFix();
      if (epoch != _epoch) return;
      update(state.copyWith(paused: false, clearError: true));
      onPosition(p);
      if (state.error == null && !state.paused) await repeat();
    } catch (_) {
      gpsLost();
    }
  }

  Future<void> reroute() async {
    final index = state.places.indexOf(state.destination!);
    await _positions?.cancel();
    _watchdog?.cancel();
    update(state.copyWith(active: false, paused: false));
    await choose(index + 1);
  }

  Future<void> fail(String text) async {
    update(state.copyWith(busy: false, error: text, message: text));
    await announce(text);
  }

  Future<void> stop({bool silent = false}) async {
    ++_epoch;
    _replyUntil = null;
    await _positions?.cancel();
    _positions = null;
    _watchdog?.cancel();
    _progress = null;
    _lastAnnouncement = '';
    update(const NavigationState());
    if (!silent) await announce('Walking navigation stopped.');
  }

  void dispose() {
    ++_epoch;
    _positions?.cancel();
    _watchdog?.cancel();
  }
}
