import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:blind_way/src/models/models.dart';
import 'package:blind_way/src/services/api_service.dart';
import 'package:blind_way/src/services/auth_service.dart';
import 'package:blind_way/src/state/app_controller.dart';

class LoginAuth extends Mock implements AuthService {}

class LoginApi extends Mock implements ApiService {}

class LoginController extends AppController {
  @override
  AppState build() => const AppState(selectedRole: UserRole.blindUser);
  @override
  Future<void> refreshContacts() async {}
  @override
  Future<void> refreshActiveAlerts() async {}
}

void main() {
  late LoginAuth auth;
  late LoginApi api;
  late LoginController controller;
  late ProviderContainer container;
  var attempt = 0;
  final session = UserSession(
    subject: 'reader',
    displayName: 'Reader',
    accessToken: 'verified-google-token',
    role: UserRole.blindUser,
  );
  setUp(() {
    attempt = 0;
    auth = LoginAuth();
    api = LoginApi();
    controller = LoginController();
    when(() => auth.attempt).thenAnswer((_) => attempt);
    when(() => auth.restore()).thenAnswer((_) async => session);
    when(() => auth.cancelOtp()).thenAnswer((_) {
      attempt++;
    });
    when(() => auth.logout()).thenAnswer((_) async {
      attempt++;
    });
    when(
      () =>
          api.registerProfile(role: UserRole.blindUser, displayName: 'Reader'),
    ).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(() => controller),
        authServiceProvider.overrideWithValue(auth),
        apiServiceProvider.overrideWithValue(api),
      ],
    );
    container.read(appControllerProvider);
  });
  tearDown(() => container.dispose());

  test(
    'network failure after OTP preserves identity and retry needs no new code',
    () async {
      when(
        () => api.registerProfile(
          role: UserRole.blindUser,
          displayName: 'Reader',
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/v1/profile'),
          type: DioExceptionType.connectionError,
        ),
      );
      await controller.handlePhoneAuthEvent(
        PhoneAuthEvent(PhoneAuthEventType.authenticated, session: session),
      );
      expect(container.read(appControllerProvider).loginPending, true);
      expect(container.read(appControllerProvider).session, isNull);
      expect(
        container.read(appControllerProvider).error,
        contains('No new OTP'),
      );
      verifyNever(() => auth.logout());
      when(
        () => api.registerProfile(
          role: UserRole.blindUser,
          displayName: 'Reader',
        ),
      ).thenAnswer((_) async {});
      await controller.retryLogin();
      expect(container.read(appControllerProvider).session?.subject, 'reader');
      expect(container.read(appControllerProvider).loginPending, false);
      expect(container.read(appControllerProvider).isBusy, false);
    },
  );
  test(
    'server rejection does not grant an app session or discard valid Google login',
    () async {
      final request = RequestOptions(path: '/v1/profile');
      when(
        () => api.registerProfile(
          role: UserRole.blindUser,
          displayName: 'Reader',
        ),
      ).thenThrow(
        DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: request, statusCode: 401),
        ),
      );
      await controller.retryLogin();
      expect(container.read(appControllerProvider).session, isNull);
      expect(container.read(appControllerProvider).loginPending, true);
      verifyNever(() => auth.logout());
    },
  );
  test('cancel invalidates a pending account request', () async {
    final pending = Completer<void>();
    when(
      () =>
          api.registerProfile(role: UserRole.blindUser, displayName: 'Reader'),
    ).thenAnswer((_) => pending.future);
    final retry = controller.retryLogin();
    await Future<void>.delayed(Duration.zero);
    await controller.resetPhoneSignIn();
    pending.complete();
    await retry;
    expect(container.read(appControllerProvider).session, isNull);
    expect(container.read(appControllerProvider).loginPending, false);
  });
  test(
    'offline token refresh can retry but revoked credentials need a new login',
    () async {
      when(
        () => auth.restore(),
      ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));
      await controller.retryLogin();
      expect(container.read(appControllerProvider).loginPending, true);
      verifyNever(() => auth.logout());
      when(
        () => auth.restore(),
      ).thenThrow(FirebaseAuthException(code: 'user-token-expired'));
      await controller.retryLogin();
      expect(container.read(appControllerProvider).loginPending, false);
      verify(() => auth.logout()).called(1);
    },
  );
}
