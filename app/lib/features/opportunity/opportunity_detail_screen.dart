import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/link_safety.dart';
import '../../core/utils/validators.dart';
import '../../data/models/content.dart';
import '../../data/models/opportunity.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../data/repositories/journey_repository.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/opportunity_card.dart';
import '../../widgets/visuals.dart';
import 'engagement_actions.dart';

final _forecastProvider = FutureProvider.autoDispose.family<Forecast?, String>((ref, key) => ref.watch(opportunityRepositoryProvider).forecast(key));
final _customRemindersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
    (ref, id) => ref.watch(engagementRepositoryProvider).customReminders(id));

class OpportunityDetailScreen extends ConsumerWidget {
  const OpportunityDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(opportunityDetailProvider(id));
    return Scaffold(
      body: detail.when(
        loading: () => const SafeArea(child: LoadingList(count: 5, height: 90)),
        error: (e, _) => SafeArea(child: Column(children: [
          Align(alignment: AlignmentDirectional.centerStart, child: BackButton(onPressed: () => context.pop())),
          Expanded(child: ErrorState(error: e, onRetry: () => ref.invalidate(opportunityDetailProvider(id)))),
        ])),
        data: (d) => _DetailBody(d: d),
      ),
      bottomNavigationBar: detail.valueOrNull == null ? null : _ApplyBar(d: detail.value!),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.d});
  final OpportunityDetail d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = d.base;
    final ur = context.isUrdu;
    final color = AppColors.fromHex(o.categoryColor);
    final saved = ref.watch(savedIdsProvider).valueOrNull?.contains(o.id) ?? false;
    final interested = ref.watch(interestedIdsProvider).valueOrNull?.contains(o.id) ?? false;
    final inCompare = ref.watch(compareTrayProvider).contains(o.id);
    final theme = Theme.of(context);

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: 230,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: context.t('opp.share'), icon: const Icon(Icons.share_outlined), onPressed: () => Share.share(
              '${o.title} — ${o.organizationName}\n${context.t('opp.deadline')}: ${Pkt.dateTime(o.deadline)}\n${o.officialApplicationUrl ?? o.sourceUrl ?? ''}\n\nvia Mauqa')),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'report') _showReport(context, ref, o.id);
              if (v == 'correct') _showCorrection(context, ref, o.id);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'report', child: ListTile(leading: const Icon(Icons.flag_outlined), title: Text(context.t('opp.report')))),
              PopupMenuItem(value: 'correct', child: ListTile(leading: const Icon(Icons.edit_note), title: Text(context.t('opp.suggestCorrection')))),
            ],
          ),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: AnimatedGradientBackground(
            colors: [AppColors.navy, Color.lerp(color, AppColors.navy, 0.35)!, color],
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                child: Stack(children: [
                  PositionedDirectional(end: 0, top: 0, child: Orb3D(size: 84, colors: [color, AppColors.lavender], icon: iconFor(o.categoryIcon))),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(o.categoryName(ur).toUpperCase(), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(o.localizedTitle(ur), maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Flexible(child: Text(o.organizationName, style: const TextStyle(color: Colors.white70))),
                      if (o.organizationVerified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16, color: AppColors.teal)),
                    ]),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        sliver: SliverList.list(children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            VerificationBadge(status: o.verificationStatus, reported: o.isReported, demo: o.isDemo),
            Pill(deadlineLabel(context, o), color: deadlineColor(o), icon: Icons.schedule_rounded),
          ]),
          const SizedBox(height: 8),
          if (o.isDemo) InfoBanner(text: context.t('opp.demo'), color: AppColors.lavender, icon: Icons.science_outlined),
          if (o.isReported) InfoBanner(text: context.t('opp.reportedBanner'), color: AppColors.coral, icon: Icons.flag_outlined),
          if (!o.isVerified && !o.isDemo) InfoBanner(text: context.t('opp.unverifiedBanner')),
          if (o.hasApplicationFee)
            InfoBanner(text: context.t('opp.feeWarning', {'fee': o.applicationFeePkr == null ? 'an amount' : formatPkr(o.applicationFeePkr)}),
                color: AppColors.coral, icon: Icons.warning_amber_rounded),
          const SizedBox(height: 8),
          _ActionRow(children: [
            _ActionButton(icon: interested ? Icons.star_rounded : Icons.star_outline_rounded, label: context.t('opp.interested'), active: interested,
                color: AppColors.amber, onTap: () => EngagementActions.toggleInterested(context, ref, o)),
            _ActionButton(icon: saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, label: context.t('opp.save'), active: saved,
                color: AppColors.teal, onTap: () => EngagementActions.toggleSave(context, ref, o)),
            _ActionButton(icon: Icons.fact_check_outlined, label: context.t('opp.check'), color: AppColors.lavender,
                onTap: () => context.push('/opportunity/${o.id}/eligibility')),
            _ActionButton(icon: inCompare ? Icons.compare_arrows_rounded : Icons.compare_arrows_outlined, label: context.t('opp.compare'), active: inCompare,
                color: AppColors.coral, onTap: () => EngagementActions.toggleCompare(context, ref, o)),
          ]),
          const SizedBox(height: 16),
          _KeyFacts(o: o),
          if (o.summary != null) ...[const SizedBox(height: 16), Text(o.summary!, style: theme.textTheme.bodyLarge)],
          _Section(title: context.t('opp.about'), body: d.description),
          _Section(title: context.t('opp.benefits'), body: d.benefits),
          _EligibilitySection(d: d),
          _DocumentsSection(d: d),
          _Section(title: context.t('opp.procedure'), body: d.applicationProcedure),
          _Section(title: context.t('opp.selection'), body: d.selectionProcedure),
          _Section(title: context.t('opp.instructions'), body: d.importantInstructions),
          if (interested) _CustomReminders(opportunityId: o.id, deadline: o.deadline),
          if (o.recurrenceKey != null) _ForecastCard(recurrenceKey: o.recurrenceKey!),
          _SourceCard(d: d),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/journey/new?opportunityId=${o.id}'),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text(context.t('journey.add')),
          ),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: () => context.push('/tools/readiness?opportunityId=${o.id}'), icon: const Icon(Icons.checklist_rounded),
              label: Text(context.t('tools.readiness'))),
        ]),
      ),
    ]);
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Row(children: [for (final c in children) Expanded(child: c)]);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap, required this.color, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool active;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: active ? color : fade(color, 0.14),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: active ? [BoxShadow(color: fade(color, 0.4), blurRadius: 12, offset: const Offset(0, 6))] : null,
                ),
                child: Icon(icon, color: active ? Colors.white : color),
              ),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        ),
      );
}

