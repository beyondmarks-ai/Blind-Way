import 'dart:async';
import 'dart:convert';
import 'package:blind_way/src/models/models.dart';
import 'package:blind_way/src/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockCredential extends Mock implements UserCredential {}

class MemoryStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  String? get value => values['phone_session_v1'];
  set value(String? v) {
    if (v == null) {
      values.remove('phone_session_v1');
    } else {
      values['phone_session_v1'] = v;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  late MockAuth platform;
  late MockUser user;
  late MockCredential credential;
  late MemoryStorage storage;
  late AuthService auth;
  late Map<Symbol, dynamic> callbacks;
  late List<PhoneAuthEvent> events;
  Future<void> drain() => Future<void>.delayed(Duration.zero);
  Future<void> request() => auth.requestOtp(
    phoneNumber: '9876543210',
    role: UserRole.blindUser,
    displayName: 'Asha',
  );
  void sent() => (callbacks[#codeSent] as PhoneCodeSent)('verification', 17);
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue((PhoneAuthCredential credential) {});
    registerFallbackValue((FirebaseAuthException error) {});
    registerFallbackValue((String id, int? token) {});
    registerFallbackValue((String id) {});
    registerFallbackValue(
      PhoneAuthProvider.credential(verificationId: 'v', smsCode: '123456'),
    );
  });
  setUp(() {
    platform = MockAuth();
    user = MockUser();
    credential = MockCredential();
    storage = MemoryStorage();
    events = [];
    when(
      () => platform.idTokenChanges(),
    ).thenAnswer((_) => const Stream.empty());
    when(() => platform.currentUser).thenReturn(user);
    when(() => platform.signOut()).thenAnswer((_) async {});
    when(() => user.uid).thenReturn('uid');
    when(() => user.phoneNumber).thenReturn('+919876543210');
    when(() => user.getIdToken()).thenAnswer((_) async => 'google-id-token');
    when(() => credential.user).thenReturn(user);
    when(
      () => platform.signInWithCredential(any()),
    ).thenAnswer((_) async => credential);
    when(
      () => platform.verifyPhoneNumber(
        phoneNumber: any(named: 'phoneNumber'),
        timeout: any(named: 'timeout'),
        forceResendingToken: any(named: 'forceResendingToken'),
        verificationCompleted: any(named: 'verificationCompleted'),
        verificationFailed: any(named: 'verificationFailed'),
        codeSent: any(named: 'codeSent'),
        codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
      ),
    ).thenAnswer((call) async {
      callbacks = call.namedArguments;
    });
    auth = AuthService(firebaseAuth: platform, storage: storage);
    auth.phoneEvents.listen(events.add);
  });
  tearDown(() => auth.dispose());
  test('normalizes Indian numbers and rejects invalid input', () {
    expect(AuthService.normalizePhone('+91 98765 43210'), '+919876543210');
    expect(() => AuthService.normalizePhone('123'), throwsFormatException);
  });
  test('requires six digits and an active challenge', () async {
    await expectLater(auth.verifyOtp('123'), throwsFormatException);
    await expectLater(auth.verifyOtp('123456'), throwsStateError);
  });
  test(
    'manual OTP signs in and stores only UID and profile metadata',
    () async {
      await request();
      sent();
      await auth.verifyOtp('123456');
      await drain();
      expect(events.last.type, PhoneAuthEventType.authenticated);
      expect(events.last.session!.subject, 'uid');
      expect(jsonDecode(storage.value!), {
        'uid': 'uid',
        'role': 'blindUser',
        'name': 'Asha',
      });
      expect(await auth.accessToken(), 'google-id-token');
    },
  );
  test('incorrect OTP is reported without accepting a session', () async {
    await request();
    sent();
    when(
      () => platform.signInWithCredential(any()),
    ).thenThrow(FirebaseAuthException(code: 'invalid-verification-code'));
    await auth.verifyOtp('654321');
    await drain();
    expect(events.last.message, contains('incorrect'));
    expect(await auth.accessToken(), isNull);
  });
  test('automatic and manual completion sign in only once', () async {
    await request();
    sent();
    (callbacks[#verificationCompleted] as PhoneVerificationCompleted)(
      PhoneAuthProvider.credential(verificationId: 'v', smsCode: '123456'),
    );
    await auth.verifyOtp('123456');
    await drain();
    verify(() => platform.signInWithCredential(any())).called(1);
    expect(
      events.where((e) => e.type == PhoneAuthEventType.authenticated).length,
      1,
    );
  });
  test('cancel ignores late code and automatic completion callbacks', () async {
    await request();
    auth.cancelOtp();
    sent();
    (callbacks[#verificationCompleted] as PhoneVerificationCompleted)(
      PhoneAuthProvider.credential(verificationId: 'v', smsCode: '123456'),
    );
    await drain();
    expect(events, isEmpty);
    verifyNever(() => platform.signInWithCredential(any()));
  });
  test('logout invalidates a credential completion in progress', () async {
    final pending = Completer<UserCredential>();
    when(
      () => platform.signInWithCredential(any()),
    ).thenAnswer((_) => pending.future);
    await request();
    sent();
    final signing = auth.verifyOtp('123456');
    await drain();
    await auth.logout();
    pending.complete(credential);
    await signing;
    await drain();
    expect(
      events.where((e) => e.type == PhoneAuthEventType.authenticated),
      isEmpty,
    );
    expect(storage.value, isNull);
    expect(await auth.accessToken(), isNull);
  });
  test(
    'restores matching Google user and deletes legacy Entra session',
    () async {
      storage.values['entra_session_v1'] = 'old';
      storage.value = jsonEncode({
        'uid': 'uid',
        'role': 'blindUser',
        'name': 'Asha',
      });
      expect((await auth.restore())!.subject, 'uid');
      expect(storage.values.containsKey('entra_session_v1'), false);
    },
  );
  test('does not restore mismatched user metadata', () async {
    storage.value = jsonEncode({
      'uid': 'other',
      'role': 'blindUser',
      'name': 'Asha',
    });
    expect(await auth.restore(), isNull);
    expect(await auth.accessToken(), isNull);
  });
  test(
    'never falls back to a cached token when native refresh fails',
    () async {
      await request();
      sent();
      await auth.verifyOtp('123456');
      when(
        () => user.getIdToken(),
      ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));
      await expectLater(
        auth.accessToken(),
        throwsA(isA<FirebaseAuthException>()),
      );
    },
  );
}
