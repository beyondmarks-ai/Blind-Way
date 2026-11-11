import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/voice_emergency_service.dart';
import '../services/notification_service.dart';
import '../config/languages.dart';
import '../state/app_controller.dart';
import 'camera_preview.dart';
import 'navigation_screen.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final blind = state.session!.role == UserRole.blindUser;
    final pages = blind
        ? const [BlindHome(), ContactsScreen(), SettingsScreen()]
        : const [ContactHome(), ContactsScreen(), SettingsScreen()];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _index == 0
              ? 'Blind Way'
              : _index == 1
              ? 'Trusted people'
              : 'Settings',
        ),
      ),
      body: Column(
        children: [
          if (!NotificationService.instance.pushAvailable ||
              !AppConfig.guardianPushConfigured)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Background emergency notifications are not configured. Trusted contacts must keep this app open to see alerts.',
              ),
            ),
          if (state.error != null)
            MaterialBanner(
              content: Text(state.error!),
              leading: const Icon(Icons.error_outline),
              actions: [
                TextButton(
                  onPressed: ref
                      .read(appControllerProvider.notifier)
                      .clearError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: Icon(
              blind ? Icons.assistant_navigation : Icons.warning_amber,
            ),
            label: blind ? 'Assist' : 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people),
            label: 'People',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class BlindHome extends ConsumerWidget {
  const BlindHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final cue = state.currentCue;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const WalkingNavigationScreen(),
            ),
          ),
          icon: const Icon(Icons.directions_walk),
          label: const Text('Google Maps walking directions'),
        ),
        if (state.navigation.active || state.navigation.busy)
          Semantics(liveRegion: true, child: Text(state.navigation.message)),
        _StatusCard(
          icon: state.camera == null ? Icons.videocam_off : Icons.videocam,
          title: state.camera == null
              ? 'Camera not connected'
              : 'Camera connected',
          subtitle: state.camera?.baseUrl ?? 'Connect your ESP32-CAM to begin.',
          action: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const CameraDialog(),
            ),
            child: Text(state.camera == null ? 'Connect' : 'Change'),
          ),
        ),
        const SizedBox(height: 12),
        if (state.camera != null) ...[
          if (AppConfig.geminiLiveUrl.isNotEmpty) ...[
            FilledButton.icon(
              onPressed:
                  state.liveConnecting ||
                      state.isReadingText ||
                      state.sosCountdown != null ||
                      state.activeAlert != null
                  ? null
                  : () => controller.setGeminiLive(!state.geminiLive),
              icon: Icon(
                state.geminiLive ? Icons.stop_circle : Icons.video_call,
              ),
              label: Text(
                state.liveConnecting
                    ? 'Connecting Gemini Live…'
                    : state.geminiLive
                    ? 'Stop Gemini Live'
                    : 'Start Gemini Live',
              ),
            ),
            const Text(
              'Live trial: camera frames go to Google about once a second. Say Hey Jarvis, pause, then ask in your language. Question audio streams after activation. Use Stop question to interrupt a reply.',
            ),
          ],
          if (state.geminiLive) ...[
            SwitchListTile(
              title: const Text('Automatic surroundings'),
              subtitle: const Text(
                'Describe visible changes without asking. Waits for each reply to finish. Stop question also pauses automatic updates.',
              ),
              value: state.autoNarration,
              onChanged: controller.setAutoNarration,
            ),
            if (state.memoryStatus.isNotEmpty) Text(state.memoryStatus),
          ],
          if (!state.geminiLive && !state.liveConnecting)
            SwitchListTile(
              title: const Text('Hands-free questions'),
              subtitle: const Text(
                'Say Hey Jarvis, then ask in your language. In this mode, say Hey Jarvis then Help for SOS, or use the emergency button.',
              ),
              value: state.handsFreeQuestions,
              onChanged:
                  state.isAsking ||
                      state.liveConnecting ||
                      state.isReadingText ||
                      state.sosCountdown != null ||
                      state.activeAlert != null
                  ? null
                  : controller.setHandsFreeQuestions,
            ),
          FilledButton.icon(
            onPressed:
                state.isAsking ||
                    state.liveConnecting ||
                    state.isReadingText ||
                    state.sosCountdown != null ||
                    state.activeAlert != null
                ? null
                : controller.askQuestion,
            icon: const Icon(Icons.mic),
            label: const Text('Ask a question'),
          ),
          if (state.isAsking)
            TextButton(
              onPressed: controller.cancelQuestion,
              child: const Text('Stop question'),
            ),
          if (state.questionStatus.isNotEmpty)
            Semantics(liveRegion: true, child: Text(state.questionStatus)),
          if (state.lastQuestion.isNotEmpty) Text('You: ${state.lastQuestion}'),
          if (state.lastAnswer.isNotEmpty) SelectableText(state.lastAnswer),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const CameraPreviewDialog(),
            ),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera preview'),
          ),
          FilledButton.icon(
            onPressed:
                state.isBusy ||
                    state.geminiLive ||
                    state.liveConnecting ||
                    state.isAsking ||
                    state.isReadingText ||
                    !state.camera!.supportsReading ||
                    state.sosCountdown != null ||
                    state.activeAlert != null
                ? null
                : controller.readCameraText,
            icon: const Icon(Icons.document_scanner),
            label: Text(state.isReadingText ? 'Reading text…' : 'Read text'),
          ),
          Text(
            state.camera!.supportsReading
                ? 'Navigation: 320 × 240. Read text: 1600 × 1200. Reading pauses scene guidance. English OCR stays on your phone.'
                : 'This camera supports navigation snapshots. Install the two-mode firmware and reconnect to enable Read text.',
          ),
          if (state.readingStatus.isNotEmpty)
            Semantics(liveRegion: true, child: Text(state.readingStatus)),
          if (state.recognizedText.isNotEmpty) ...[
            SelectableText(state.recognizedText),
            TextButton(
              onPressed: state.isReadingText ? null : controller.repeatReadText,
              child: const Text('Read text again'),
            ),
          ],
          if (state.isReadingText || state.recognizedText.isNotEmpty)
            TextButton(
              onPressed: controller.stopReadingSpeech,
              child: const Text('Stop reading'),
            ),
          const SizedBox(height: 12),
        ],
        _StatusCard(
          icon: state.bluetoothAudio ? Icons.headphones : Icons.headset_off,
          title: state.bluetoothAudio
              ? 'Bluetooth audio connected'
              : 'Phone audio active',
          subtitle: state.bluetoothAudio
              ? 'Guidance will play through your connected earbuds.'
              : 'Pair earbuds or continue using the phone speaker.',
          action: TextButton(
            onPressed: controller.openBluetoothSettings,
            child: const Text('Bluetooth'),
          ),
        ),
        const SizedBox(height: 20),
        _StatusCard(
          icon: state.handsFreeQuestions || state.voiceEmergencyListening
              ? Icons.mic
              : Icons.mic_off,
          title: state.handsFreeQuestions
              ? 'Hey Jarvis listening'
              : state.voiceEmergencyListening
              ? state.voiceEmergencyMode == VoiceEmergencyMode.offlineWakeWord
                    ? 'Offline wake word ready'
                    : 'Voice emergency ready'
              : state.voiceEmergencyAvailable
              ? 'Voice emergency starts with assistance'
              : 'Voice emergency unavailable',
          subtitle: state.handsFreeQuestions
              ? 'Say “Hey Jarvis”, pause, then ask a question or say “Help” for SOS. Questions need internet.'
              : state.voiceEmergencyListening
              ? state.voiceEmergencyMode == VoiceEmergencyMode.offlineWakeWord
                    ? 'Say “${AppConfig.wakeWordPhrase}” using the phone or earbud microphone. Detection stays on-device.'
                    : 'Say “Help”, “Emergency”, or “SOS” using the phone or earbud microphone.'
              : 'Start assistance and allow microphone access to enable the spoken help trigger.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: state.isAssisting
                ? const Color(0xff36474f)
                : const Color(0xff00677e),
            minimumSize: const Size.fromHeight(72),
          ),
          onPressed:
              state.geminiLive ||
                  state.liveConnecting ||
                  state.isBusy ||
                  (state.isReadingText && !state.isAssisting)
              ? null
              : state.isAssisting
              ? controller.stopAssistance
              : controller.startAssistance,
          icon: Icon(
            state.isAssisting ? Icons.stop_circle : Icons.play_circle,
            size: 34,
          ),
          label: Text(
            state.isAssisting ? 'Stop assistance' : 'Start assistance',
          ),
        ),
        const SizedBox(height: 18),
        Semantics(
          liveRegion: true,
          label: cue == null
              ? 'No scene guidance yet'
              : '${cue.risk.name}. ${cue.cue}',
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest guidance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    cue?.cue ?? 'Start assistance to hear what is ahead.',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (cue != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${cue.risk.name.toUpperCase()} · ${(cue.confidence * 100).round()}% confidence',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (state.sosCountdown != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Sending emergency in ${state.sosCountdown}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: controller.cancelSosCountdown,
                    child: const Text('Cancel emergency'),
                  ),
                ],
              ),
            ),
          )
        else if (state.activeAlert != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Emergency active',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'Your trusted contacts have been notified and location sharing is active.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => controller.closeAlert('cancel'),
                    child: const Text('I am safe — cancel alert'),
                  ),
                ],
              ),
            ),
          )
        else
          SosHoldButton(onActivated: controller.beginSosCountdown),
      ],
    );
  }
}

