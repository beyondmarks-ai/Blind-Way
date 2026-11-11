import 'package:blind_way/src/app.dart';
import 'package:blind_way/src/models/models.dart';
import 'package:blind_way/src/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PhoneScreenController extends AppController {
  PhoneScreenController({this.recovery = false});
  final bool recovery;
  bool retried = false;
  String? number, code;
  @override
  AppState build() => AppState(loginPending: recovery);
  @override
  Future<void> retryLogin() async {
    retried = true;
  }

  @override
  Future<void> sendOtp({
    required String phoneNumber,
    required String displayName,
    bool resend = false,
  }) async {
    number = phoneNumber;
    state = state.copyWith(
      otpSent: true,
      otpPhone: '+919876543210',
      otpMessage: 'Enter your SMS code.',
      resendAvailableAt: DateTime.now().millisecondsSinceEpoch + 60000,
    );
  }

  @override
  Future<void> verifyOtp(String value) async {
    code = value;
  }

  @override
  Future<void> resetPhoneSignIn() async {
    state = const AppState(selectedRole: UserRole.blindUser);
  }
}

void main() {
  testWidgets(
    'verified login recovery offers retry without requesting another OTP',
    (tester) async {
      final controller = PhoneScreenController(recovery: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      expect(find.text('Send OTP'), findsNothing);
      expect(find.text('6-digit SMS code'), findsNothing);
      await tester.ensureVisible(find.text('Retry sign-in'));
      await tester.tap(find.text('Retry sign-in'));
      expect(controller.retried, true);
      expect(controller.number, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'phone screen sends number, accepts one OTP field and permits cancellation',
    (tester) async {
      final controller = PhoneScreenController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send OTP'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('I need vision assistance'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Asha');
      await tester.enterText(find.byType(TextField).at(1), '9876543210');
      await tester.ensureVisible(find.text('Send OTP'));
      await tester.tap(find.text('Send OTP'));
      await tester.pump();
      expect(controller.number, '9876543210');
      expect(find.text('6-digit SMS code'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Resend code in 60 seconds'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField).at(2), '12a34567');
      await tester.ensureVisible(find.text('Verify and sign in'));
      await tester.tap(find.text('Verify and sign in'));
      await tester.pump();
      expect(controller.code, '123456');
      await tester.ensureVisible(find.text('Change number or cancel'));
      await tester.tap(find.text('Change number or cancel'));
      await tester.pump();
      expect(find.text('6-digit SMS code'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
