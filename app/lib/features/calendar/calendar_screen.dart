import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../data/repositories/journey_repository.dart';
import '../../widgets/common.dart';
import '../opportunity/opportunity_detail_screen.dart' show pickPktDateTime;
import 'ics.dart';

/// Events for a 6-week window around a month (UTC range), so week/month views share one fetch.
final _eventsProvider = FutureProvider.autoDispose.family<List<CalendarEvent>, DateTime>((ref, month) {
  final from = DateTime.utc(month.year, month.month, 1).subtract(const Duration(days: 7));
  final to = DateTime.utc(month.year, month.month + 1, 1).add(const Duration(days: 14));
  return ref.watch(journeyRepositoryProvider).calendar(from, to);
});

const _typeColors = {
  'interested_deadline': AppColors.amber,
  'saved_deadline': AppColors.teal,
  'application_deadline': AppColors.coral,
  'interview': AppColors.lavender,
  'follow_up': Colors.blueGrey,
  'custom_reminder': AppColors.success,
};
const _typeLabels = {
  'interested_deadline': 'Interested · deadline',
  'saved_deadline': 'Saved · deadline',
  'application_deadline': 'Application deadline',
  'interview': 'Interview',
  'follow_up': 'Follow-up',
  'custom_reminder': 'Reminder',
};

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  // All calendar dates are Pakistan dates.
  DateTime _focused = Pkt.nowPkt();
  DateTime _selected = Pkt.nowPkt();
  CalendarFormat _format = CalendarFormat.month;
  bool _dayView = false;

  DateTime get _monthKey => DateTime.utc(_focused.year, _focused.month);

  List<CalendarEvent> _forDay(List<CalendarEvent> all, DateTime day) =>
      all.where((e) => isSameDay(Pkt.toPkt(e.at), day)).toList()..sort((a, b) => a.at.compareTo(b.at));

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(_eventsProvider(_monthKey));
    final all = events.valueOrNull ?? const <CalendarEvent>[];
    final dayEvents = _forDay(all, _selected);

    return Scaffold(
      appBar: AppBar(title: Text(context.t('cal.title')), actions: [
        IconButton(
          tooltip: 'Export to my calendar (.ics)',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () async {
            final now = DateTime.now().toUtc();
            List<CalendarEvent> events = const [];
            if (!await runAction(context, () async => events = await ref.read(journeyRepositoryProvider).calendar(now, now.add(const Duration(days: 365))))) return;
            final bytes = Uint8List.fromList(utf8.encode(buildIcs(events)));
            await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'text/calendar', name: 'mauqa-deadlines.ics')], subject: 'Mauqa deadlines');
          },
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'month', label: Text(context.t('cal.month'))),
            ButtonSegment(value: 'week', label: Text(context.t('cal.week'))),
            ButtonSegment(value: 'day', label: Text(context.t('cal.day'))),
          ],
          selected: {_dayView ? 'day' : _format == CalendarFormat.week ? 'week' : 'month'},
          onSelectionChanged: (v) => setState(() {
            _dayView = v.first == 'day';
            _format = v.first == 'month' ? CalendarFormat.month : CalendarFormat.week;
          }),
        ),
        const SizedBox(width: 8),
      ]),
      floatingActionButton: FloatingActionButton(
        tooltip: context.t('remind.custom'),
        onPressed: () async {
          final title = await _askTitle(context);
          if (title == null || !context.mounted) return;
          final when = await pickPktDateTime(context);
          if (when == null || !context.mounted) return;
          if (await runAction(context, () => ref.read(engagementRepositoryProvider).addCustomReminder(title: title, atUtc: when), success: context.t('remind.saved'))) {
            ref.invalidate(_eventsProvider);
          }
        },
        child: const Icon(Icons.add_alarm_rounded),
      ),
      body: Column(children: [
        if (!_dayView)
          TableCalendar<CalendarEvent>(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2035),
            focusedDay: _focused,
            calendarFormat: _format,
            availableCalendarFormats: const {CalendarFormat.month: 'Month', CalendarFormat.week: 'Week'},
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            eventLoader: (d) => _forDay(all, d),
            onDaySelected: (sel, foc) => setState(() { _selected = sel; _focused = foc; }),
            onPageChanged: (foc) => setState(() => _focused = foc),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(color: fade(AppColors.teal, 0.35), shape: BoxShape.circle),
              selectedDecoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, list) => list.isEmpty
                  ? null
                  : Positioned(
                      bottom: 4,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final e in list.take(3))
                          Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(color: _typeColors[e.type] ?? AppColors.teal, shape: BoxShape.circle)),
                      ]),
                    ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              IconButton(onPressed: () => setState(() { _selected = _selected.subtract(const Duration(days: 1)); _focused = _selected; }), icon: const Icon(Icons.chevron_left)),
              Expanded(child: Text(Pkt.date(_selected.subtract(Pkt.offset)), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(onPressed: () => setState(() { _selected = _selected.add(const Duration(days: 1)); _focused = _selected; }), icon: const Icon(Icons.chevron_right)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 10, runSpacing: 4, children: [
            for (final e in _typeLabels.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _typeColors[e.key], shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(e.value, style: Theme.of(context).textTheme.labelSmall),
              ]),
          ]),
        ),
        const Divider(),
        Expanded(
          child: events.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_eventsProvider(_monthKey))),
            data: (_) => dayEvents.isEmpty
                ? Center(child: Text(context.t('cal.empty')))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: dayEvents.length,
                    itemBuilder: (_, i) {
                      final e = dayEvents[i];
                      final color = _typeColors[e.type] ?? AppColors.teal;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: fade(color, 0.2), child: Icon(Icons.event_note_rounded, color: color)),
                          title: Text(e.title),
                          subtitle: Text('${_typeLabels[e.type] ?? e.type} · ${Pkt.dateTime(e.at)}'),
                          onTap: e.applicationId != null
                              ? () => context.push('/journey/${e.applicationId}')
                              : e.opportunityId != null
                                  ? () => context.push('/opportunity/${e.opportunityId}')
                                  : null,
                          trailing: e.reminderId == null
                              ? null
                              : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                                  if (await runAction(context, () => ref.read(engagementRepositoryProvider).deleteCustomReminder(e.reminderId!))) {
                                    ref.invalidate(_eventsProvider);
                                  }
                                }),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

Future<String?> _askTitle(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(context.t('remind.custom')),
      content: TextField(controller: c, autofocus: true, maxLength: 140, decoration: const InputDecoration(hintText: 'e.g. Get documents attested')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(context.t('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim().isEmpty ? null : c.text.trim()), child: Text(context.t('common.continue'))),
      ],
    ),
  ).whenComplete(c.dispose);
}
