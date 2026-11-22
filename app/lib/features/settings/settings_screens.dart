import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/strings.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

const appVersion = '1.0.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final n = ref.read(appSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.title'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        ListTile(
          leading: const Icon(Icons.translate_rounded),
          title: Text(context.t('settings.language')),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ur', label: Text('اردو'))],
            selected: {s.locale.languageCode},
            onSelectionChanged: (v) async {
              await n.update(s.copyWith(locale: Locale(v.first)));
              await ref.read(profileRepositoryProvider).updateProfile({'preferred_language': v.first}).catchError((_) {});
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: Text(context.t('settings.theme')),
          trailing: DropdownButton<ThemeMode>(
            value: s.themeMode,
            onChanged: (v) => n.update(s.copyWith(themeMode: v)),
            items: [
              DropdownMenuItem(value: ThemeMode.system, child: Text(context.t('settings.themeSystem'))),
              DropdownMenuItem(value: ThemeMode.light, child: Text(context.t('settings.themeLight'))),
              DropdownMenuItem(value: ThemeMode.dark, child: Text(context.t('settings.themeDark'))),
            ],
          ),
        ),
        _Nav(Icons.accessibility_new_rounded, context.t('settings.accessibility'), '/settings/accessibility'),
        _Nav(Icons.notifications_active_outlined, context.t('notif.prefs'), '/notifications/prefs'),
        _Nav(Icons.auto_awesome_outlined, context.t('settings.recPrefs'), null, onTap: () => _recPrefs(context, ref)),
        _Nav(Icons.privacy_tip_outlined, context.t('settings.privacy'), '/settings/privacy'),
        _Nav(Icons.password_rounded, context.t('settings.changePassword'), '/settings/password'),
        const Divider(),
        _Nav(Icons.description_outlined, context.t('settings.terms'), '/legal?kind=terms'),
        _Nav(Icons.policy_outlined, context.t('settings.privacyPolicy'), '/legal?kind=privacy'),
        _Nav(Icons.help_outline_rounded, context.t('settings.help'), '/tools/guides?category=faq'),
        _Nav(Icons.support_agent_rounded, 'Contact us', '/settings/feedback?kind=support'),
        _Nav(Icons.rate_review_outlined, context.t('settings.feedback'), '/settings/feedback?kind=feedback'),
        _Nav(Icons.bug_report_outlined, context.t('settings.reportIssue'), '/settings/feedback?kind=technical_issue'),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: Text(context.t('settings.about')),
          subtitle: Text(context.t('settings.version', {'v': appVersion})),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Mauqa',
            applicationVersion: appVersion,
            applicationIcon: const Orb3D(size: 48, icon: Icons.auto_awesome),
            children: const [Text('Opportunity discovery for Pakistan. Listings link to official sources; always confirm details on the official website.')],
          ),
        ),
      ]),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav(this.icon, this.label, this.route, {this.onTap});
  final IconData icon;
  final String label;
  final String? route;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) =>
      ListTile(leading: Icon(icon), title: Text(label), trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap ?? () => context.push(route!));
}

Future<void> _recPrefs(BuildContext context, WidgetRef ref) async {
  final p = await ref.read(fullProfileProvider.future);
  if (!context.mounted) return;
  final prefs = Map<String, dynamic>.from(p.profile.recommendationPrefs);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(builder: (c, set) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(title: Text(context.t('settings.verifiedOnly')), value: prefs['verified_only'] == true, onChanged: (v) => set(() => prefs['verified_only'] = v)),
        SwitchListTile(title: Text(context.t('settings.hideDemo')), value: prefs['include_demo'] == false, onChanged: (v) => set(() => prefs['include_demo'] = !v)),
        SwitchListTile(title: const Text('Remote opportunities only'), value: prefs['remote_only'] == true, onChanged: (v) => set(() => prefs['remote_only'] = v)),
        SwitchListTile(title: const Text('Also show ones I may not qualify for'), value: prefs['include_not_eligible'] == true,
            onChanged: (v) => set(() => prefs['include_not_eligible'] = v)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () async {
              if (await runAction(c, () => ref.read(profileRepositoryProvider).updateProfile({'recommendation_prefs': prefs}), success: context.t('profile.recsUpdated'))) {
                ref.invalidate(fullProfileProvider);
                if (c.mounted) Navigator.pop(c);
              }
            },
            child: Text(context.t('common.save')),
          ),
        ),
      ]),
    )),
  );
}

