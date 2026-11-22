import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../supabase_client.dart';

class NotificationRepository {
  NotificationRepository(this._c);
  final SupabaseClient _c;

  Future<List<AppNotification>> list({bool unreadOnly = false, String? type, int limit = 100}) => guard(() async {
        var q = _c.from('notifications').select('id, type, title, body, opportunity_id, application_id, is_read, created_at')
            .eq('user_id', requireUserId(_c));
        if (unreadOnly) q = q.eq('is_read', false);
        if (type != null) q = q.eq('type', type);
        final rows = await q.order('created_at', ascending: false).limit(limit);
        return rows.map(AppNotification.fromJson).toList();
      });

  Future<void> markRead(String id, {bool read = true}) => guard(() =>
      _c.from('notifications').update({'is_read': read, 'read_at': read ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', id));

  Future<void> markAllRead() => guard(() => _c.rpc('mark_all_notifications_read'));

  Future<void> delete(String id) => guard(() => _c.from('notifications').delete().eq('id', id));

  Future<NotificationPrefs> prefs() => guard(() async =>
      NotificationPrefs(await _c.from('notification_preferences').select().eq('user_id', requireUserId(_c)).single()));

  Future<void> updatePrefs(Map<String, dynamic> patch) => guard(() async {
        const allowed = {'push_enabled', 'email_enabled', 'sms_enabled', 'whatsapp_enabled', 'new_matches', 'deadline_reminders',
          'closing_soon', 'deadline_changes', 'eligibility_updates', 'application_reminders', 'verification_updates', 'announcements',
          'default_reminder_offsets', 'reminder_hour_local', 'quiet_hours_start', 'quiet_hours_end'};
        final clean = Map<String, dynamic>.from(patch)..removeWhere((k, _) => !allowed.contains(k));
        await _c.from('notification_preferences').update(clean).eq('user_id', requireUserId(_c));
      });

  Future<void> registerDevice(String token, String platform) => guard(() => _c.from('device_tokens').upsert(
      {'user_id': requireUserId(_c), 'token': token, 'platform': platform, 'last_seen_at': DateTime.now().toUtc().toIso8601String()},
      onConflict: 'token'));

  Future<void> unregisterDevice(String token) => guard(() => _c.from('device_tokens').delete().eq('token', token));
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(supabaseProvider)));
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(notificationRepositoryProvider).list();
});
final notificationPrefsProvider = FutureProvider.autoDispose<NotificationPrefs>((ref) => ref.watch(notificationRepositoryProvider).prefs());