class _KeyFacts extends StatelessWidget {
  const _KeyFacts({required this.o});
  final Opportunity o;
  @override
  Widget build(BuildContext context) {
    final facts = <(IconData, String, String)>[
      (Icons.event_busy_rounded, context.t('opp.deadline'), o.deadline == null ? context.t('common.noDeadline') : Pkt.dateTime(o.deadline)),
      if (o.openingDate != null) (Icons.event_available_rounded, context.t('opp.opening'), Pkt.date(o.openingDate)),
      if (o.fundingLabel != null) (Icons.payments_outlined, context.t('opp.funding'), o.fundingLabel!),
      (Icons.place_outlined, context.t('opp.location'), o.location),
      if (o.durationText != null) (Icons.timelapse_rounded, context.t('opp.duration'), o.durationText!),
      if (o.minAge != null || o.maxAge != null) (Icons.cake_outlined, 'Age', '${o.minAge ?? '–'} to ${o.maxAge ?? '–'}'),
    ];
    return GlassCard(
      child: Column(children: [
        for (final f in facts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(f.$1, size: 20, color: AppColors.teal),
              const SizedBox(width: 12),
              SizedBox(width: 92, child: Text(f.$2, style: Theme.of(context).textTheme.labelMedium)),
              Expanded(child: Text(f.$3, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String? body;
  @override
  Widget build(BuildContext context) {
    if (body == null || body!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const Border(),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [SelectableText(body!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5))],
        ),
      ),
    );
  }
}

class _EligibilitySection extends StatelessWidget {
  const _EligibilitySection({required this.d});
  final OpportunityDetail d;
  @override
  Widget build(BuildContext context) {
    final criteria = d.rules.where((r) => r.nodeType == 'criterion').toList();
    final groups = {for (final r in d.rules.where((r) => r.nodeType == 'group')) r.id: r};
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('opp.eligibility'), style: Theme.of(context).textTheme.titleMedium),
          if (d.eligibilitySummary != null) ...[const SizedBox(height: 8), Text(d.eligibilitySummary!)],
          const SizedBox(height: 8),
          if (criteria.isEmpty)
            const Text('Detailed criteria have not been structured yet — please read the official announcement.')
          else
            for (final c in criteria)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(c.isMandatory ? Icons.check_circle_outline : Icons.info_outline, size: 18, color: c.isMandatory ? AppColors.teal : Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(child: Text([
                    c.label ?? pretty(c.criterionType ?? ''),
                    if (c.parentId != null && groups[c.parentId]?.groupOperator == 'or') '(any one of these)',
                    if (!c.isMandatory) '(recommended)',
                  ].join(' '))),
                ]),
              ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/opportunity/${d.base.id}/eligibility'),
            icon: const Icon(Icons.fact_check_rounded),
            label: Text(context.t('opp.check')),
          ),
        ]),
      ),
    );
  }
}

