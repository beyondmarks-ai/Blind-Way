import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/models.dart';
import 'state/app_controller.dart';
import 'ui/dashboard.dart';

class BlindWayApp extends ConsumerWidget {
  const BlindWayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return WithForegroundTask(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Blind Way',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff005a70),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xfff7fafb),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(fontWeight: FontWeight.w800),
            headlineMedium: TextStyle(fontWeight: FontWeight.w700),
            titleLarge: TextStyle(fontWeight: FontWeight.w700),
            bodyLarge: TextStyle(fontSize: 18, height: 1.35),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xffd5e1e5)),
            ),
          ),
        ),
        home: state.session == null ? const SignInScreen() : const Dashboard(),
      ),
    );
  }
}

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/branding/blind_way_logo.png',
                    width: 112,
                    height: 112,
                    semanticLabel: 'Blind Way logo',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Blind Way',
                    style: Theme.of(context).textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Spoken guidance and trusted emergency support.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'How will you use the app?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    selected: state.selectedRole == UserRole.blindUser,
                    icon: Icons.assistant_navigation,
                    title: 'I need vision assistance',
                    subtitle:
                        'Connect a camera, hear guidance, and send emergency alerts.',
                    onTap: () => controller.selectRole(UserRole.blindUser),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    selected: state.selectedRole == UserRole.emergencyContact,
                    icon: Icons.health_and_safety,
                    title: 'I am a trusted contact',
                    subtitle: 'Receive alerts and see live emergency location.',
                    onTap: () =>
                        controller.selectRole(UserRole.emergencyContact),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: state.selectedRole == null || state.isBusy
                        ? null
                        : controller.login,
                    icon: state.isBusy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Continue securely'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: state.selectedRole == null || state.isBusy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const PhoneOtpDialog(),
                          ),
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Sign in with phone OTP'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorText(state.error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PhoneOtpDialog extends ConsumerStatefulWidget {
  const PhoneOtpDialog({super.key});

  @override
  ConsumerState<PhoneOtpDialog> createState() => _PhoneOtpDialogState();
}

class _PhoneOtpDialogState extends ConsumerState<PhoneOtpDialog> {
  final _phoneController = TextEditingController(text: '+91');
  final _codeController = TextEditingController();
  bool _codeSent = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _phone => _phoneController.text.replaceAll(RegExp(r'[\s()-]'), '');

  Future<void> _sendCode() async {
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_phone)) {
      setState(
        () => _error =
            'Enter a phone number with country code, such as +919876543210.',
      );
      return;
    }
    setState(() => _error = null);
    final sent = await ref
        .read(appControllerProvider.notifier)
        .requestPhoneOtp(_phone);
    if (!mounted) return;
    if (sent) {
      setState(() => _codeSent = true);
    } else {
      setState(() => _error = ref.read(appControllerProvider).error);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the six-digit code from the SMS.');
      return;
    }
    setState(() => _error = null);
    final verified = await ref
        .read(appControllerProvider.notifier)
        .verifyPhoneOtp(_phone, code);
    if (!mounted) return;
    if (verified) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = ref.read(appControllerProvider).error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(
      appControllerProvider.select((value) => value.isBusy),
    );
    return AlertDialog(
      title: Text(_codeSent ? 'Enter verification code' : 'Phone sign in'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _codeSent
                  ? 'We sent a six-digit code to $_phone.'
                  : 'Enter your mobile number including the country code.',
            ),
            const SizedBox(height: 16),
            if (!_codeSent)
              TextField(
                controller: _phoneController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+919876543210',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: busy ? null : (_) => _sendCode(),
              )
            else
              TextField(
                controller: _codeController,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Six-digit code',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: busy ? null : (_) => _verifyCode(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_codeSent)
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                    _codeSent = false;
                    _codeController.clear();
                    _error = null;
                  }),
            child: const Text('Change number'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : (_codeSent ? _verifyCode : _sendCode),
          child: busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_codeSent ? 'Verify' : 'Send code'),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 38),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}
