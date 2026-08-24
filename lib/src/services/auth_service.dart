import 'package:auth0_flutter/auth0_flutter.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';

class AuthService {
  AuthService()
    : _auth0 = AppConfig.authConfigured
          ? Auth0(AppConfig.auth0Domain, AppConfig.auth0ClientId)
          : null;

  final Auth0? _auth0;

  Future<UserSession?> restore(UserRole role) async {
    if (_auth0 == null ||
        !await _auth0.credentialsManager.hasValidCredentials()) {
      return null;
    }
    final credentials = await _auth0.credentialsManager.credentials();
    return _session(credentials, role);
  }

  Future<UserSession> login(UserRole role, {String? connection}) async {
    if (_auth0 == null) {
      if (!kDebugMode) {
        throw StateError('Auth0 build configuration is missing.');
      }
      return UserSession(
        subject: 'debug-${role.name}',
        displayName: role == UserRole.blindUser ? 'Demo user' : 'Demo contact',
        accessToken: 'debug-token',
        role: role,
      );
    }
    final credentials = await _auth0
        .webAuthentication(scheme: 'https')
        .login(
          audience: AppConfig.auth0Audience,
          parameters: connection == null
              ? const {}
              : {'connection': connection},
        );
    return _session(credentials, role);
  }

  Future<void> sendPhoneOtp(String phoneNumber) async {
    final auth0 = _auth0;
    if (auth0 == null) {
      throw StateError('Auth0 build configuration is missing.');
    }
    await auth0.api.startPasswordlessWithPhoneNumber(
      phoneNumber: phoneNumber,
      passwordlessType: PasswordlessType.code,
    );
  }

  Future<UserSession> loginWithPhoneOtp(
    UserRole role, {
    required String phoneNumber,
    required String verificationCode,
  }) async {
    final auth0 = _auth0;
    if (auth0 == null) {
      throw StateError('Auth0 build configuration is missing.');
    }
    final credentials = await auth0.api.loginWithSmsCode(
      phoneNumber: phoneNumber,
      verificationCode: verificationCode,
      audience: AppConfig.auth0Audience,
    );
    await auth0.credentialsManager.storeCredentials(credentials);
    return _session(credentials, role);
  }

  Future<void> logout() async {
    if (_auth0 != null) {
      await _auth0.webAuthentication(scheme: 'https').logout();
    }
  }

  UserSession _session(Credentials credentials, UserRole role) => UserSession(
    subject: credentials.user.sub,
    displayName:
        credentials.user.name ??
        credentials.user.email ??
        credentials.user.phoneNumber ??
        'User',
    accessToken: credentials.accessToken,
    role: role,
  );
}