String pretty(String s) => s.replaceAll('_', ' ');

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.d});
  final OpportunityDetail d;
  @override
  Widget build(BuildContext context) {
    if (d.documents.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('opp.documents'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final doc in d.documents)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(doc.label),
              subtitle: doc.notes == null ? null : Text(doc.notes!),
              trailing: doc.isMandatory ? Text(context.t('common.required'), style: const TextStyle(color: AppColors.coral)) : Text(context.t('common.optional')),
            ),
          TextButton.icon(
            onPressed: () => context.push('/documents?opportunityId=${d.base.id}'),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Check against my document vault'),
          ),
        ]),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.d});
  final OpportunityDetail d;
  @override
  Widget build(BuildContext context) {
    final o = d.base;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('opp.source'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          VerificationBadge(status: o.verificationStatus, reported: o.isReported, demo: o.isDemo),
          const SizedBox(height: 8),
          if (o.lastCheckedAt != null) Text(context.t('opp.lastChecked', {'date': Pkt.date(o.lastCheckedAt)})),
          if (o.lastVerifiedAt != null) Text(context.t('opp.lastVerified', {'date': Pkt.date(o.lastVerifiedAt)})),
          if (o.sourceUrl != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_rounded),
              title: Text(Uri.tryParse(o.sourceUrl!)?.host ?? o.sourceUrl!),
              subtitle: const Text('Original announcement'),
              onTap: () => launchUrl(Uri.parse(o.sourceUrl!), mode: LaunchMode.externalApplication),
            ),
          const Divider(),
          Text(o.organizationName, style: Theme.of(context).textTheme.titleSmall),
          if (d.organizationDescription != null) Text(d.organizationDescription!, style: Theme.of(context).textTheme.bodySmall),
          if (o.organizationWebsite != null)
            TextButton.icon(onPressed: () => launchUrl(Uri.parse(o.organizationWebsite!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.public), label: Text(Uri.tryParse(o.organizationWebsite!)?.host ?? 'Website')),
          if (d.contactEmail != null)
            TextButton.icon(onPressed: () => launchUrl(Uri(scheme: 'mailto', path: d.contactEmail)), icon: const Icon(Icons.mail_outline), label: Text(d.contactEmail!)),
        ]),
      ),
    );
  }
}

