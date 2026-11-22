import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/opportunity.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../widgets/common.dart';

final _compareDetailsProvider = FutureProvider.autoDispose.family<List<OpportunityDetail>, String>((ref, joinedIds) async {
  final ids = joinedIds.split(',').where((s) => s.isNotEmpty).toList();
  final repo = ref.watch(opportunityRepositoryProvider);
  return Future.wait(ids.map(repo.detail));
});
final _savedComparisonsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(engagementRepositoryProvider).savedComparisons());
final _eligibilityOutcomesProvider = FutureProvider.autoDispose.family<Map<String, String>, String>(
    (ref, joined) => ref.watch(opportunityRepositoryProvider).storedOutcomes(joined.split(',').where((s) => s.isNotEmpty).toList()));

class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(compareTrayProvider);
    final joined = ids.join(',');
    final details = ref.watch(_compareDetailsProvider(joined));
    final outcomes = ref.watch(_eligibilityOutcomesProvider(joined)).valueOrNull ?? const {};
    final saved = ref.watch(_savedComparisonsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(context.t('compare.title')), actions: [
        if (ids.length >= 2)
          IconButton(
            tooltip: context.t('compare.save'),
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              final name = await _askName(context);
              if (name == null || !context.mounted) return;
              if (await runAction(context, () => ref.read(engagementRepositoryProvider).saveComparison(name, ids), success: context.t('common.saved'))) {
                ref.invalidate(_savedComparisonsProvider);
              }
            },
          ),
        if (ids.isNotEmpty)
          IconButton(tooltip: context.t('compare.clear'), icon: const Icon(Icons.clear_all_rounded), onPressed: () => ref.read(compareTrayProvider.notifier).clear()),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (ids.length < 2)
          EmptyState(message: context.t('compare.empty'), icon: Icons.compare_arrows_rounded, action: () => context.go('/explore'), actionLabel: context.t('nav.explore'))
        else
          details.when(
            loading: () => const LoadingList(count: 2),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_compareDetailsProvider(joined))),
            data: (list) => _Table(items: list, outcomes: outcomes),
          ),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Saved comparisons', style: Theme.of(context).textTheme.titleMedium),
          for (final c in saved)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(c['name'] as String),
              subtitle: Text('${(c['opportunity_ids'] as List).length} opportunities'),
              onTap: () => ref.read(compareTrayProvider.notifier).setAll((c['opportunity_ids'] as List).map((e) => e.toString()).toList()),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                if (await runAction(context, () => ref.read(engagementRepositoryProvider).deleteComparison(c['id'] as String))) {
                  ref.invalidate(_savedComparisonsProvider);
                }
              }),
            ),
        ],
      ]),
    );
  }
}

class _Table extends ConsumerWidget {
  const _Table({required this.items, required this.outcomes});
  final List<OpportunityDetail> items;
  final Map<String, String> outcomes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String elig(OpportunityDetail d) => switch (outcomes[d.base.id]) {
          'eligible' => '✓ ${context.t('elig.eligible')}',
          'not_eligible' => '✗ ${context.t('elig.not')}',
          'probably_eligible' => '? ${context.t('elig.probably')}',
          _ => d.eligibilitySummary ?? 'Run eligibility check',
        };
    final rows = <(String, String Function(OpportunityDetail))>[
      (context.t('journey.org'), (d) => d.base.organizationName),
      (context.t('opp.eligibility'), elig),
      (context.t('opp.benefits'), (d) => d.benefits ?? '—'),
      (context.t('opp.funding'), (d) => d.base.fundingLabel ?? '—'),
      ('Salary / stipend', (d) => d.base.amountMinPkr == null ? (d.base.amountText ?? '—')
          : '${formatPkr(d.base.amountMinPkr)}${d.base.amountMaxPkr != null ? ' – ${formatPkr(d.base.amountMaxPkr)}' : ''}'),
      (context.t('opp.deadline'), (d) => d.base.deadline == null ? '—' : Pkt.dateTime(d.base.deadline)),
      (context.t('opp.documents'), (d) => d.documents.isEmpty ? '—' : d.documents.map((x) => x.label).join(', ')),
      (context.t('opp.location'), (d) => d.base.location),
      (context.t('opp.duration'), (d) => d.base.durationText ?? '—'),
      (context.t('opp.procedure'), (d) => d.applicationProcedure ?? '—'),
      ('Verification', (d) => d.base.isDemo ? 'DEMO' : d.base.verificationStatus.replaceAll('_', ' ')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        dataRowMaxHeight: 120,
        headingRowHeight: 84,
        columns: [
          const DataColumn(label: Text('')),
          for (final d in items)
            DataColumn(
              label: SizedBox(
                width: 180,
                child: Row(children: [
                  Expanded(child: InkWell(
                    onTap: () => context.push('/opportunity/${d.base.id}'),
                    child: Text(d.base.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.teal)),
                  )),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => ref.read(compareTrayProvider.notifier).toggle(d.base.id)),
                ]),
              ),
            ),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              DataCell(SizedBox(width: 90, child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w600)))),
              for (final d in items) DataCell(SizedBox(width: 180, child: Text(r.$2(d), maxLines: 5, overflow: TextOverflow.ellipsis))),
            ]),
        ],
      ),
    );
  }
}

Future<String?> _askName(BuildContext context) {
  final c = TextEditingController(text: 'My comparison');
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(context.t('compare.save')),
      content: TextField(controller: c, autofocus: true, maxLength: 60),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(context.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()), child: Text(context.t('common.save'))),
      ],
    ),
  ).whenComplete(c.dispose);
}
