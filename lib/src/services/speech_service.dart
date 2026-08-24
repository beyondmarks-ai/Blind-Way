import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'api_service.dart';

class SpeechService {
  SpeechService(this._api)
    : _tts = FlutterTts(),
      _player = AudioPlayer(useProxyForRequestHeaders: false);

  final ApiService _api;
  final FlutterTts _tts;
  final AudioPlayer _player;
  String _language = 'en-IN';
  String _languageName = 'English';

  Future<void> initialize() async {
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(false);
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

  Future<void> speak(String text) async {
    await stop();
    final headers = _api.speechHeaders;
    if (headers != null) {
      final urls = <Uri>[
        _api.speechUri(text, _languageName),
        if (_api.hasSpeechStream) _api.bufferedSpeechUri(text, _languageName),
      ];
      for (final url in urls) {
        try {
          await _player.setUrl(url.toString(), headers: headers);
          unawaited(_player.play());
          return;
        } catch (_) {
          // Try the buffered cloud endpoint before falling back to native TTS.
        }
      }
    }
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _player.stop();
    await _tts.stop();
  }

  Future<void> dispose() => _player.dispose();
}
