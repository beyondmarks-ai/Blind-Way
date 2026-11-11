import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_controller.dart';

/// Sequential snapshots: never queue old frames behind a reading capture.
class CameraPreviewDialog extends ConsumerStatefulWidget {
  const CameraPreviewDialog({super.key});
  @override
  ConsumerState<CameraPreviewDialog> createState() =>
      _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends ConsumerState<CameraPreviewDialog>
    with WidgetsBindingObserver {
  Timer? _timer;
  Uint8List? _frame;
  DateTime? _capturedAt;
  String? _error;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(Duration.zero, _nextFrame);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  Future<void> _nextFrame() async {
    if (!mounted) return;
    final state = ref.read(appControllerProvider);
    try {
      if (_foreground && !state.isReadingText && state.camera != null) {
        final camera = state.camera!;
        final frame = state.geminiLive
            ? ref.read(appControllerProvider.notifier).liveFrame
            : state.liveConnecting
            ? null
            : await ref.read(cameraServiceProvider).capture(camera);
        if (!mounted) return;
        final current = ref.read(appControllerProvider);
        if (!current.isReadingText && current.camera == camera) {
          setState(() {
            _frame = frame;
            _capturedAt = frame == null ? null : DateTime.now();
            _error = null;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Camera unavailable. Check power and Wi-Fi. Retrying…';
          _frame = null;
        });
      }
    } finally {
      if (mounted) {
        _timer = Timer(
          Duration(milliseconds: _error == null ? 150 : 1500),
          _nextFrame,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    return AlertDialog(
      title: const Text('Camera preview'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isReadingText || !_foreground)
                const Text('Preview paused.')
              else if (_frame != null)
                StreamBuilder<int>(
                  stream: Stream.periodic(const Duration(seconds: 1), (n) => n),
                  builder: (context, _) {
                    final stale =
                        _capturedAt == null ||
                        DateTime.now().difference(_capturedAt!) >
                            const Duration(seconds: 3);
                    return stale
                        ? const Text(
                            'Image is out of date. Waiting for a fresh frame.',
                          )
                        : Image.memory(
                            _frame!,
                            gaplessPlayback: true,
                            semanticLabel: 'Most recent camera view',
                          );
                  },
                )
              else
                Text(_error ?? 'Connecting to camera…'),
              if (state.readingStatus.isNotEmpty)
                Semantics(liveRegion: true, child: Text(state.readingStatus)),
              if (state.recognizedText.isNotEmpty)
                SelectableText(state.recognizedText),
            ],
          ),
        ),
      ),
      actions: [
        if (state.camera?.supportsReading == true)
          FilledButton(
            onPressed:
                state.isReadingText ||
                    state.activeAlert != null ||
                    state.sosCountdown != null
                ? null
                : ref.read(appControllerProvider.notifier).readCameraText,
            child: Text(state.isReadingText ? 'Reading…' : 'Read text'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
