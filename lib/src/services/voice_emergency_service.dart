import 'dart:async';

import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../config/app_config.dart';

enum VoiceEmergencyMode { offlineWakeWord, speechRecognition, unavailable }

class VoiceEmergencyStartResult {
  const VoiceEmergencyStartResult(this.mode);
  final VoiceEmergencyMode mode;
  bool get available => mode != VoiceEmergencyMode.unavailable;
}

class VoiceEmergencyService {
  final SpeechToText _speech = SpeechToText();
  PorcupineManager? _porcupine;
  Timer? _restartTimer;
  FutureOr<void> Function()? _onHelp;
  void Function(bool listening)? _onListeningChanged;
  bool _active = false;
  bool _triggered = false;
  String _localeId = 'en_IN';

  Future<VoiceEmergencyStartResult> start({
    required FutureOr<void> Function() onHelp,
    required void Function(bool listening) onListeningChanged,
    required String language,
  }) async {
    await stop();
    _onHelp = onHelp;
    _onListeningChanged = onListeningChanged;
    _localeId = switch (language) {
      'Hindi' => 'hi_IN',
      'Tamil' => 'ta_IN',
      _ => 'en_IN',
    };
    if (AppConfig.porcupineAccessKey.isNotEmpty) {
      try {
        _porcupine = AppConfig.wakeWordKeywordPath.isNotEmpty
            ? await PorcupineManager.fromKeywordPaths(
                AppConfig.porcupineAccessKey,
                [AppConfig.wakeWordKeywordPath],
                _porcupineResult,
                sensitivities: const [0.65],
              )
            : await PorcupineManager.fromBuiltInKeywords(
                AppConfig.porcupineAccessKey,
                const [BuiltInKeyword.JARVIS],
                _porcupineResult,
                sensitivities: const [0.65],
              );
        _active = true;
        _triggered = false;
        await _porcupine!.start();
        _onListeningChanged?.call(true);
        return const VoiceEmergencyStartResult(
          VoiceEmergencyMode.offlineWakeWord,
        );
      } catch (_) {
        await _porcupine?.delete();
        _porcupine = null;
        // A missing/expired keyword model must not remove the emergency voice
        // fallback; Android short-command recognition remains available.
      }
    }
    return _startSpeechRecognition();
  }

  Future<VoiceEmergencyStartResult> _startSpeechRecognition() async {
    final available = await _speech.initialize(
      onStatus: _status,
      onError: (_) => _scheduleRestart(),
    );
    if (!available) {
      return const VoiceEmergencyStartResult(VoiceEmergencyMode.unavailable);
    }
    _active = true;
    _triggered = false;
    await _listen();
    return const VoiceEmergencyStartResult(
      VoiceEmergencyMode.speechRecognition,
    );
  }

  void _porcupineResult(int _) {
    if (_triggered) return;
    _triggered = true;
    _active = false;
    _onListeningChanged?.call(false);
    unawaited(_porcupine?.stop());
    _onHelp?.call();
  }

  Future<void> _listen() async {
    if (!_active || _triggered || _speech.isListening) return;
    await _speech.listen(
      onResult: _result,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        localeId: _localeId,
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  void _result(SpeechRecognitionResult result) {
    final words = result.recognizedWords
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const commands = {
      'help',
      'help me',
      'emergency',
      'sos',
      'मदद',
      'बचाओ',
      'உதவி',
      'காப்பாற்றுங்கள்',
    };
    final help = commands.contains(words);
    if (!help || _triggered) return;
    _triggered = true;
    _active = false;
    _restartTimer?.cancel();
    unawaited(_speech.stop());
    _onListeningChanged?.call(false);
    _onHelp?.call();
  }

  void _status(String status) {
    final listening = status == SpeechToText.listeningStatus;
    _onListeningChanged?.call(listening);
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (!_active || _triggered) return;
    _onListeningChanged?.call(false);
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 600), _listen);
  }

  Future<void> stop() async {
    _active = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _onListeningChanged?.call(false);
    await _porcupine?.delete();
    _porcupine = null;
    if (_speech.isListening) await _speech.stop();
  }

  Future<void> dispose() async => stop();
}
