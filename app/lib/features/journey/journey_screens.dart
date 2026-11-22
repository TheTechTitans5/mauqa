import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/journey_repository.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';
import '../opportunity/opportunity_detail_screen.dart' show pickPktDateTime;

Color statusColor(String s) => switch (s) {
      'selected' => AppColors.success,
      'rejected' || 'withdrawn' => Colors.grey,
      'interview_scheduled' || 'shortlisted' => AppColors.amber,
      'applied' || 'under_review' => AppColors.teal,
      _ => AppColors.lavender,
    };

class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key});
  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final apps = ref.watch(applicationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('journey.title')), actions: [
        IconButton(tooltip: context.t('cal.title'), onPressed: () => context.push('/calendar'), icon: const Icon(Icons.calendar_month_rounded)),
      ]),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: () => context.push('/journey/new'),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.t('journey.add')),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(applicationsProvider),
        child: AsyncView<List<Application>>(
          value: apps,
          onRetry: () => ref.invalidate(applicationsProvider),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [EmptyState(message: context.t('journey.empty'), icon: Icons.route_rounded,
                  action: () => context.push('/journey/new'), actionLabel: context.t('journey.add'))]);
            }
            final counts = <String, int>{};
            for (final a in list) {
              counts[a.status] = (counts[a.status] ?? 0) + 1;
            }
            final shown = _status == null ? list : list.where((a) => a.status == _status).toList();
            final active = list.where((a) => !['selected', 'rejected', 'withdrawn'].contains(a.status)).length;
            final selected = counts['selected'] ?? 0;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 160), children: [
              GlassCard(
                child: Row(children: [
                  ProgressRing(value: list.isEmpty ? 0 : (list.length - active) / list.length, size: 70, label: '${list.length}'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$active in progress', style: Theme.of(context).textTheme.titleMedium),
                      Text('${counts['applied'] ?? 0} applied · ${counts['interview_scheduled'] ?? 0} interviews · $selected selected'),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  ChoiceChip(label: Text('All (${list.length})'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                  for (final s in applicationStatuses)
                    if ((counts[s] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: ChoiceChip(label: Text('${context.t('status.$s')} (${counts[s]})'), selected: _status == s,
                            onSelected: (v) => setState(() => _status = v ? s : null)),
                      ),
                ]),
              ),
              const SizedBox(height: 8),
              for (final (i, a) in shown.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: EntranceFade(index: i, child: _ApplicationTile(a: a)),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.a});
  final Application a;
  @override
  Widget build(BuildContext context) {
    final color = statusColor(a.status);
    final next = [a.interviewAt, a.followUpAt, a.deadline].whereType<DateTime>().where((d) => d.isAfter(DateTime.now().toUtc())).toList()..sort();
    return GlassCard(
      onTap: () => context.push('/journey/${a.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(a.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
          Pill(context.t('status.${a.status}'), color: color),
        ]),
        if (a.organization != null) Text(a.organization!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        _StageBar(stage: a.stage, color: color),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.event_rounded, size: 16), const SizedBox(width: 6), Text('Next: ${Pkt.dateTime(next.first)}')]),
        ],
      ]),
    );
  }
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.stage, required this.color});
  final int stage;
  final Color color;
  @override
  Widget build(BuildContext context) {
    // Positive path has 7 steps (interested → selected); rejected/withdrawn show as terminal grey.
    const steps = 7;
    final s = stage >= 8 ? steps : (stage + 1).clamp(1, steps);
    return Row(children: [
      for (var i = 0; i < steps; i++)
        Expanded(
          child: Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: i < s ? color : fade(color, 0.15), borderRadius: BorderRadius.circular(4)),
          ),
        ),
    ]);
  }
}

class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key, this.opportunityId});
  final String? opportunityId;
  @override
  ConsumerState<ApplicationFormScreen> createState() => _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _org = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  String _status = 'planning';
  DateTime? _deadline;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _org, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linked = widget.opportunityId == null ? null : ref.watch(opportunityDetailProvider(widget.opportunityId!)).valueOrNull?.base;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('journey.add'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (linked != null)
            GlassCard(child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link_rounded), title: Text(linked.title), subtitle: Text(linked.organizationName)))
          else ...[
            TextFormField(controller: _title, decoration: InputDecoration(labelText: context.t('journey.titleField')), validator: (v) => Validators.required(v)),
            const SizedBox(height: 12),
            TextFormField(controller: _org, decoration: InputDecoration(labelText: context.t('journey.org'))),
            const SizedBox(height: 12),
            TextFormField(controller: _url, decoration: const InputDecoration(labelText: 'Official link (optional)'), validator: (v) => Validators.httpsUrl(v)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_rounded),
              title: Text(context.t('opp.deadline')),
              subtitle: Text(_deadline == null ? '—' : Pkt.dateTime(_deadline)),
              onTap: () async {
                final d = await pickPktDateTime(context);
                if (d != null) setState(() => _deadline = d);
              },
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: InputDecoration(labelText: context.t('journey.status')),
            items: [for (final s in applicationStatuses) DropdownMenuItem(value: s, child: Text(context.t('status.$s')))],
            onChanged: (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _notes, maxLines: 4, decoration: InputDecoration(labelText: context.t('journey.notes'))),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () async {
              if (!_form.currentState!.validate()) return;
              setState(() => _busy = true);
              String? id;
              final ok = await runAction(context, () async {
                id = await ref.read(journeyRepositoryProvider).create(
                      opportunityId: widget.opportunityId,
                      customTitle: widget.opportunityId == null ? _title.text.trim() : null,
                      customOrganization: _org.text.trim().isEmpty ? null : _org.text.trim(),
                      customUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
                      status: _status,
                      deadline: _deadline,
                      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                    );
              }, success: context.t('common.saved'));
              if (!mounted) return;
              setState(() => _busy = false);
              if (ok && id != null) {
                ref.invalidate(applicationsProvider);
                ref.invalidate(homeSummaryProvider);
                context.pushReplacement('/journey/$id');
              }
            },
            child: Text(context.t('common.save')),
          ),
        ]),
      ),
    );
  }
}

