import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'api_service.dart';

class _SpeechRequest {
  _SpeechRequest(this.text, {this.queueKey});

  final String text;
  final String? queueKey;
  final Completer<void> completed = Completer<void>();
}

class SpeechService {
  SpeechService(this._api)
    : _tts = FlutterTts(),
      _player = AudioPlayer(useProxyForRequestHeaders: false);

  final ApiService _api;
  final FlutterTts _tts;
  final AudioPlayer _player;
  final List<_SpeechRequest> _queue = [];
  String _language = 'en-IN';
  String _languageName = 'English';
  bool _processing = false;
  bool _disposed = false;
  Future<void> _outputReady = Future<void>.value();
  int _playbackEpoch = 0;

  Future<void> initialize() async {
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(_language);
  }

  Future<void> setLanguage(String language) async {
    _languageName = language;
    _language = switch (language) {
      'Hindi' => 'hi-IN',
      'Tamil' => 'ta-IN',
      _ => 'en-IN',
    };
    await _tts.setLanguage(_language);
  }

  /// Queues speech without cutting off the sentence currently being played.
  ///
  /// [queueKey] coalesces pending messages of the same kind, so rapidly
  /// changing vision results keep only the newest unsaid instruction.
  /// [interrupt] is reserved for danger and emergency messages.
  Future<void> speak(String text, {String? queueKey, bool interrupt = false}) {
    if (_disposed || text.trim().isEmpty) return Future<void>.value();
    final request = _SpeechRequest(text.trim(), queueKey: queueKey);

    if (interrupt) {
      _playbackEpoch++;
      _completeAndClearQueue();
      _outputReady = _stopOutputs();
      _queue.insert(0, request);
    } else {
      if (queueKey != null) {
        final replaced = _queue.where((item) => item.queueKey == queueKey);
        for (final item in replaced.toList()) {
          _queue.remove(item);
          if (!item.completed.isCompleted) item.completed.complete();
        }
      }
      _queue.add(request);
    }

    unawaited(_drainQueue());
    return request.completed.future;
  }

  Future<void> _drainQueue() async {
    if (_processing || _disposed) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final request = _queue.removeAt(0);
        final requestEpoch = _playbackEpoch;
        try {
          await _outputReady;
          if (requestEpoch == _playbackEpoch) {
            await _play(request.text, requestEpoch);
          }
        } catch (_) {
          // A failed cloud and native voice must not block later guidance.
        } finally {
          if (!request.completed.isCompleted) request.completed.complete();
        }
      }
    } finally {
      _processing = false;
      if (_queue.isNotEmpty && !_disposed) unawaited(_drainQueue());
    }
  }

  Future<void> _play(String text, int requestEpoch) async {
    final headers = _api.speechHeaders;
    if (headers != null) {
      final urls = <Uri>[
        _api.speechUri(text, _languageName),
        if (_api.hasSpeechStream) _api.bufferedSpeechUri(text, _languageName),
      ];
      for (final url in urls) {
        try {
          await _player.setUrl(url.toString(), headers: headers);
          if (requestEpoch != _playbackEpoch) return;
          await _player.play();
          return;
        } catch (_) {
          await _player.stop();
          // Try the buffered cloud endpoint before falling back to native TTS.
        }
      }
    }
    if (requestEpoch != _playbackEpoch) return;
    await _tts.speak(text);
  }

  Future<void> _stopOutputs() async {
    await Future.wait([_player.stop(), _tts.stop()]);
  }

  void _completeAndClearQueue() {
    for (final request in _queue) {
      if (!request.completed.isCompleted) request.completed.complete();
    }
    _queue.clear();
  }

  Future<void> stop() async {
    _playbackEpoch++;
    _completeAndClearQueue();
    _outputReady = _stopOutputs();
    await _outputReady;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _player.dispose();
  }
}
