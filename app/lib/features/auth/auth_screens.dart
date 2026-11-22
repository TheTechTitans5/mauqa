import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/env.dart';
import '../../core/l10n/strings.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/auth_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Orb3D(size: 120, icon: Icons.settings_rounded),
              const SizedBox(height: 24),
              Text('Backend not configured', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('Run the app with your Supabase URL and anon key:\n\n'
                  'flutter run --dart-define-from-file=env/dev.json\n\nSee README → "Run the app".', textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'ur', label: Text('اردو'))],
                  selected: {settings.locale.languageCode},
                  style: SegmentedButton.styleFrom(foregroundColor: Colors.white, selectedForegroundColor: AppColors.navy, selectedBackgroundColor: Colors.white),
                  onSelectionChanged: (v) => ref.read(appSettingsProvider.notifier).update(settings.copyWith(locale: Locale(v.first))),
                ),
              ),
              const Spacer(),
              const Center(child: _FloatingOrbs()),
              const Spacer(),
              Text(context.t('app.name'), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, letterSpacing: 2)),
              const SizedBox(height: 8),
              Text(context.t('auth.welcomeTitle'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 12),
              Text(context.t('auth.welcomeBody'), style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 8),
              Text(context.t('app.tagline'), style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: AppColors.teal),
                onPressed: () => context.push('/signup'),
                child: Text(context.t('auth.getStarted')),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                onPressed: () => context.push('/login'),
                child: Text(context.t('auth.haveAccount')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FloatingOrbs extends StatefulWidget {
  const _FloatingOrbs();
  @override
  State<_FloatingOrbs> createState() => _FloatingOrbsState();
}

class _FloatingOrbsState extends State<_FloatingOrbs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = reduce ? 0.5 : Curves.easeInOut.transform(_c.value);
        return SizedBox(
          width: 260,
          height: 220,
          child: Stack(children: [
            Positioned(left: 10, top: 30 + t * 12, child: const Orb3D(size: 80, colors: [AppColors.amber, AppColors.coral], icon: Icons.school_rounded)),
            Positioned(left: 85, top: 70 - t * 14, child: const Orb3D(size: 120, icon: Icons.rocket_launch_rounded)),
            Positioned(right: 0, top: 10 + t * 18, child: const Orb3D(size: 70, colors: [AppColors.lavender, Color(0xFF4F7BE0)], icon: Icons.work_rounded)),
          ]),
        );
      },
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            GlassCard(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          ]),
        ),
      );
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _phone = false, _busy = false, _obscure = true;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(authRepositoryProvider);
    await runAction(context, () => _phone
        ? repo.signInWithPhone(Validators.normalizePhone(_id.text), _pw.text)
        : repo.signInWithEmail(_id.text, _pw.text));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _otpLogin() async {
    final err = Validators.phonePk(_id.text);
    if (err != null) return showSnack(context, err, error: true);
    final phone = Validators.normalizePhone(_id.text);
    if (await runAction(context, () => ref.read(authRepositoryProvider).sendPhoneOtp(phone)) && mounted) {
      context.push('/otp?phone=${Uri.encodeComponent(phone)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(title: context.t('auth.login'), children: [
      Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(context.t('auth.useEmail')), icon: const Icon(Icons.mail_outline)),
              ButtonSegment(value: true, label: Text(context.t('auth.usePhone')), icon: const Icon(Icons.phone_iphone)),
            ],
            selected: {_phone},
            onSelectionChanged: (v) => setState(() => _phone = v.first),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _id,
            keyboardType: _phone ? TextInputType.phone : TextInputType.emailAddress,
            autofillHints: [_phone ? AutofillHints.telephoneNumber : AutofillHints.email],
            decoration: InputDecoration(labelText: context.t(_phone ? 'auth.phone' : 'auth.email'), hintText: _phone ? '03001234567' : null),
            validator: _phone ? Validators.phonePk : Validators.email,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pw,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: context.t('auth.password'),
              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
            ),
            validator: (v) => Validators.required(v),
            onFieldSubmitted: (_) => _submit(),
          ),
          Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => context.push('/forgot'), child: Text(context.t('auth.forgot')))),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.t('auth.login'))),
          if (_phone) ...[const SizedBox(height: 8), OutlinedButton(onPressed: _busy ? null : _otpLogin, child: const Text('Send me a one-time code instead'))],
          if (Env.googleSignInEnabled) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
              onPressed: () => runAction(context, () => ref.read(authRepositoryProvider).signInWithGoogle()),
              label: Text(context.t('auth.google')),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.pushReplacement('/signup'), child: Text(context.t('auth.signup'))),
        ]),
      ),
    ]);
  }
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _phone = false, _accepted = false, _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _id, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_accepted) return showSnack(context, context.t('auth.acceptTerms'), error: true);
    setState(() => _busy = true);
    final repo = ref.read(authRepositoryProvider);
    final lang = ref.read(appSettingsProvider).locale.languageCode;
    if (_phone) {
      final phone = Validators.normalizePhone(_id.text);
      final ok = await runAction(context, () => repo.signUpWithPhone(phone: phone, password: _pw.text, fullName: _name.text, language: lang));
      if (ok && mounted) context.push('/otp?phone=${Uri.encodeComponent(phone)}');
    } else {
      final ok = await runAction(context, () => repo.signUpWithEmail(email: _id.text, password: _pw.text, fullName: _name.text, language: lang));
      if (ok && mounted && repo.session == null) {
        await showDialog<void>(context: context, builder: (c) => AlertDialog(
          title: const Icon(Icons.mark_email_read_rounded, size: 48, color: AppColors.teal),
          content: Text(context.t('auth.checkEmail')),
          actions: [
            TextButton(onPressed: () => runAction(c, () => repo.resendEmailConfirmation(_id.text), success: 'Sent again'), child: const Text('Resend')),
            FilledButton(onPressed: () => Navigator.pop(c), child: Text(context.t('common.done'))),
          ],
        ));
        if (mounted) context.pushReplacement('/login');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(title: context.t('auth.signup'), children: [
      Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(context.t('auth.useEmail'))),
              ButtonSegment(value: true, label: Text(context.t('auth.usePhone'))),
            ],
            selected: {_phone},
            onSelectionChanged: (v) => setState(() => _phone = v.first),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: context.t('auth.fullName')),
              validator: (v) => Validators.required(v) ?? ((v!.trim().length < 2) ? 'Enter your name' : null)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _id,
            keyboardType: _phone ? TextInputType.phone : TextInputType.emailAddress,
            decoration: InputDecoration(labelText: context.t(_phone ? 'auth.phone' : 'auth.email'), hintText: _phone ? '03001234567' : null),
            validator: _phone ? Validators.phonePk : Validators.email,
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _pw, obscureText: true, decoration: InputDecoration(labelText: context.t('auth.password'), helperText: 'At least 8 characters with letters and numbers'),
              validator: Validators.password),
          const SizedBox(height: 12),
          TextFormField(controller: _pw2, obscureText: true, decoration: InputDecoration(labelText: context.t('auth.confirmPassword')),
              validator: (v) => v != _pw.text ? 'Passwords do not match' : null),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _accepted,
            onChanged: (v) => setState(() => _accepted = v ?? false),
            title: Text(context.t('auth.acceptTerms')),
            controlAffinity: ListTileControlAffinity.leading,
            subtitle: Wrap(children: [
              TextButton(onPressed: () => context.push('/legal?kind=terms'), child: Text(context.t('settings.terms'))),
              TextButton(onPressed: () => context.push('/legal?kind=privacy'), child: Text(context.t('settings.privacyPolicy'))),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.t('auth.signup'))),
        ]),
      ),
    ]);
  }
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});
  final String phone;
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(title: context.t('auth.otpTitle'), children: [
      Text(context.t('auth.otpBody', {'phone': widget.phone})),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w700),
        decoration: const InputDecoration(counterText: ''),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : () async {
          if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) return showSnack(context, 'Enter the 6-digit code', error: true);
          setState(() => _busy = true);
          await runAction(context, () => ref.read(authRepositoryProvider).verifyPhoneOtp(widget.phone, _code.text));
          if (mounted) setState(() => _busy = false);
        },
        child: Text(context.t('auth.verify')),
      ),
      TextButton(onPressed: () => runAction(context, () => ref.read(authRepositoryProvider).sendPhoneOtp(widget.phone), success: 'Code sent'),
          child: const Text('Resend code')),
    ]);
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: context.t('auth.forgot'), children: [
        Form(
          key: _form,
          child: TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: context.t('auth.email')), validator: Validators.email),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            if (!_form.currentState!.validate()) return;
            // Same message whether or not the account exists (prevents account enumeration).
            await runAction(context, () => ref.read(authRepositoryProvider).sendPasswordReset(_email.text), success: context.t('auth.resetSent'));
          },
          child: Text(context.t('common.continue')),
        ),
        const SizedBox(height: 8),
        const Text('Signed up with a phone number? Log in with a one-time code from the login screen, then change your password in Settings.'),
      ]);
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(title: context.t('auth.setPassword'), children: [
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(controller: _pw, obscureText: true, decoration: InputDecoration(labelText: context.t('auth.newPassword')), validator: Validators.password),
            const SizedBox(height: 12),
            TextFormField(controller: _pw2, obscureText: true, decoration: InputDecoration(labelText: context.t('auth.confirmPassword')),
                validator: (v) => v != _pw.text ? 'Passwords do not match' : null),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            if (!_form.currentState!.validate()) return;
            if (await runAction(context, () => ref.read(authRepositoryProvider).updatePassword(_pw.text), success: context.t('auth.passwordUpdated')) &&
                context.mounted) {
              context.go('/home');
            }
          },
          child: Text(context.t('common.save')),
        ),
      ]);
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final terms = kind == 'terms';
    return Scaffold(
      appBar: AppBar(title: Text(context.t(terms ? 'settings.terms' : 'settings.privacyPolicy'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const InfoBanner(text: 'Template text for the Mauqa project. Have it reviewed by a qualified lawyer before public launch.'),
        const SizedBox(height: 8),
        Text(terms ? _terms : _privacy, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
      ]),
    );
  }
}

const _terms = '''Mauqa helps you discover opportunities and links you to the official websites of the organisations that run them.

1. Mauqa is not the organiser of any listed opportunity. Applications are submitted on the official website; decisions are made by the organiser.
2. We check listings against official sources and label them (Verified, Pending verification, Unverified). Always confirm details on the official website before applying or paying any fee.
3. Eligibility results are guidance based on the information you provide and the structured criteria we hold. The official announcement is the final authority.
4. Do not submit false, misleading or abusive content, reports or stories.
5. Never share your passwords for official portals with anyone, including Mauqa.
6. You can delete your account at any time from Settings.''';

const _privacy = '''What we store: your account (email or phone), the profile information you choose to add, your saved/interested opportunities, application tracking records, notification preferences and documents you upload.

Sensitive information (household income, disability status, CNIC) is optional. Income and disability are used for eligibility checks only if you switch on "Use my income/disability info for eligibility checks".

Your documents are stored in private storage. Only you can open them, through links that expire after two minutes.

We do not sell your data. We do not share your profile with opportunity providers.

You can download a copy of your data or permanently delete your account from Settings → Privacy.

Retention: read notifications are deleted after 12 months, search history after 6 months, and all your data immediately when you delete your account (backups roll off within 30 days).''';