class _ForecastCard extends ConsumerWidget {
  const _ForecastCard({required this.recurrenceKey});
  final String recurrenceKey;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(_forecastProvider(recurrenceKey)).valueOrNull;
    if (f == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: InfoBanner(
        color: AppColors.lavender,
        icon: Icons.insights_rounded,
        text: 'ESTIMATE, not an announcement: based on ${f.cycles} previous cycles, the next round may open around '
            '${Pkt.date(f.nextOpening)} with a deadline near ${Pkt.date(f.nextDeadline)}.',
      ),
    );
  }
}

class _CustomReminders extends ConsumerWidget {
  const _CustomReminders({required this.opportunityId, required this.deadline});
  final String opportunityId;
  final DateTime? deadline;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_customRemindersProvider(opportunityId)).valueOrNull ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(context.t('saved.reminders'), style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              tooltip: context.t('remind.custom'),
              icon: const Icon(Icons.add_alarm_rounded),
              onPressed: () async {
                final when = await pickPktDateTime(context, lastDate: deadline);
                if (when == null || !context.mounted) return;
                if (await runAction(context, () => ref.read(engagementRepositoryProvider)
                    .addCustomReminder(title: 'Reminder', atUtc: when, opportunityId: opportunityId), success: context.t('remind.saved'))) {
                  ref.invalidate(_customRemindersProvider(opportunityId));
                }
              },
            ),
          ]),
          const Text('Automatic reminders: 7, 3, 1 days before and on the deadline day (change in Saved → Interested).'),
          for (final r in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm_rounded),
              title: Text(Pkt.dateTime(parseTs(r['remind_at']))),
              subtitle: Text(r['status'] as String),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                if (await runAction(context, () => ref.read(engagementRepositoryProvider).deleteCustomReminder(r['id'] as String))) {
                  ref.invalidate(_customRemindersProvider(opportunityId));
                }
              }),
            ),
        ]),
      ),
    );
  }
}

/// Picks a date and time interpreted as Pakistan time; returns the UTC instant.
Future<DateTime?> pickPktDateTime(BuildContext context, {DateTime? lastDate}) async {
  final now = DateTime.now();
  final d = await showDatePicker(context: context, firstDate: now, lastDate: lastDate?.toLocal() ?? now.add(const Duration(days: 730)));
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0), helpText: 'Time (Pakistan time)');
  if (t == null) return null;
  final utc = Pkt.fromPktWallClock(d.year, d.month, d.day, t.hour, t.minute);
  return utc.isAfter(DateTime.now().toUtc()) ? utc : null;
}

class _ApplyBar extends ConsumerWidget {
  const _ApplyBar({required this.d});
  final OpportunityDetail d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = d.base;
    final url = o.officialApplicationUrl;
    final disabled = url == null || o.isClosed;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: disabled ? null : () => _apply(context, ref),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(url == null ? context.t('opp.noApplyLink') : o.isClosed ? context.t('common.closed') : context.t('opp.apply')),
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final o = d.base;
    final uri = Uri.parse(o.officialApplicationUrl!);
    final check = checkLink(o.officialApplicationUrl, officialDomains: d.officialDomains);
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.open_in_new_rounded),
        title: Text(context.t('opp.leaving')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.t('opp.leavingBody', {'host': uri.host, 'org': o.organizationName})),
          const SizedBox(height: 8),
          SelectableText(uri.toString(), style: Theme.of(context).textTheme.bodySmall),
          if (o.isDemo) InfoBanner(text: context.t('opp.demo'), color: AppColors.lavender),
          if (!check.ok) InfoBanner(text: '${context.t('opp.linkCaution')}: ${check.flags.join('; ')}', color: AppColors.coral, icon: Icons.warning_amber),
          if (o.hasApplicationFee) InfoBanner(text: context.t('opp.feeWarning', {'fee': formatPkr(o.applicationFeePkr)}), color: AppColors.coral),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.t('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(context.t('opp.open'))),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened || !context.mounted) {
      if (context.mounted) showSnack(context, 'Could not open the link', error: true);
      return;
    }
    // Opening the website does NOT mean the user applied. Ask, and only record on confirmation.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;
    final applied = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.t('opp.didApply')),
        content: Text(context.t('opp.didApplyBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.t('opp.notYet'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(context.t('opp.yesApplied'))),
        ],
      ),
    );
    if (applied == true && context.mounted) {
      if (await runAction(context, () => ref.read(journeyRepositoryProvider).confirmApplied(o.id), success: context.t('status.applied'))) {
        ref.invalidate(applicationsProvider);
      }
    }
  }
}

