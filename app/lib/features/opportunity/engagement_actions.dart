import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../data/models/opportunity.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../widgets/common.dart';

class EngagementActions {
  static Future<void> toggleSave(BuildContext context, WidgetRef ref, Opportunity o) async {
    final saved = ref.read(savedIdsProvider).valueOrNull?.contains(o.id) ?? false;
    final repo = ref.read(engagementRepositoryProvider);
    final ok = await runAction(context, () => saved ? repo.unsave(o.id) : repo.save(o.id),
        success: saved ? context.t('common.removed') : context.t('common.saved'));
    if (ok) {
      ref.invalidate(savedIdsProvider);
      ref.invalidate(homeSummaryProvider);
    }
  }

  /// Marks Interested and immediately offers deadline reminders (default 7/3/1/0 days before).
  static Future<void> toggleInterested(BuildContext context, WidgetRef ref, Opportunity o) async {
    final interested = ref.read(interestedIdsProvider).valueOrNull?.contains(o.id) ?? false;
    final repo = ref.read(engagementRepositoryProvider);
    if (interested) {
      if (await runAction(context, () => repo.removeInterested(o.id), success: context.t('common.removed'))) {
        ref.invalidate(interestedIdsProvider);
        ref.invalidate(homeSummaryProvider);
      }
      return;
    }
    final ok = await runAction(context, () => repo.markInterested(o.id));
    if (!ok) return;
    ref.invalidate(interestedIdsProvider);
    ref.invalidate(homeSummaryProvider);
    if (!context.mounted || o.deadline == null || o.isClosed) return;
    final choice = await showReminderSheet(context, initialEnabled: true, initialOffsets: const [7, 3, 1, 0], offerMode: true);
    if (choice == null || !context.mounted) return;
    if (await runAction(context, () => repo.updateReminders(o.id, enabled: choice.enabled, offsets: choice.offsets),
        success: context.t('remind.saved'))) {
      ref.invalidate(interestedListProvider);
    }
  }

  static void toggleCompare(BuildContext context, WidgetRef ref, Opportunity o) {
    final tray = ref.read(compareTrayProvider.notifier);
    final had = ref.read(compareTrayProvider).contains(o.id);
    if (!tray.toggle(o.id)) {
      showSnack(context, context.t('compare.full'), error: true);
    } else {
      showSnack(context, had ? context.t('common.removed') : context.t('compare.added'));
    }
  }
}

class ReminderChoice {
  ReminderChoice(this.enabled, this.offsets);
  final bool enabled;
  final List<int> offsets;
}

const reminderOffsetOptions = [14, 7, 3, 1, 0];

Future<ReminderChoice?> showReminderSheet(BuildContext context,
    {required bool initialEnabled, required List<int> initialOffsets, bool offerMode = false}) {
  return showModalBottomSheet<ReminderChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _ReminderSheet(initialEnabled: initialEnabled, initialOffsets: initialOffsets, offerMode: offerMode),
  );
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({required this.initialEnabled, required this.initialOffsets, required this.offerMode});
  final bool initialEnabled;
  final List<int> initialOffsets;
  final bool offerMode;
  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late bool enabled = widget.initialEnabled;
  late final Set<int> offsets = widget.initialOffsets.toSet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.offerMode ? context.t('remind.offer') : context.t('saved.reminders'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: Text(context.t('remind.enable')),
            onChanged: (v) => setState(() => enabled = v),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in reminderOffsetOptions)
              FilterChip(
                label: Text(context.t('remind.$d')),
                selected: offsets.contains(d),
                onSelected: enabled ? (v) => setState(() => v ? offsets.add(d) : offsets.remove(d)) : null,
              ),
          ]),
          const SizedBox(height: 8),
          Text('Reminders are sent at 9:00 AM Pakistan time. If the deadline changes, they update automatically.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Row(children: [
            if (widget.offerMode)
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, ReminderChoice(false, offsets.toList())), child: Text(context.t('opp.notYet')))),
            if (widget.offerMode) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, ReminderChoice(enabled && offsets.isNotEmpty, (offsets.toList()..sort((a, b) => b - a)))),
                child: Text(context.t('common.save')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
