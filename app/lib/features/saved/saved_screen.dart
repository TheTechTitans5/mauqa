import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/activity.dart';
import '../../data/models/opportunity.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../data/supabase_client.dart';
import '../../widgets/common.dart';
import '../../widgets/opportunity_card.dart';
import '../opportunity/engagement_actions.dart';

class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.initialTab});
  final String? initialTab;
  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab == 'interested' ? 1 : 0);
  String _q = '';
  String? _category;
  bool _hideClosed = false;

  @override
  void didUpdateWidget(covariant SavedScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialTab != old.initialTab) _tabs.index = widget.initialTab == 'interested' ? 1 : 0;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool _match(Opportunity o) =>
      (_q.isEmpty || '${o.title} ${o.organizationName}'.toLowerCase().contains(_q.toLowerCase())) &&
      (_category == null || o.categorySlug == _category) &&
      (!_hideClosed || !o.isClosed);

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedListProvider);
    final interested = ref.watch(interestedListProvider);
    final interestedCount = interested.valueOrNull?.length;
    final savedCount = saved.valueOrNull?.length;
    final allOpps = [...?saved.valueOrNull?.map((e) => e.opportunity), ...?interested.valueOrNull?.map((e) => e.opportunity)];
    final cats = {for (final o in allOpps) o.categorySlug: o.categoryName(context.isUrdu)};

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('saved.title')),
        actions: [
          IconButton(tooltip: context.t('compare.title'), icon: const Icon(Icons.compare_arrows_rounded), onPressed: () => context.push('/compare')),
          IconButton(tooltip: context.t('cal.title'), icon: const Icon(Icons.calendar_month_rounded), onPressed: () => context.push('/calendar')),
        ],
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: '${context.t('saved.saved')}${savedCount == null ? '' : ' ($savedCount)'}'),
          Tab(text: '${context.t('saved.interested')}${interestedCount == null ? '' : ' ($interestedCount)'}'),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: TextField(
            decoration: InputDecoration(hintText: context.t('saved.filterHint'), prefixIcon: const Icon(Icons.filter_list_rounded)),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            FilterChip(label: Text(context.t('common.closed')), selected: !_hideClosed, onSelected: (v) => setState(() => _hideClosed = !v)),
            const SizedBox(width: 8),
            for (final e in cats.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(e.value), selected: _category == e.key, onSelected: (v) => setState(() => _category = v ? e.key : null)),
              ),
          ]),
        ),
        if ((saved.error ?? interested.error) == null && (ref.watch(savedIdsProvider).error is AppException &&
            (ref.watch(savedIdsProvider).error as AppException).isOffline))
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: InfoBanner(text: context.t('common.offline'), icon: Icons.wifi_off_rounded)),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(savedListProvider),
              child: AsyncView<List<SavedEntry>>(
                value: saved,
                onRetry: () => ref.invalidate(savedListProvider),
                data: (list) {
                  final items = list.where((e) => _match(e.opportunity)).toList();
                  if (items.isEmpty) return ListView(children: [EmptyState(message: context.t('saved.emptySaved'), icon: Icons.bookmark_add_rounded)]);
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => OpportunityCard(
                      opportunity: items[i].opportunity,
                      index: i,
                      trailing: IconButton(
                        tooltip: context.t('saved.reminders'),
                        icon: Icon(items[i].remindersEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                            color: items[i].remindersEnabled ? AppColors.teal : null),
                        onPressed: () async {
                          if (await runAction(context, () => ref.read(engagementRepositoryProvider)
                              .setSavedReminders(items[i].opportunity.id, !items[i].remindersEnabled), success: context.t('remind.saved'))) {
                            ref.invalidate(savedListProvider);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(interestedListProvider),
              child: AsyncView<List<InterestedEntry>>(
                value: interested,
                onRetry: () => ref.invalidate(interestedListProvider),
                data: (list) {
                  final items = list.where((e) => _match(e.opportunity)).toList()
                    ..sort((a, b) => (a.opportunity.deadline ?? DateTime(9999)).compareTo(b.opportunity.deadline ?? DateTime(9999)));
                  if (items.isEmpty) return ListView(children: [EmptyState(message: context.t('saved.emptyInterested'), icon: Icons.star_border_rounded)]);
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _InterestedTile(entry: items[i], index: i),
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InterestedTile extends ConsumerWidget {
  const _InterestedTile({required this.entry, required this.index});
  final InterestedEntry entry;
  final int index;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = entry.opportunity;
    final offsets = [...entry.offsets]..sort((a, b) => b - a);
    return Column(children: [
      OpportunityCard(opportunity: o, index: index),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(children: [
          Icon(entry.remindersEnabled && !o.isClosed ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
              size: 18, color: entry.remindersEnabled && !o.isClosed ? AppColors.teal : Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              o.isClosed
                  ? 'Closed — reminders stopped'
                  : !entry.remindersEnabled || offsets.isEmpty
                      ? 'Reminders off'
                      : offsets.map((d) => context.t('remind.$d')).join(' · '),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          if (!o.isClosed)
            TextButton(
              onPressed: () async {
                final choice = await showReminderSheet(context, initialEnabled: entry.remindersEnabled, initialOffsets: entry.offsets);
                if (choice == null || !context.mounted) return;
                if (await runAction(context, () => ref.read(engagementRepositoryProvider)
                    .updateReminders(o.id, enabled: choice.enabled, offsets: choice.offsets), success: context.t('remind.saved'))) {
                  ref.invalidate(interestedListProvider);
                }
              },
              child: Text(context.t('remind.title')),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final repo = ref.read(engagementRepositoryProvider);
              if (v == 'move' && await runAction(context, () => repo.moveInterestedToSaved(o.id), success: context.t('common.saved'))) {
                ref.invalidate(interestedIdsProvider);
                ref.invalidate(savedIdsProvider);
                ref.invalidate(homeSummaryProvider);
              }
              if (v == 'remove' && context.mounted && await runAction(context, () => repo.removeInterested(o.id), success: context.t('common.removed'))) {
                ref.invalidate(interestedIdsProvider);
                ref.invalidate(homeSummaryProvider);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'move', child: Text(context.t('saved.moveToSaved'))),
              PopupMenuItem(value: 'remove', child: Text(context.t('saved.remove'))),
            ],
          ),
        ]),
      ),
    ]);
  }
}
