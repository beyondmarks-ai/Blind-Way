import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/models.dart';

enum PhoneAuthEventType { codeSent, authenticated, failed, timeout }

class PhoneAuthEvent {
  const PhoneAuthEvent(
    this.type, {
    this.session,
    this.message,
    this.generation = 0,
  });
  final PhoneAuthEventType type;
  final UserSession? session;
  final String? message;
  final int generation;
}

/// Google phone auth owns its native session; app metadata uses secure storage.
class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, FlutterSecureStorage? storage})
    : _auth = firebaseAuth ?? FirebaseAuth.instance,
      _storage = storage ?? const FlutterSecureStorage() {
    _tokenSubscription = _auth.idTokenChanges().listen(_publishToken);
  }
  final FirebaseAuth _auth;
  final FlutterSecureStorage _storage;
  final _tokens = StreamController<String?>.broadcast();
  final _events = StreamController<PhoneAuthEvent>.broadcast();
  Stream<String?> get tokenChanges => _tokens.stream;
  Stream<PhoneAuthEvent> get phoneEvents => _events.stream;
  int get attempt => _generation;
  StreamSubscription<User?>? _tokenSubscription;
  Timer? _requestTimeout;
  int _generation = 0;
  int? _acceptedGeneration;
  String? _verificationId, _activeUid, _phone;
  int? _resendToken;
  UserRole? _role;
  String _name = '';
  bool _disposed = false;
  Future<void> _credentialQueue = Future<void>.value();
  static const _storageKey = 'phone_session_v1';

  static String normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'[\s()\-]'), '');
    final local = digits.startsWith('+91')
        ? digits.substring(3)
        : digits.length == 12 && digits.startsWith('91')
        ? digits.substring(2)
        : digits;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(local)) {
      throw const FormatException(
        'Enter a valid 10-digit Indian mobile number.',
      );
    }
    return '+91$local';
  }

  bool _current(int epoch) => !_disposed && epoch == _generation;
  void _emit(PhoneAuthEvent event) {
    if (!_disposed) {
      _events.add(
        PhoneAuthEvent(
          event.type,
          session: event.session,
          message: event.message,
          generation: _generation,
        ),
      );
    }
  }

  Future<void> requestOtp({
    required String phoneNumber,
    required UserRole role,
    required String displayName,
    bool resend = false,
  }) async {
    final phone = normalizePhone(phoneNumber);
    if (displayName.trim().isEmpty) {
      throw const FormatException('Enter your name.');
    }
    final forceToken = resend && phone == _phone ? _resendToken : null;
    _resendToken = forceToken;
    final epoch = ++_generation;
    _acceptedGeneration = null;
    _verificationId = null;
    _phone = phone;
    _role = role;
    _name = displayName.trim();
    _requestTimeout?.cancel();
    _requestTimeout = Timer(const Duration(minutes: 2), () {
      if (_current(epoch) && _verificationId == null) {
        ++_generation;
        _emit(
          const PhoneAuthEvent(
            PhoneAuthEventType.failed,
            message:
                'OTP request timed out. Check your connection and try again.',
          ),
        );
      }
    });
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: forceToken,
        verificationCompleted: (credential) {
          if (_current(epoch)) unawaited(_acceptCredential(credential, epoch));
        },
        verificationFailed: (error) {
          if (_current(epoch) && _acceptedGeneration != epoch) {
            _requestTimeout?.cancel();
            _emit(
              PhoneAuthEvent(
                PhoneAuthEventType.failed,
                message: errorMessage(error),
              ),
            );
          }
        },
        codeSent: (verificationId, resendToken) {
          if (_current(epoch) && _acceptedGeneration != epoch) {
            _requestTimeout?.cancel();
            _verificationId = verificationId;
            _resendToken = resendToken;
            _emit(const PhoneAuthEvent(PhoneAuthEventType.codeSent));
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (_current(epoch) && _acceptedGeneration != epoch) {
            _requestTimeout?.cancel();
            _verificationId ??= verificationId;
            _emit(
              const PhoneAuthEvent(
                PhoneAuthEventType.timeout,
                message:
                    'Enter the code from your SMS. Automatic code detection has finished.',
              ),
            );
          }
        },
      );
    } on FirebaseAuthException catch (error) {
      if (_current(epoch)) {
        _requestTimeout?.cancel();
        _emit(
          PhoneAuthEvent(
            PhoneAuthEventType.failed,
            message: errorMessage(error),
          ),
        );
      }
    } catch (_) {
      if (_current(epoch)) {
        _requestTimeout?.cancel();
      }
      rethrow;
    }
  }

  Future<void> verifyOtp(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const FormatException('Enter the 6-digit OTP from your SMS.');
    }
    if (_verificationId == null) throw StateError('Request a new OTP first.');
    await _acceptCredential(
      PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code.trim(),
      ),
      _generation,
    );
  }

  Future<void> _acceptCredential(PhoneAuthCredential credential, int epoch) {
    final operation = _credentialQueue.then((_) async {
      if (!_current(epoch) || _acceptedGeneration == epoch) return;
      try {
        final result = await _auth.signInWithCredential(credential);
        if (!_current(epoch)) {
          await _auth.signOut();
          return;
        }
        final user = result.user;
        if (user == null || user.phoneNumber != _phone) {
          throw FirebaseAuthException(code: 'credential-mismatch');
        }
        final token = await user.getIdToken();
        if (!_current(epoch)) {
          await _auth.signOut();
          return;
        }
        if (token == null || token.isEmpty) {
          throw FirebaseAuthException(code: 'invalid-user-token');
        }
        await _storage.write(
          key: _storageKey,
          value: jsonEncode({
            'uid': user.uid,
            'role': _role!.name,
            'name': _name,
          }),
        );
        if (!_current(epoch)) {
          await _storage.delete(key: _storageKey);
          await _auth.signOut();
          return;
        }
        _activeUid = user.uid;
        _acceptedGeneration = epoch;
        _requestTimeout?.cancel();
        _tokens.add(token);
        _emit(
          PhoneAuthEvent(
            PhoneAuthEventType.authenticated,
            session: UserSession(
              subject: user.uid,
              displayName: _name,
              accessToken: token,
              role: _role!,
            ),
          ),
        );
      } on FirebaseAuthException catch (error) {
        if (_current(epoch)) {
          _emit(
            PhoneAuthEvent(
              PhoneAuthEventType.failed,
              message: errorMessage(error),
            ),
          );
        }
      } catch (_) {
        if (_current(epoch)) {
          _emit(
            const PhoneAuthEvent(
              PhoneAuthEventType.failed,
              message:
                  'Could not finish sign-in. Check your connection and try again.',
            ),
          );
        }
      }
    });
    _credentialQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<UserSession?> restore() async {
    final epoch = _generation;
    await _storage.delete(key: 'entra_session_v1');
    final saved = await _storage.read(key: _storageKey);
    final user = _auth.currentUser;
    if (saved == null || user == null || user.phoneNumber == null) return null;
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['uid'] != user.uid) return null;
    final token = await user.getIdToken();
    if (!_current(epoch) || token == null) return null;
    _activeUid = user.uid;
    _tokens.add(token);
    return UserSession(
      subject: user.uid,
      displayName: data['name'] as String,
      accessToken: token,
      role: UserRole.values.byName(data['role'] as String),
    );
  }

  Future<String?> accessToken() async {
    final user = _auth.currentUser;
    final epoch = _generation;
    if (user == null || user.uid != _activeUid) return null;
    final token = await user.getIdToken();
    return _current(epoch) && user.uid == _activeUid ? token : null;
  }

  Future<void> _publishToken(User? user) async {
    if (_disposed) return;
    final epoch = _generation;
    if (user == null || user.uid != _activeUid) {
      _tokens.add(null);
      return;
    }
    try {
      final token = await user.getIdToken();
      if (_current(epoch) && user.uid == _activeUid) _tokens.add(token);
    } catch (_) {
      if (_current(epoch)) _tokens.add(null);
    }
  }

  void cancelOtp() {
    ++_generation;
    _verificationId = null;
    _resendToken = null;
    _requestTimeout?.cancel();
  }

  Future<void> logout() async {
    cancelOtp();
    _activeUid = null;
    _tokens.add(null);
    await _auth.signOut();
    await _storage.delete(key: _storageKey);
    await _storage.delete(key: 'entra_session_v1');
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    _requestTimeout?.cancel();
    unawaited(_tokenSubscription?.cancel());
    unawaited(_tokens.close());
    unawaited(_events.close());
  }

  static String errorMessage(
    FirebaseAuthException error,
  ) => switch (error.code) {
    'invalid-phone-number' => 'Enter a valid mobile number.',
    'invalid-verification-code' =>
      'That OTP is incorrect. Check the SMS and try again.',
    'session-expired' ||
    'invalid-verification-id' => 'This OTP has expired. Request a new code.',
    'too-many-requests' || 'quota-exceeded' =>
      'Too many OTP requests. Please wait before trying again.',
    'network-request-failed' => 'Check your internet connection and try again.',
    'operation-not-allowed' =>
      'Phone sign-in is unavailable for this number or region.',
    'app-not-authorized' ||
    'invalid-app-credential' ||
    'missing-client-identifier' =>
      'Google could not verify this app. Use the latest APK and enable Google Play services.',
    'captcha-check-failed' || 'web-context-canceled' =>
      'App verification was not completed. Try sending the OTP again.',
    'user-disabled' => 'This account has been disabled.',
    _ => 'Phone verification failed. Try again or request a new OTP.',
  };
}
