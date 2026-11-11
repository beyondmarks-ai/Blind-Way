import 'package:flutter/services.dart';

/// Bundled Android ML Kit recognition. Reading images never leave the phone.
class TextRecognitionService {
  TextRecognitionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('blindway/text-recognition');
  final MethodChannel _channel;

  Future<String> recognize(Uint8List jpeg) async {
    final text = await _channel
        .invokeMethod<String>('recognize', jpeg)
        .timeout(const Duration(seconds: 30));
    return text?.trim() ?? '';
  }
}
