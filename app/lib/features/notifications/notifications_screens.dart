import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../widgets/common.dart';
import '../opportunity/engagement_actions.dart' show reminderOffsetOptions;

const _categories = {
  'deadlines': ['interested_deadline', 'saved_deadline', 'closing_soon', 'deadline_changed', 'opportunity_closed'],
  'matches': ['new_opportunity', 'matching_opportunity', 'eligibility_update'],
  'applications': ['application_reminder', 'interview_reminder', 'document_expiry'],
  'updates': ['verification_update', 'announcement', 'system'],
};

IconData _icon(String type) => switch (type) {
      'interested_deadline' || 'saved_deadline' => Icons.alarm_rounded,
      'closing_soon' => Icons.timer_rounded,
      'deadline_changed' => Icons.edit_calendar_rounded,
      'opportunity_closed' => Icons.lock_clock_rounded,
      'interview_reminder' => Icons.record_voice_over_rounded,
      'application_reminder' => Icons.assignment_turned_in_outlined,
      'verification_update' => Icons.verified_rounded,
      'document_expiry' => Icons.description_outlined,
      'matching_opportunity' || 'new_opportunity' => Icons.auto_awesome_rounded,
      _ => Icons.notifications_rounded,
    };

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String? _category;
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('notif.title')), actions: [
        IconButton(
          tooltip: context.t('notif.markAll'),
          icon: const Icon(Icons.done_all_rounded),
          onPressed: () async {
            if (await runAction(context, () => ref.read(notificationRepositoryProvider).markAllRead())) {
              ref.invalidate(notificationsProvider);
              ref.invalidate(homeSummaryProvider);
            }
          },
        ),
        IconButton(tooltip: context.t('notif.prefs'), icon: const Icon(Icons.tune_rounded), onPressed: () => context.push('/notifications/prefs')),
      ]),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            FilterChip(label: const Text('Unread'), selected: _unreadOnly, onSelected: (v) => setState(() => _unreadOnly = v)),
            const SizedBox(width: 8),
            for (final c in _categories.keys)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(label: Text(c[0].toUpperCase() + c.substring(1)), selected: _category == c,
                    onSelected: (v) => setState(() => _category = v ? c : null)),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: AsyncView<List<AppNotification>>(
              value: list,
              onRetry: () => ref.invalidate(notificationsProvider),
              data: (all) {
                final items = all.where((n) => (!_unreadOnly || !n.isRead) && (_category == null || _categories[_category]!.contains(n.type))).toList();
                if (items.isEmpty) return ListView(children: [EmptyState(message: context.t('notif.empty'), icon: Icons.notifications_off_outlined)]);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final n = items[i];
                    return Dismissible(
                      key: ValueKey(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(alignment: AlignmentDirectional.centerEnd, padding: const EdgeInsets.all(20), color: AppColors.coral,
                          child: const Icon(Icons.delete_outline, color: Colors.white)),
                      onDismissed: (_) => ref.read(notificationRepositoryProvider).delete(n.id).then((_) => ref.invalidate(notificationsProvider),
                          onError: (_) => ref.invalidate(notificationsProvider)),
                      child: Card(
                        color: n.isRead ? null : fade(AppColors.teal, 0.08),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: fade(AppColors.teal, 0.15), child: Icon(_icon(n.type), color: AppColors.teal)),
                          title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800)),
                          subtitle: Text('${n.body}\n${timeAgo(n.createdAt)}'),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: n.isRead ? 'Mark unread' : 'Mark read',
                            icon: Icon(n.isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
                            onPressed: () async {
                              await ref.read(notificationRepositoryProvider).markRead(n.id, read: !n.isRead);
                              ref.invalidate(notificationsProvider);
                              ref.invalidate(homeSummaryProvider);
                            },
                          ),
                          onTap: () async {
                            if (!n.isRead) {
                              ref.read(notificationRepositoryProvider).markRead(n.id).then((_) => ref.invalidate(notificationsProvider), onError: (_) {});
                            }
                            if (n.applicationId != null) {
                              context.push('/journey/${n.applicationId}');
                            } else if (n.opportunityId != null) {
                              context.push('/opportunity/${n.opportunityId}');
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class NotificationPrefsScreen extends ConsumerWidget {
  const NotificationPrefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    Future<void> set(Map<String, dynamic> patch) async {
      if (await runAction(context, () => ref.read(notificationRepositoryProvider).updatePrefs(patch))) ref.invalidate(notificationPrefsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t('notif.prefs'))),
      body: AsyncView<NotificationPrefs>(
        value: prefs,
        onRetry: () => ref.invalidate(notificationPrefsProvider),
        data: (p) {
          Widget sw(String key, String label, {String? subtitle}) =>
              SwitchListTile(value: p.flag(key), title: Text(label), subtitle: subtitle == null ? null : Text(subtitle), onChanged: (v) => set({key: v}));
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            const _Header('Channels'),
            sw('push_enabled', context.t('notif.push')),
            sw('email_enabled', context.t('notif.email')),
            sw('sms_enabled', context.t('notif.sms'), subtitle: 'Closing-soon and interview alerts only'),
            sw('whatsapp_enabled', context.t('notif.whatsapp'), subtitle: 'Closing-soon and interview alerts only'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: InfoBanner(text: context.t('notif.channelsNote'))),
            const _Header('What to notify me about'),
            sw('deadline_reminders', 'Deadline reminders'),
            sw('closing_soon', 'Closing soon'),
            sw('deadline_changes', 'Deadline changes'),
            sw('new_matches', 'New matching opportunities'),
            sw('eligibility_updates', 'Eligibility updates'),
            sw('application_reminders', 'Application & interview reminders'),
            sw('verification_updates', 'Verification updates'),
            sw('announcements', 'Announcements'),
            const _Header('Default reminder schedule (Saved items)'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, children: [
                for (final d in reminderOffsetOptions)
                  FilterChip(
                    label: Text(context.t('remind.$d')),
                    selected: p.defaultOffsets.contains(d),
                    onSelected: (v) {
                      final next = {...p.defaultOffsets};
                      v ? next.add(d) : next.remove(d);
                      set({'default_reminder_offsets': next.toList()..sort((a, b) => b - a)});
                    },
                  ),
              ]),
            ),
            ListTile(
              title: const Text('Reminder time (Pakistan time)'),
              trailing: DropdownButton<int>(
                value: p.reminderHour,
                items: [for (var h = 6; h <= 22; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                onChanged: (v) => set({'reminder_hour_local': v}),
              ),
            ),
            ListTile(
              title: const Text('Quiet hours'),
              subtitle: Text(p.quietStart == null ? 'Off' : '${p.quietStart}:00 – ${p.quietEnd}:00 PKT'),
              trailing: Switch(
                value: p.quietStart != null,
                onChanged: (v) => set(v ? {'quiet_hours_start': 22, 'quiet_hours_end': 7} : {'quiet_hours_start': null, 'quiet_hours_end': null}),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.teal)),
      );
}
