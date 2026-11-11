import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final locked = state.isBusy || state.otpSent || state.loginPending;
    final remaining =
        ((state.resendAvailableAt - DateTime.now().millisecondsSinceEpoch) /
                1000)
            .ceil()
            .clamp(0, 120);
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
                    onTap: locked
                        ? null
                        : () => controller.selectRole(UserRole.blindUser),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    selected: state.selectedRole == UserRole.emergencyContact,
                    icon: Icons.health_and_safety,
                    title: 'I am a trusted contact',
                    subtitle: 'Receive alerts and see live emergency location.',
                    onTap: locked
                        ? null
                        : () =>
                              controller.selectRole(UserRole.emergencyContact),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    readOnly: locked,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                    ),
                    autofillHints: const [AutofillHints.name],
                    textCapitalization: TextCapitalization.words,
                    maxLength: 80,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    readOnly: locked,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [
                      AutofillHints.telephoneNumberNational,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Mobile number (India)',
                      hintText: '10-digit number',
                      prefixText: '+91 ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.loginPending) ...[
                    FilledButton.icon(
                      onPressed: state.isBusy ? null : controller.retryLogin,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        state.isBusy ? 'Opening account...' : 'Retry sign-in',
                      ),
                    ),
                  ] else if (state.otpSent) ...[
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      readOnly: state.isBusy,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '6-digit SMS code',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!state.isBusy) controller.verifyOtp(_code.text);
                      },
                    ),
                    FilledButton(
                      onPressed: state.isBusy
                          ? null
                          : () => controller.verifyOtp(_code.text),
                      child: Text(
                        state.isBusy ? 'Verifying…' : 'Verify and sign in',
                      ),
                    ),
                    TextButton(
                      onPressed: state.isBusy || remaining > 0
                          ? null
                          : () {
                              _code.clear();
                              controller.sendOtp(
                                phoneNumber: _phone.text,
                                displayName: _name.text,
                                resend: true,
                              );
                            },
                      child: Text(
                        remaining > 0
                            ? 'Resend code in $remaining seconds'
                            : 'Resend code',
                      ),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed:
                          state.selectedRole == null ||
                              state.isBusy ||
                              remaining > 0
                          ? null
                          : () => controller.sendOtp(
                              phoneNumber: _phone.text,
                              displayName: _name.text,
                            ),
                      icon: const Icon(Icons.sms_outlined),
                      label: Text(
                        state.isBusy
                            ? 'Sending code…'
                            : remaining > 0
                            ? 'Try again in $remaining seconds'
                            : 'Send OTP',
                      ),
                    ),
                  if (state.otpSent || state.isBusy || state.loginPending)
                    TextButton(
                      onPressed: () {
                        _code.clear();
                        controller.resetPhoneSignIn();
                      },
                      child: const Text('Change number or cancel'),
                    ),
                  if (state.otpMessage.isNotEmpty)
                    Semantics(liveRegion: true, child: Text(state.otpMessage)),
                  const SizedBox(height: 10),
                  const Text(
                    'No password needed. By sending a code, you agree that Google uses your phone number for verification and abuse prevention. SMS charges may apply.',
                    textAlign: TextAlign.center,
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    enabled: onTap != null,
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