class ApplicationDetailScreen extends ConsumerWidget {
  const ApplicationDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _patch(BuildContext context, WidgetRef ref, Map<String, dynamic> patch) async {
    if (await runAction(context, () => ref.read(journeyRepositoryProvider).update(id, patch), success: context.t('common.saved'))) {
      ref.invalidate(applicationProvider(id));
      ref.invalidate(applicationHistoryProvider(id));
      ref.invalidate(applicationsProvider);
      ref.invalidate(homeSummaryProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(applicationProvider(id));
    final history = ref.watch(applicationHistoryProvider(id)).valueOrNull ?? const <StatusChange>[];
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(
          tooltip: context.t('common.delete'),
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirmDialog(context, title: context.t('journey.deleteConfirm'), destructive: true, confirmLabel: context.t('common.delete'))) return;
            if (!context.mounted) return;
            if (await runAction(context, () => ref.read(journeyRepositoryProvider).delete(id))) {
              ref.invalidate(applicationsProvider);
              if (context.mounted) context.pop();
            }
          },
        ),
      ]),
      body: AsyncView<Application>(
        value: app,
        onRetry: () => ref.invalidate(applicationProvider(id)),
        data: (a) => ListView(padding: const EdgeInsets.all(20), children: [
          Text(a.displayTitle, style: Theme.of(context).textTheme.headlineSmall),
          if (a.organization != null) Text(a.organization!),
          const SizedBox(height: 12),
          _StageBar(stage: a.stage, color: statusColor(a.status)),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('journey.status'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in applicationStatuses)
                  ChoiceChip(
                    label: Text(context.t('status.$s')),
                    selected: a.status == s,
                    selectedColor: fade(statusColor(s), 0.25),
                    onSelected: (_) => a.status == s ? null : _patch(context, ref, {'status': s}),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _DateTile(icon: Icons.event_busy_rounded, label: context.t('opp.deadline'), value: a.deadline,
                  onPick: a.opportunityId != null ? null : (d) => _patch(context, ref, {'deadline': d?.toIso8601String()})),
              _DateTile(icon: Icons.record_voice_over_rounded, label: context.t('journey.interview'), value: a.interviewAt,
                  onPick: (d) => _patch(context, ref, {'interview_at': d?.toIso8601String(), if (d != null && a.stage < 6) 'status': 'interview_scheduled'})),
              _DateTile(icon: Icons.mark_email_unread_outlined, label: context.t('journey.followUp'), value: a.followUpAt,
                  onPick: (d) => _patch(context, ref, {'follow_up_at': d?.toIso8601String()})),
              ListTile(
                leading: const Icon(Icons.tag_rounded),
                title: Text(context.t('journey.reference')),
                subtitle: Text(a.externalReference ?? '—'),
                onTap: () async {
                  final v = await _prompt(context, context.t('journey.reference'), a.externalReference);
                  if (v != null && context.mounted) await _patch(context, ref, {'external_reference': v});
                },
              ),
              if (a.appliedOn != null) ListTile(leading: const Icon(Icons.send_rounded), title: Text(context.t('journey.appliedOn')), subtitle: Text(Pkt.date(a.appliedOn))),
            ]),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(context.t('journey.notes'), style: Theme.of(context).textTheme.titleMedium)),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () async {
                  final v = await _prompt(context, context.t('journey.notes'), a.notes, multiline: true);
                  if (v != null && context.mounted) await _patch(context, ref, {'notes': v});
                }),
              ]),
              Text(a.notes?.isNotEmpty == true ? a.notes! : '—'),
            ]),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.t('journey.timeline'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final h in history.reversed)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: statusColor(h.to), shape: BoxShape.circle)),
                    Container(width: 2, height: 30, color: fade(statusColor(h.to), 0.3)),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('status.${h.to}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(Pkt.dateTime(h.at), style: Theme.of(context).textTheme.labelSmall),
                  ])),
                ]),
            ]),
          ),
          const SizedBox(height: 12),
          if (a.opportunityId != null)
            OutlinedButton.icon(onPressed: () => context.push('/opportunity/${a.opportunityId}'), icon: const Icon(Icons.info_outline), label: const Text('View opportunity')),
          if (a.officialUrl != null)
            TextButton.icon(onPressed: () => launchUrl(Uri.parse(a.officialUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new), label: Text(Uri.tryParse(a.officialUrl!)?.host ?? 'Official website')),
        ]),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.icon, required this.label, required this.value, required this.onPick});
  final IconData icon;
  final String label;
  final DateTime? value;
  final void Function(DateTime?)? onPick;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value == null ? '—' : Pkt.dateTime(value)),
        trailing: onPick == null
            ? null
            : value == null
                ? const Icon(Icons.add_rounded)
                : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => onPick!(null)),
        onTap: onPick == null
            ? null
            : () async {
                final d = await pickPktDateTime(context);
                if (d != null) onPick!(d);
              },
      );
}

Future<String?> _prompt(BuildContext context, String title, String? initial, {bool multiline = false}) {
  final c = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: multiline ? 6 : 1, maxLength: multiline ? 5000 : 100),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(context.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(context.t('common.save'))),
      ],
    ),
  ).whenComplete(c.dispose);
}
