import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../config/app_config.dart';

class GeminiLiveService {
  GeminiLiveService(this.tokenProvider);
  final Future<String?> Function() tokenProvider;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  WebSocket? _socket;
  Completer<void>? _setup;
  String? _switchingLanguage;
  bool ready = false;
  int _generation = 0;
  Future<void> connect({String language = 'auto'}) async {
    await close();
    final generation = ++_generation;
    final uri = Uri.parse(
      AppConfig.geminiLiveUrl,
    ).replace(queryParameters: {'language': language});
    if (uri.scheme != 'wss' || uri.host.isEmpty) {
      throw StateError('Gemini Live is not configured');
    }
    final token = await tokenProvider();
    if (token == null) throw StateError('Sign in to use Gemini Live');
    if (generation != _generation) return;
    final socket = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 20));
    if (generation != _generation) {
      await socket.close();
      return;
    }
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 20);
    _setup = Completer<void>();
    socket.listen(
      (raw) {
        if (generation != _generation) return;
        try {
          final event = Map<String, dynamic>.from(
            jsonDecode(raw as String) as Map,
          );
          if (event['type'] == 'ready') {
            if (_switchingLanguage != null &&
                event['language'] != _switchingLanguage) {
              return;
            }
            _switchingLanguage = null;
            ready = true;
            if (!(_setup?.isCompleted ?? true)) _setup!.complete();
          }
          if (['closed', 'error', 'reconnect'].contains(event['type'])) {
            ready = false;
            if (!(_setup?.isCompleted ?? true)) {
              _setup!.completeError(
                StateError(
                  event['message'] as String? ?? 'Live connection failed',
                ),
              );
            }
          }
          _events.add(event);
        } catch (_) {
          _events.add({'type': 'error', 'message': 'Invalid live response'});
        }
      },
      onError: (Object error) {
        if (generation == _generation) _disconnected();
      },
      onDone: () {
        if (generation == _generation) _disconnected();
      },
    );
    await _setup!.future.timeout(const Duration(seconds: 20));
  }

  void _disconnected() {
    ready = false;
    if (!(_setup?.isCompleted ?? true)) {
      _setup!.completeError(StateError('Live connection failed'));
    }
    _events.add({'type': 'closed'});
  }

  void _send(Map<String, dynamic> message) {
    if (ready) _socket?.add(jsonEncode(message));
  }

  void frame(Uint8List jpeg) =>
      _send({'type': 'frame', 'data': base64Encode(jpeg)});
  void observe(int turn, String language) =>
      _send({'type': 'observe', 'turn': turn, 'language': language});
  void played(int turn) => _send({'type': 'played', 'turn': turn});
  void begin(int turn) => _send({'type': 'begin', 'turn': turn});
  void navigationPrompt(String prompt, {String language = 'auto'}) => _send({
    'type': 'navigationPrompt',
    'prompt': prompt,
    'language': language,
  });
  void audio(int turn, Uint8List pcm) =>
      _send({'type': 'audio', 'turn': turn, 'data': base64Encode(pcm)});
  void end(int turn) => _send({'type': 'end', 'turn': turn});
  void cancel() {
    _send({'type': 'cancel'});
    ready = false;
  }

  Future<void> changeLanguage(String language) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Live connection is unavailable');
    }
    final setup = Completer<void>();
    _setup = setup;
    _switchingLanguage = language;
    ready = false;
    socket.add(jsonEncode({'type': 'language', 'language': language}));
    await setup.future.timeout(const Duration(seconds: 20));
  }

  Future<void> close() async {
    ++_generation;
    ready = false;
    _switchingLanguage = null;
    final old = _socket;
    _socket = null;
    if (!(_setup?.isCompleted ?? true)) _setup!.complete();
    await old?.close();
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }
}
