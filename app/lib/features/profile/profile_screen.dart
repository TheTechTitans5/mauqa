import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart' show pushServiceProvider;
import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/local/offline_cache.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fp = ref.watch(fullProfileProvider);
    return Scaffold(
      body: AsyncView<FullProfile>(
        value: fp,
        onRetry: () => ref.invalidate(fullProfileProvider),
        data: (p) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(fullProfileProvider),
          child: ListView(padding: EdgeInsets.zero, children: [
            _Header(p: p),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Row(icon: Icons.badge_outlined, label: context.t('profile.category'), value: p.profile.userCategory == null ? '—' : pretty(p.profile.userCategory!)),
                  _Row(icon: Icons.place_outlined, label: context.t('profile.city'), value: [p.profile.city, p.profile.province].whereType<String>().join(', ')),
                  _Row(icon: Icons.school_outlined, label: context.t('profile.education'),
                      value: p.education.isEmpty ? '—' : '${pretty(p.education.first.level)} · ${p.education.first.institutionName ?? ''} ${p.education.first.scoreLabel}'),
                  _Row(icon: Icons.psychology_outlined, label: context.t('profile.skills'), value: p.skills.isEmpty ? '—' : p.skills.map((s) => s.name).join(', ')),
                  _Row(icon: Icons.interests_outlined, label: context.t('profile.interests'), value: p.interests.isEmpty ? '—' : p.interests.map((s) => s.name).join(', ')),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            _Menu(items: [
              (Icons.edit_rounded, context.t('profile.edit'), '/profile/edit'),
              (Icons.folder_shared_rounded, context.t('profile.documents'), '/documents'),
              (Icons.calendar_month_rounded, context.t('profile.calendar'), '/calendar'),
              (Icons.notifications_rounded, context.t('notif.title'), '/notifications'),
              (Icons.compare_arrows_rounded, context.t('profile.compare'), '/compare'),
              (Icons.handyman_rounded, context.t('profile.tools'), '/tools'),
              (Icons.groups_rounded, context.t('profile.community'), '/community'),
              (Icons.settings_rounded, context.t('profile.settings'), '/settings'),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.coral),
                icon: const Icon(Icons.logout_rounded),
                label: Text(context.t('profile.logout')),
                onPressed: () async {
                  await ref.read(pushServiceProvider).unregister();
                  await ref.read(offlineCacheProvider).clearUser(p.profile.id);
                  if (context.mounted) await runAction(context, () => ref.read(authRepositoryProvider).signOut());
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.p});
  final FullProfile p;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(avatarUrlProvider(p.profile.avatarPath)).valueOrNull;
    final top = MediaQuery.of(context).padding.top;
    return AnimatedGradientBackground(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 20, 20, 24),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            ProgressRing(value: p.completion / 100, size: 96, stroke: 6, label: ''),
            CircleAvatar(
              radius: 38,
              backgroundColor: AppColors.teal,
              backgroundImage: url == null ? null : NetworkImage(url),
              child: url == null ? Text(((p.profile.fullName ?? '').trim().isEmpty ? '?' : p.profile.fullName!.trim()).characters.first.toUpperCase(), style: const TextStyle(fontSize: 28, color: Colors.white)) : null,
            ),
          ]),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.profile.fullName ?? '—', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              Text(p.profile.email ?? p.profile.phone ?? '', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Pill(context.t('profile.completion', {'n': p.completion}), color: AppColors.amber),
            ]),
          ),
          IconButton.filledTonal(onPressed: () => context.push('/profile/edit'), icon: const Icon(Icons.edit_rounded), tooltip: context.t('profile.edit')),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.teal),
          const SizedBox(width: 12),
          SizedBox(width: 96, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ]),
      );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.items});
  final List<(IconData, String, String)> items;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final i in items)
              ListTile(leading: Icon(i.$1, color: AppColors.teal), title: Text(i.$2), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.push(i.$3)),
          ]),
        ),
      );
}
