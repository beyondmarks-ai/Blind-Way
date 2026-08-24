import 'package:flutter/services.dart';

class BluetoothService {
  static const _channel = MethodChannel('blindway/system');

  Future<void> openSettings() =>
      _channel.invokeMethod<void>('openBluetoothSettings');

  Future<bool> hasBluetoothAudio() async =>
      await _channel.invokeMethod<bool>('hasBluetoothAudio') ?? false;
}
