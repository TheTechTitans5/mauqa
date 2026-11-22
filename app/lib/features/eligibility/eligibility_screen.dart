import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class EligibilityScreen extends ConsumerWidget {
  const EligibilityScreen({super.key, required this.opportunityId});
  final String opportunityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(eligibilityProvider(opportunityId));
    final title = ref.watch(opportunityDetailProvider(opportunityId)).valueOrNull?.base.title;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('elig.title'))),
      body: AsyncView<EligibilityResult>(
        value: res,
        onRetry: () => ref.invalidate(eligibilityProvider(opportunityId)),
        loading: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Orb3D(size: 110, icon: Icons.fact_check_rounded), SizedBox(height: 16), CircularProgressIndicator(),
        ])),
        data: (r) => _Result(r: r, title: title, onRecheck: () async {
          await ref.read(opportunityRepositoryProvider).checkEligibility(opportunityId, force: true);
          ref.invalidate(eligibilityProvider(opportunityId));
        }),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.r, required this.title, required this.onRecheck});
  final EligibilityResult r;
  final String? title;
  final Future<void> Function() onRecheck;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (r.outcome) {
      'eligible' => (AppColors.success, Icons.verified_rounded, context.t('elig.eligible')),
      'not_eligible' => (AppColors.coral, Icons.do_not_disturb_on_rounded, context.t('elig.not')),
      _ => (AppColors.warning, Icons.help_rounded, context.t('elig.probably')),
    };
    return ListView(padding: const EdgeInsets.all(20), children: [
      Semantics(
        liveRegion: true,
        label: label,
        child: GlassCard(
          child: Column(children: [
            Orb3D(size: 110, colors: [color, Color.lerp(color, AppColors.navy, 0.4)!], icon: icon),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
            if (title != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(title!, textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            Text(r.explanation, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (r.matched.isNotEmpty || r.failed.isNotEmpty) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: r.score, minHeight: 10, color: color, backgroundColor: fade(color, 0.15)),
              ),
              const SizedBox(height: 4),
              Text('${(r.score * 100).round()}% of required criteria confirmed', style: Theme.of(context).textTheme.labelSmall),
            ],
          ]),
        ),
      ),
      if (r.failed.isNotEmpty) _Group(title: context.t('elig.failed'), items: r.failed, color: AppColors.coral, icon: Icons.cancel_rounded),
      if (r.unconfirmed.isNotEmpty) _Group(title: context.t('elig.unconfirmed'), items: r.unconfirmed, color: AppColors.warning, icon: Icons.help_outline_rounded),
      if (r.matched.isNotEmpty) _Group(title: context.t('elig.matched'), items: r.matched, color: AppColors.success, icon: Icons.check_circle_rounded),
      if (r.missing.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('elig.missing'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              for (final m in r.missing) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                const Icon(Icons.radio_button_unchecked, size: 16), const SizedBox(width: 8), Expanded(child: Text(m)),
              ])),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.tonal(onPressed: () => context.push('/profile/edit'), child: Text(context.t('elig.updateProfile'))),
                if (r.missing.any((m) => m.startsWith('Document')))
                  OutlinedButton(onPressed: () => context.push('/documents'), child: Text(context.t('docs.title'))),
              ]),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      InfoBanner(text: context.t('elig.disclaimer'), color: AppColors.lavender),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => runAction(context, onRecheck),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(context.t('elig.recheck')),
      ),
    ]);
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items, required this.color, required this.icon});
  final String title;
  final List<CriterionResult> items;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
            const SizedBox(height: 8),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.label + (i.mandatory ? '' : ' (recommended)'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(i.reason, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      );
}