class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final n = ref.read(appSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.accessibility'))),
      body: ListView(children: [
        ListTile(
          title: Text(context.t('settings.textSize')),
          subtitle: Slider(value: s.textScale, min: 0.85, max: 1.6, divisions: 15, label: '${(s.textScale * 100).round()}%',
              onChanged: (v) => n.update(s.copyWith(textScale: v))),
        ),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Preview: Scholarships close soon — check your eligibility.',
            style: Theme.of(context).textTheme.bodyLarge)),
        SwitchListTile(title: Text(context.t('settings.highContrast')), value: s.highContrast, onChanged: (v) => n.update(s.copyWith(highContrast: v))),
        SwitchListTile(title: Text(context.t('settings.simpleMode')), subtitle: const Text('Larger text and fewer sections on Home'),
            value: s.simpleMode, onChanged: (v) => n.update(s.copyWith(simpleMode: v))),
        SwitchListTile(title: Text(context.t('settings.reduceMotion')), value: s.reduceMotion, onChanged: (v) => n.update(s.copyWith(reduceMotion: v))),
        SwitchListTile(title: Text(context.t('settings.lowData')), subtitle: const Text('Turns off animations and organisation logos'),
            value: s.lowData, onChanged: (v) => n.update(s.copyWith(lowData: v))),
      ]),
    );
  }
}

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(fullProfileProvider).valueOrNull?.profile;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('settings.privacy'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InfoBanner(text: context.t('docs.private'), color: AppColors.teal, icon: Icons.lock_outline),
        if (p != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('profile.shareSensitive')),
            subtitle: Text(context.t('profile.sensitiveNote')),
            value: p.shareSensitive,
            onChanged: (v) async {
              if (await runAction(context, () => ref.read(profileRepositoryProvider).updateProfile({'share_sensitive_for_eligibility': v}))) {
                ref.invalidate(fullProfileProvider);
              }
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_shared_outlined),
          title: const Text('Document permissions'),
          subtitle: const Text('Documents are visible only to you. Mauqa staff cannot open them. Links you open expire after 2 minutes.'),
          onTap: () => context.push('/documents'),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.download_rounded),
          title: Text(context.t('settings.downloadData')),
          subtitle: const Text('A JSON file with your profile, lists, applications and settings'),
          onTap: () async {
            Map<String, dynamic>? data;
            if (!await runAction(context, () async => data = await ref.read(contentRepositoryProvider).exportMyData())) return;
            final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
            await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'application/json', name: 'mauqa-my-data.json')], subject: 'My Mauqa data');
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_forever_rounded, color: AppColors.coral),
          title: Text(context.t('settings.deleteAccount'), style: const TextStyle(color: AppColors.coral)),
          onTap: () async {
            final c = TextEditingController();
            final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
              title: Text(context.t('settings.deleteAccount')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(context.t('settings.deleteConfirm')),
                const SizedBox(height: 12),
                TextField(controller: c, decoration: const InputDecoration(hintText: 'DELETE')),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: Text(context.t('common.cancel'))),
                FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                    onPressed: () => Navigator.pop(d, c.text.trim() == 'DELETE'), child: Text(context.t('common.delete'))),
              ],
            ));
            c.dispose();
            if (ok == true && context.mounted) await runAction(context, () => ref.read(contentRepositoryProvider).deleteMyAccount());
          },
        ),
        const SizedBox(height: 8),
        Text('Retention: read notifications are deleted after 12 months and search history after 6 months.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.t('settings.changePassword'))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password'), validator: (v) => Validators.required(v)),
            const SizedBox(height: 12),
            TextFormField(controller: _new, obscureText: true, decoration: InputDecoration(labelText: context.t('auth.newPassword')), validator: Validators.password),
            const SizedBox(height: 12),
            TextFormField(controller: _new2, obscureText: true, decoration: InputDecoration(labelText: context.t('auth.confirmPassword')),
                validator: (v) => v != _new.text ? 'Passwords do not match' : null),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                if (await runAction(context, () => ref.read(authRepositoryProvider).changePassword(current: _cur.text, next: _new.text),
                    success: context.t('auth.passwordUpdated')) && context.mounted) {
                  context.pop();
                }
              },
              child: Text(context.t('common.save')),
            ),
          ]),
        ),
      );
}

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _msg = TextEditingController();
  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) { 'technical_issue' => context.t('settings.reportIssue'), 'support' => 'Contact us', _ => context.t('settings.feedback') };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: _msg, maxLines: 8, maxLength: 4000, decoration: InputDecoration(
          labelText: widget.kind == 'technical_issue' ? 'What happened? What did you expect?' : 'Your message',
          alignLabelWithHint: true,
        )),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            if (_msg.text.trim().length < 5) return showSnack(context, 'Please write a little more', error: true);
            if (await runAction(context, () => ref.read(contentRepositoryProvider).sendFeedback(widget.kind, _msg.text,
                appVersion: appVersion, platform: Platform.operatingSystem), success: 'Thank you — we received your message.') && context.mounted) {
              context.pop();
            }
          },
          child: const Text('Send'),
        ),
      ]),
    );
  }
}
