import 'package:blind_way/src/services/text_recognition_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('blindway/text-recognition');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'passes JPEG bytes directly to on-device OCR and trims result',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'recognize');
            expect(call.arguments, Uint8List.fromList([255, 216, 255, 217]));
            return '  Exit on the left.\n';
          });
      expect(
        await TextRecognitionService().recognize(
          Uint8List.fromList([255, 216, 255, 217]),
        ),
        'Exit on the left.',
      );
    },
  );
  test(
    'native OCR failure propagates instead of reporting successful reading',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'OCR_FAILED');
          });
      await expectLater(
        TextRecognitionService().recognize(Uint8List(4)),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