class CameraDialog extends ConsumerStatefulWidget {
  const CameraDialog({super.key});

  @override
  ConsumerState<CameraDialog> createState() => _CameraDialogState();
}

class _CameraDialogState extends ConsumerState<CameraDialog> {
  final _url = TextEditingController();
  final _token = TextEditingController();

  @override
  void initState() {
    super.initState();
    final camera = ref.read(appControllerProvider).camera;
    _url.text = camera?.baseUrl ?? AppConfig.cameraAddress;
    _token.text = camera?.token ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect camera'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Use the phone hosting the camera hotspot, or join the same Wi-Fi. The current GC2145 firmware uses its IP address; it does not support BLE setup or automatic discovery.',
          ),
          if (ref.watch(appControllerProvider).error case final error?)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Camera address',
              hintText: '10.67.29.164',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Camera token (optional)',
              helperText: 'Leave blank for the current GC2145 firmware.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const ProvisionCameraDialog(),
        ),
        child: const Text('Set up Wi-Fi'),
      ),
      TextButton(
        onPressed: () async {
          final found = await ref
              .read(appControllerProvider.notifier)
              .discoverCamera();
          if (found != null && mounted) setState(() => _url.text = found);
        },
        child: const Text('Find automatically'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: ref.watch(appControllerProvider).isBusy
            ? null
            : () async {
                final connected = await ref
                    .read(appControllerProvider.notifier)
                    .connectCamera(_url.text, token: _token.text);
                if (context.mounted && connected) {
                  Navigator.pop(context);
                }
              },
        child: const Text('Connect'),
      ),
    ],
  );
}

