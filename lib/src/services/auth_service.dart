import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/models.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _auth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  String? _verificationId;

  Stream<String?> get tokenChanges =>
      _auth.idTokenChanges().asyncMap((user) => user?.getIdToken());

  Future<UserSession?> restore(UserRole role) async {
    final user = _auth.currentUser;
    return user == null ? null : _session(user, role);
  }

  Future<void> sendPhoneOtp(String phoneNumber) async {
    // The role is selected before each login. Start a fresh Firebase session so
    // a previously cached user can never bypass verification for a new number.
    await _auth.signOut();
    _verificationId = null;
    final sent = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          await _auth.signInWithCredential(credential);
          if (!sent.isCompleted) sent.complete();
        } on FirebaseAuthException catch (error) {
          if (!sent.isCompleted) sent.completeError(_friendlyError(error));
        }
      },
      verificationFailed: (error) {
        if (!sent.isCompleted) sent.completeError(_friendlyError(error));
      },
      codeSent: (verificationId, _) {
        _verificationId = verificationId;
        if (!sent.isCompleted) sent.complete();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );

    await sent.future.timeout(
      const Duration(seconds: 75),
      onTimeout: () => throw TimeoutException(
        'Firebase did not send the verification code. Please try again.',
      ),
    );
  }

  Future<UserSession> loginWithPhoneOtp(
    UserRole role, {
    required String phoneNumber,
    required String verificationCode,
  }) async {
    var user = _auth.currentUser;
    if (user == null) {
      final verificationId = _verificationId;
      if (verificationId == null) {
        throw StateError('Request a new Firebase verification code first.');
      }
      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: verificationCode,
        );
        user = (await _auth.signInWithCredential(credential)).user;
      } on FirebaseAuthException catch (error) {
        throw _friendlyError(error);
      }
    }
    if (user == null) throw StateError('Firebase sign-in did not complete.');
    _verificationId = null;
    return _session(user, role, phoneNumber: phoneNumber);
  }

  Future<void> logout() async {
    _verificationId = null;
    await _auth.signOut();
  }

  Future<UserSession> _session(
    User user,
    UserRole role, {
    String? phoneNumber,
  }) async {
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase did not issue an ID token.');
    }
    return UserSession(
      subject: user.uid,
      displayName:
          user.displayName ??
          user.phoneNumber ??
          phoneNumber ??
          'Blind Way user',
      accessToken: token,
      role: role,
    );
  }

  Exception _friendlyError(FirebaseAuthException error) {
    final message = switch (error.code) {
      'invalid-phone-number' =>
        'Enter a valid phone number including the country code.',
      'invalid-verification-code' => 'The verification code is incorrect.',
      'session-expired' => 'The verification code expired. Request a new code.',
      'too-many-requests' =>
        'Too many verification attempts. Please wait and try again.',
      'quota-exceeded' =>
        'The Firebase SMS quota has been reached. Please try again later.',
      'operation-not-allowed' =>
        'Phone sign-in is not enabled in Firebase Authentication.',
      'network-request-failed' =>
        'Network unavailable. Check the internet connection and try again.',
      _ => error.message ?? 'Firebase Authentication failed.',
    };
    return Exception(message);
  }
}