const _reportReasons = {
  'suspected_scam': 'Looks like a scam',
  'fee_requested': 'Asks for an application fee',
  'payment_request': 'Asks me to send money',
  'broken_link': 'Link is broken',
  'incorrect_information': 'Information is incorrect',
  'expired': 'Already closed / expired',
  'duplicate': 'Duplicate listing',
  'fake_organization': 'Organisation seems fake',
  'other': 'Something else',
};

Future<void> _showReport(BuildContext context, WidgetRef ref, String opportunityId) async {
  String reason = 'incorrect_information';
  final details = TextEditingController();
  final evidence = TextEditingController();
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Form(
          key: formKey,
          child: ListView(shrinkWrap: true, children: [
            Text(context.t('report.title'), style: Theme.of(c).textTheme.titleLarge),
            for (final e in _reportReasons.entries)
              RadioListTile<String>(value: e.key, groupValue: reason, title: Text(e.value), onChanged: (v) => set(() => reason = v!)),
            TextFormField(controller: details, maxLines: 3, maxLength: 2000, decoration: InputDecoration(labelText: context.t('report.details'))),
            TextFormField(controller: evidence, decoration: const InputDecoration(labelText: 'Link to evidence (optional)'),
                validator: (v) => Validators.httpsUrl(v)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final ok = await runAction(c, () => ref.read(engagementRepositoryProvider).report(
                    opportunityId: opportunityId, reason: reason, details: details.text.trim().isEmpty ? null : details.text.trim(),
                    evidenceUrl: evidence.text.trim().isEmpty ? null : evidence.text.trim()), success: context.t('report.sent'));
                if (ok && c.mounted) Navigator.pop(c);
              },
              child: Text(context.t('opp.report')),
            ),
          ]),
        ),
      ),
    ),
  );
  details.dispose();
  evidence.dispose();
}

Future<void> _showCorrection(BuildContext context, WidgetRef ref, String opportunityId) async {
  String field = 'deadline';
  final value = TextEditingController();
  final evidence = TextEditingController();
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Form(
          key: formKey,
          child: ListView(shrinkWrap: true, children: [
            Text(context.t('opp.suggestCorrection'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: field,
              decoration: const InputDecoration(labelText: 'What is wrong?'),
              items: const [
                DropdownMenuItem(value: 'deadline', child: Text('Deadline')),
                DropdownMenuItem(value: 'eligibility', child: Text('Eligibility')),
                DropdownMenuItem(value: 'official_application_url', child: Text('Application link')),
                DropdownMenuItem(value: 'amount', child: Text('Amount / stipend')),
                DropdownMenuItem(value: 'documents', child: Text('Required documents')),
                DropdownMenuItem(value: 'title', child: Text('Title')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => set(() => field = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: value, maxLines: 3, decoration: const InputDecoration(labelText: 'Correct information'),
                validator: (v) => Validators.required(v)),
            const SizedBox(height: 12),
            TextFormField(controller: evidence, decoration: const InputDecoration(labelText: 'Official source link (recommended)'),
                validator: (v) => Validators.httpsUrl(v)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final ok = await runAction(c, () => ref.read(engagementRepositoryProvider).suggestCorrection(
                    opportunityId: opportunityId, field: field, value: value.text.trim(),
                    evidenceUrl: evidence.text.trim().isEmpty ? null : evidence.text.trim()), success: context.t('report.sent'));
                if (ok && c.mounted) Navigator.pop(c);
              },
              child: Text(context.t('common.save')),
            ),
          ]),
        ),
      ),
    ),
  );
  value.dispose();
  evidence.dispose();
}