class ProvisionCameraDialog extends ConsumerStatefulWidget {
  const ProvisionCameraDialog({super.key});

  @override
  ConsumerState<ProvisionCameraDialog> createState() =>
      _ProvisionCameraDialogState();
}

class _ProvisionCameraDialogState extends ConsumerState<ProvisionCameraDialog> {
  final _device = TextEditingController();
  final _pop = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _device.dispose();
    _pop.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set up camera Wi-Fi'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the device name and proof-of-possession printed when the camera starts.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _device,
            decoration: const InputDecoration(labelText: 'PROV_BW device name'),
          ),
          TextField(
            controller: _pop,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Device code'),
          ),
          TextField(
            controller: _ssid,
            decoration: const InputDecoration(labelText: 'Wi-Fi name'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Wi-Fi password'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () async {
          await ref
              .read(appControllerProvider.notifier)
              .provisionCamera(
                deviceName: _device.text,
                proofOfPossession: _pop.text,
                ssid: _ssid.text,
                password: _password.text,
              );
          if (context.mounted &&
              ref.read(appControllerProvider).error == null) {
            Navigator.pop(context);
          }
        },
        child: const Text('Provision'),
      ),
    ],
  );
}

class SosHoldButton extends StatefulWidget {
  const SosHoldButton({super.key, required this.onActivated});
  final VoidCallback onActivated;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton> {
  Timer? _timer;
  var _holding = false;

  void _start() {
    setState(() => _holding = true);
    _timer = Timer(const Duration(seconds: 2), () {
      if (_holding) widget.onActivated();
      if (mounted) setState(() => _holding = false);
    });
  }

  void _stop() {
    _timer?.cancel();
    if (mounted) setState(() => _holding = false);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Emergency SOS',
    hint: 'Press and hold for two seconds to begin the emergency countdown',
    onLongPress: widget.onActivated,
    child: GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 96,
        decoration: BoxDecoration(
          color: _holding ? const Color(0xff8e0000) : const Color(0xffb3261e),
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: Text(
          _holding ? 'Keep holding…' : 'Hold for Emergency SOS',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

class ContactHome extends ConsumerWidget {
  const ContactHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final alert = state.activeAlert;
    final api = ref.read(apiServiceProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (alert == null)
          const _StatusCard(
            icon: Icons.verified_user,
            title: 'Monitoring active',
            subtitle:
                'Emergency alerts from linked users will appear here and as high-priority notifications.',
          )
        else
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${alert.blindUserName} needs emergency help',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Started ${alert.startedAt.toLocal()}'),
                  Text(
                    alert.triggerSource == 'voice'
                        ? 'Triggered by the spoken help command'
                        : 'Triggered with the emergency button',
                  ),
                  if (alert.latitude != null && alert.longitude != null) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FlutterMap(
                          key: ValueKey('${alert.latitude}:${alert.longitude}'),
                          options: MapOptions(
                            initialCenter: LatLng(
                              alert.latitude!,
                              alert.longitude!,
                            ),
                            initialZoom: 17,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'ai.beyondmarks.blindway',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(
                                    alert.latitude!,
                                    alert.longitude!,
                                  ),
                                  width: 56,
                                  height: 56,
                                  child: const Icon(
                                    Icons.location_pin,
                                    color: Color(0xffb3261e),
                                    size: 52,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Accuracy: ${alert.accuracy?.round() ?? 0} m'
                      '${alert.locationUpdatedAt == null ? '' : ' · Updated ${alert.locationUpdatedAt!.toLocal()}'}',
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: const Text('© OpenStreetMap contributors'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${alert.latitude},${alert.longitude}',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.map),
                      label: const Text('Open live location'),
                    ),
                  ],
                  if (alert.lastCue?.isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last scene description',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              alert.lastDetails?.isNotEmpty == true
                                  ? alert.lastDetails!
                                  : alert.lastCue!,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (alert.lastDetails?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text('Guidance given: ${alert.lastCue}'),
                            ],
                            Text(
                              '${alert.lastRisk?.name.toUpperCase() ?? 'UNKNOWN'} · ${((alert.lastConfidence ?? 0) * 100).round()}% confidence',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (alert.snapshotAvailable) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Last camera view',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (alert.snapshotCapturedAt != null)
                      Text('Captured ${alert.snapshotCapturedAt!.toLocal()}'),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        child: Image.network(
                          api.alertSnapshotUri(alert.id).toString(),
                          headers: api.speechHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            height: 180,
                            child: Center(
                              child: Text('Snapshot could not be loaded.'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref
                        .read(appControllerProvider.notifier)
                        .closeAlert('acknowledge'),
                    child: const Text('Acknowledge alert'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => ref
                        .read(appControllerProvider.notifier)
                        .closeAlert('resolve'),
                    child: const Text('Mark resolved'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Live location refreshes every 15 seconds during an active alert. Emergency snapshots are private, visible only to linked guardians, and deleted when the alert closes or after 30 days.',
        ),
      ],
    );
  }
}

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final blind = state.session!.role == UserRole.blindUser;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (blind) ...[
          FilledButton.icon(
            onPressed: controller.createInvite,
            icon: const Icon(Icons.person_add),
            label: const Text('Create secure invite'),
          ),
          if (state.inviteCode?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('Invite code — expires in 10 minutes'),
                      const SizedBox(height: 8),
                      SelectableText(
                        state.inviteCode!,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ] else ...[
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => controller.redeemInvite(_code.text),
            child: const Text('Link trusted user'),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          blind ? 'Your trusted contacts' : 'People who trust you',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (state.contacts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No trusted connections yet.'),
            ),
          )
        else
          ...state.contacts.map(
            (contact) => Card(
              child: ListTile(
                leading: Icon(
                  contact.verified ? Icons.verified : Icons.pending,
                ),
                title: Text(contact.name),
                subtitle: Text(
                  contact.verified
                      ? 'Verified emergency contact'
                      : 'Verification pending',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          state.session!.displayName,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          state.session!.role == UserRole.blindUser
              ? 'Vision assistance user'
              : 'Trusted emergency contact',
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          key: ValueKey(state.language),
          initialValue: AppLanguages.normalize(state.language),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Voice response language',
            border: OutlineInputBorder(),
          ),
          items: AppLanguages.labels.entries
              .map(
                (language) => DropdownMenuItem(
                  value: language.key,
                  child: Text(language.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged:
              (state.isAsking && !state.geminiLive) ||
                  state.liveConnecting ||
                  state.isReadingText ||
                  state.sosCountdown != null ||
                  state.activeAlert != null
              ? null
              : (value) {
                  if (value != null) controller.setLanguage(value);
                },
        ),
        const Text(
          'Gemini Live switches to your selected language and resumes automatically. Automatic follows your spoken question. Your choice is saved.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: state.isBusy ? null : controller.testNotification,
          icon: const Icon(Icons.notifications_active),
          label: const Text('Test notification for my account'),
        ),
        const Text(
          'Guardians must allow notifications, sign in, and link with the assistance user in Trusted people.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: controller.openBluetoothSettings,
          icon: const Icon(Icons.bluetooth),
          label: const Text('Bluetooth audio settings'),
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Privacy: normal camera images are analyzed transiently. Only the latest frame is stored during an emergency and shared with linked guardians. Walking navigation sends your current location and destination to Google Maps. Guardians receive location only during an active emergency alert.',
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: controller.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                Text(subtitle),
              ],
            ),
          ),
          ?action,
        ],
      ),
    ),
  );
}
