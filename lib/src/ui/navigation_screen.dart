import 'package:flutter/material.dart';
import '../config/navigation_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../state/app_controller.dart';
import '../models/navigation.dart';

class WalkingNavigationScreen extends ConsumerStatefulWidget {
  const WalkingNavigationScreen({super.key});
  @override
  ConsumerState<WalkingNavigationScreen> createState() =>
      _WalkingNavigationScreenState();
}

class _WalkingNavigationScreenState
    extends ConsumerState<WalkingNavigationScreen> {
  final _destination = TextEditingController();
  GoogleMapController? _map;
  @override
  void dispose() {
    _destination.dispose();
    _map?.dispose();
    super.dispose();
  }

  LatLng point(NavPoint p) => LatLng(p.latitude, p.longitude);
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider),
        nav = app.navigation,
        controller = ref.read(appControllerProvider.notifier);
    ref.listen(appControllerProvider, (before, after) {
      final p = after.navigation.position;
      if (p != null && p != before?.navigation.position) {
        _map?.animateCamera(
          before?.navigation.position == null
              ? CameraUpdate.newLatLngZoom(point(p), 16)
              : CameraUpdate.newLatLng(point(p)),
        );
      }
    });
    final words = NavigationStrings(
      app.language == 'auto' ? controller.navigation.language() : app.language,
    );
    String t(String source, [Map<String, Object> values = const {}]) =>
        words.text(source, values);
    final disabled =
        nav.busy || app.activeAlert != null || app.sosCountdown != null;
    return Scaffold(
      appBar: AppBar(title: Text(t('Walking directions'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t(
              'Say “Hey Jarvis”, pause, then “Take me to…” with the place and area. Jarvis reads one address at a time. Reply yes or no after the sound; no screen selection is needed. Enable Hey Jarvis for automatic reply listening.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destination,
            decoration: InputDecoration(
              labelText: t('Destination and area'),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: disabled
                ? null
                : (value) => controller.navigationCommand({
                    'action': 'search',
                    'destination': value,
                  }),
          ),
          FilledButton.icon(
            onPressed: disabled
                ? null
                : () => controller.navigationCommand({
                    'action': 'search',
                    'destination': _destination.text,
                  }),
            icon: const Icon(Icons.search),
            label: Text(t('Find destination')),
          ),
          OutlinedButton.icon(
            onPressed: app.isAsking
                ? controller.cancelQuestion
                : controller.askQuestion,
            icon: const Icon(Icons.mic),
            label: Text(t(app.isAsking ? 'Stop question' : 'Ask Jarvis')),
          ),
          if (!app.handsFreeQuestions)
            OutlinedButton(
              onPressed: () => controller.setHandsFreeQuestions(true),
              child: Text(t('Enable Hey Jarvis')),
            ),
          if (nav.busy) const LinearProgressIndicator(),
          Semantics(
            liveRegion: true,
            child: Text(
              nav.error ?? nav.message,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: point(nav.position ?? const NavPoint(0, 0)),
                zoom: nav.position == null ? 1 : 16,
              ),
              onMapCreated: (map) => _map = map,
              myLocationEnabled: nav.position != null,
              myLocationButtonEnabled: nav.position != null,
              mapToolbarEnabled: false,
              polylines: {
                if (nav.route != null)
                  Polyline(
                    polylineId: const PolylineId('walking'),
                    points: nav.route!.points.map(point).toList(),
                    width: 6,
                    color: Colors.blue,
                  ),
              },
              markers: {
                if (nav.destination != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: point(nav.destination!.location),
                    infoWindow: InfoWindow(title: nav.destination!.name),
                  ),
              },
            ),
          ),
          if (nav.confirmation != 'none') ...[
            FilledButton(
              onPressed: disabled
                  ? null
                  : () => controller.navigationCommand({'action': 'confirm'}),
              child: Text(
                t(
                  nav.confirmation == 'destination'
                      ? 'Yes, this is the place'
                      : 'Yes, start walking guidance',
                ),
              ),
            ),
            OutlinedButton(
              onPressed: disabled
                  ? null
                  : () => controller.navigationCommand({'action': 'reject'}),
              child: Text(
                t(
                  nav.confirmation == 'destination'
                      ? 'No, read the next match'
                      : 'No, do not start',
                ),
              ),
            ),
          ],
          for (final entry in nav.places.asMap().entries)
            Card(
              child: ListTile(
                title: Text('${entry.key + 1}. ${entry.value.name}'),
                subtitle: Text(
                  [entry.value.address, ...entry.value.attributions].join('\n'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: disabled
                    ? null
                    : () => controller.navigationCommand({
                        'action': 'select',
                        'index': entry.key + 1,
                      }),
              ),
            ),
          if (nav.route != null) ...[
            Text(
              t('{name}: {metres} metres, about {minutes} minutes walking.', {
                'name': nav.destination!.name,
                'metres': nav.route!.distance.round(),
                'minutes': (nav.route!.seconds / 60).ceil(),
              }),
            ),
            for (final warning in nav.route!.warnings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(t(warning)),
              ),
            if (!nav.active)
              FilledButton(
                onPressed: disabled
                    ? null
                    : () => controller.navigationCommand({'action': 'start'}),
                child: Text(
                  t('Confirm destination and start walking guidance'),
                ),
              ),
            Semantics(
              liveRegion: true,
              child: Text(
                nav.guidance,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (nav.active) ...[
              OutlinedButton(
                onPressed: () =>
                    controller.navigationCommand({'action': 'repeat'}),
                child: Text(t('Repeat instruction')),
              ),
              OutlinedButton(
                onPressed: () => controller.navigationCommand({
                  'action': nav.paused ? 'resume' : 'pause',
                }),
                child: Text(
                  t(nav.paused ? 'Resume guidance' : 'Pause guidance'),
                ),
              ),
              OutlinedButton(
                onPressed: disabled
                    ? null
                    : () => controller.navigationCommand({'action': 'reroute'}),
                child: Text(t('Get a new route from here')),
              ),
            ],
          ],
          if (nav.route != null || nav.busy || nav.places.isNotEmpty)
            FilledButton.tonal(
              onPressed: () => controller.navigationCommand({'action': 'stop'}),
              child: Text(t('Stop navigation')),
            ),
          Text(
            t(
              'Map instructions do not confirm safe crossings, obstacles, accessible entrances, or pavement conditions. Keep using your usual mobility aid.',
            ),
          ),
        ],
      ),
    );
  }
}
