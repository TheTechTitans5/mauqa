import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n/strings.dart';
import '../core/theme/app_colors.dart';
import '../data/models/opportunity.dart';
import '../data/repositories/engagement_repository.dart';
import '../features/opportunity/engagement_actions.dart';
import 'common.dart';
import 'visuals.dart';

String deadlineLabel(BuildContext context, Opportunity o) {
  if (o.effectiveStatus == 'closed') return context.t('common.closed');
  if (o.effectiveStatus == 'upcoming') return context.t('common.opensSoon');
  final d = o.daysLeft;
  if (d == null) return context.t('common.noDeadline');
  if (d <= 0) return context.t('common.closesToday');
  return context.t('common.daysLeft', {'n': d});
}

Color deadlineColor(Opportunity o) {
  final d = o.daysLeft;
  if (o.isClosed) return Colors.grey;
  if (d != null && d <= 3) return AppColors.coral;
  if (d != null && d <= 7) return AppColors.amber;
  return AppColors.teal;
}

/// Full-width card used in lists.
class OpportunityCard extends ConsumerWidget {
  const OpportunityCard({super.key, required this.opportunity, this.reasons = const [], this.eligibility, this.index = 0, this.trailing});
  final Opportunity opportunity;
  final List<String> reasons;
  final String? eligibility;
  final int index;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = opportunity;
    final ur = context.isUrdu;
    final saved = ref.watch(savedIdsProvider).valueOrNull?.contains(o.id) ?? false;
    final interested = ref.watch(interestedIdsProvider).valueOrNull?.contains(o.id) ?? false;
    final color = AppColors.fromHex(o.categoryColor);
    final theme = Theme.of(context);
    return EntranceFade(
      index: index,
      child: TiltCard(
        child: Semantics(
          button: true,
          label: '${o.title}, ${o.organizationName}, ${deadlineLabel(context, o)}',
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            onTap: () => context.push('/opportunity/${o.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _CategoryBadge(color: color, icon: iconFor(o.categoryIcon)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.localizedTitle(ur), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Row(children: [
                      Flexible(child: Text(o.organizationName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
                      if (o.organizationVerified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, size: 14, color: AppColors.teal)),
                    ]),
                  ]),
                ),
                if (trailing != null) trailing!,
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(deadlineLabel(context, o), color: deadlineColor(o), icon: Icons.schedule_rounded),
                if (o.fundingLabel != null) Pill(o.fundingLabel!, color: AppColors.lavender, icon: Icons.payments_outlined),
                Pill(o.location, color: Colors.blueGrey, icon: Icons.place_outlined),
                VerificationBadge(status: o.verificationStatus, reported: o.isReported, demo: o.isDemo),
                if (eligibility != null) _EligibilityPill(eligibility!),
              ]),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final r in reasons)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.auto_awesome, size: 13, color: AppColors.amber),
                      const SizedBox(width: 3),
                      Text(r, style: theme.textTheme.labelSmall),
                    ]),
                ]),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Text(o.categoryName(ur), style: theme.textTheme.labelMedium?.copyWith(color: color)),
                const Spacer(),
                IconButton(
                  tooltip: context.t('opp.markInterested'),
                  onPressed: () => EngagementActions.toggleInterested(context, ref, o),
                  icon: Icon(interested ? Icons.star_rounded : Icons.star_outline_rounded, color: interested ? AppColors.amber : null),
                ),
                IconButton(
                  tooltip: context.t('opp.save'),
                  onPressed: () => EngagementActions.toggleSave(context, ref, o),
                  icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, color: saved ? AppColors.teal : null),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Compact floating card for horizontal carousels.
class OpportunityMiniCard extends StatelessWidget {
  const OpportunityMiniCard({super.key, required this.opportunity, this.width = 250});
  final Opportunity opportunity;
  final double width;
  @override
  Widget build(BuildContext context) {
    final o = opportunity;
    final color = AppColors.fromHex(o.categoryColor);
    return SizedBox(
      width: width,
      child: TiltCard(
        child: GlassCard(
          onTap: () => context.push('/opportunity/${o.id}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _CategoryBadge(color: color, icon: iconFor(o.categoryIcon), size: 38),
              const Spacer(),
              Pill(deadlineLabel(context, o), color: deadlineColor(o)),
            ]),
            const SizedBox(height: 12),
            Text(o.localizedTitle(context.isUrdu), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(o.organizationName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            VerificationBadge(status: o.verificationStatus, reported: o.isReported, demo: o.isDemo),
          ]),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.color, required this.icon, this.size = 46});
  final Color color;
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.32),
          gradient: LinearGradient(colors: [Color.lerp(color, Colors.white, 0.25)!, color], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: fade(color, 0.4), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      );
}

class _EligibilityPill extends StatelessWidget {
  const _EligibilityPill(this.outcome);
  final String outcome;
  @override
  Widget build(BuildContext context) => switch (outcome) {
        'eligible' => Pill(context.t('elig.eligible'), color: AppColors.success, icon: Icons.check_circle_rounded),
        'not_eligible' => Pill(context.t('elig.not'), color: AppColors.coral, icon: Icons.cancel_outlined),
        _ => Pill(context.t('elig.probably'), color: AppColors.warning, icon: Icons.help_outline_rounded),
      };
}
