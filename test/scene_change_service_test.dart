import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:blind_way/src/services/scene_change_service.dart';

void main() {
  test('announces first view, suppresses noise, detects changed scene', () {
    final detector = SceneChangeService();
    final image = Uint8List.fromList(List.filled(24 * 18 * 4, 100));
    expect(detector.changed(image), isTrue);
    detector.mark(image);
    expect(detector.changed(image), isFalse);
    final noise = Uint8List.fromList(List.filled(image.length, 106));
    expect(detector.changed(noise), isFalse);
    final moved = Uint8List.fromList(image);
    moved.fillRange(0, image.length ~/ 3, 170);
    expect(detector.changed(moved), isTrue);
    detector.mark(moved);
    expect(detector.changed(moved), isFalse);
    detector.reset();
    expect(detector.changed(moved), isTrue);
  });
}
