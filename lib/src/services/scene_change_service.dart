import 'dart:typed_data';
import 'dart:ui' as ui;

/// Small decoded image comparison; JPEG byte changes alone are not movement.
class SceneChangeService {
  Uint8List? _announced;
  Future<Uint8List> sample(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(
      jpeg,
      targetWidth: 24,
      targetHeight: 18,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (bytes == null) throw StateError('Cannot compare camera images');
        return Uint8List.fromList(bytes.buffer.asUint8List());
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  bool changed(Uint8List sample) {
    final old = _announced;
    if (old == null || old.length != sample.length) return true;
    var changed = 0;
    for (var i = 0; i < sample.length; i += 4) {
      final difference =
          ((old[i] - sample[i]).abs() +
              (old[i + 1] - sample[i + 1]).abs() +
              (old[i + 2] - sample[i + 2]).abs()) /
          3;
      if (difference > 28) changed++;
    }
    return changed / (sample.length / 4) > 0.18;
  }

  void mark(Uint8List sample) {
    _announced = Uint8List.fromList(sample);
  }

  void reset() {
    _announced = null;
  }
}
