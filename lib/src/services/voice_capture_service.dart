import 'package:flutter/services.dart';

class VoiceCaptureService {
  static const _methods = MethodChannel('blindway/voice');
  static const _events = EventChannel('blindway/voice-events');
  late final Stream<Map<String, dynamic>> events = _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));
  Future<void> start() => _methods.invokeMethod('start');
  Future<void> record(int captureId) =>
      _methods.invokeMethod('record', captureId);
  Future<void> recordLive(int captureId) =>
      _methods.invokeMethod('recordLive', captureId);
  static const _playback = MethodChannel('blindway/live-audio');
  Future<void> startPlayback(int turn) => _playback.invokeMethod('start', turn);
  Future<void> playChunk(int turn, Uint8List pcm) =>
      _playback.invokeMethod('chunk', {'turn': turn, 'pcm': pcm});
  Future<void> endPlayback(int turn) => _playback.invokeMethod('end', turn);
  Future<void> stopPlayback() => _playback.invokeMethod('stop');
  Future<void> mute(bool muted) => _methods.invokeMethod('mute', muted);
  Future<void> cancel() => _methods.invokeMethod('cancel');
  Future<void> stop() => _methods.invokeMethod('stop');
}
