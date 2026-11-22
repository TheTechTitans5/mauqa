import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../supabase_client.dart';

/// Application tracker ("My Journey") and the calendar.
class JourneyRepository {
  JourneyRepository(this._c);
  final SupabaseClient _c;
  static const _select = '*, opportunities(title, deadline, official_application_url, organizations(name))';

  Future<List<Application>> list() => guard(() async {
        final rows = await _c.from('applications').select(_select).eq('user_id', requireUserId(_c)).order('updated_at', ascending: false);
        return rows.map(Application.fromJson).toList();
      });

  Future<Application?> byOpportunity(String opportunityId) => guard(() async {
        final row = await _c.from('applications').select(_select).eq('user_id', requireUserId(_c)).eq('opportunity_id', opportunityId).maybeSingle();
        return row == null ? null : Application.fromJson(row);
      });

  Future<Application> get(String id) => guard(() async => Application.fromJson(await _c.from('applications').select(_select).eq('id', id).single()));

  Future<List<StatusChange>> history(String applicationId) => guard(() async {
        final rows = await _c.from('application_status_history').select().eq('application_id', applicationId).order('changed_at');
        return rows.map(StatusChange.fromJson).toList();
      });

  /// Creates a tracker entry. The status is whatever the user chose — nothing is assumed from opening a link.
  Future<String> create({String? opportunityId, String? customTitle, String? customOrganization, String? customUrl,
      String status = 'planning', DateTime? deadline, String? notes}) =>
      guard(() async {
        if (!applicationStatuses.contains(status)) throw AppException('Invalid status');
        final row = await _c.from('applications').insert({
          'user_id': requireUserId(_c),
          'opportunity_id': opportunityId,
          'custom_title': customTitle,
          'custom_organization': customOrganization,
          'custom_url': customUrl,
          'status': status,
          'deadline': deadline?.toUtc().toIso8601String(),
          'notes': notes,
        }).select('id').single();
        return row['id'] as String;
      });

  /// Records the user's confirmation that they applied (creates or updates the entry).
  Future<void> confirmApplied(String opportunityId) => guard(() async {
        final existing = await byOpportunity(opportunityId);
        if (existing == null) {
          await create(opportunityId: opportunityId, status: 'applied');
        } else if (existing.stage < applicationStatuses.indexOf('applied')) {
          await update(existing.id, {'status': 'applied'});
        }
      });

  Future<void> update(String id, Map<String, dynamic> patch) => guard(() async {
        const allowed = {'status', 'custom_title', 'custom_organization', 'custom_url', 'applied_on', 'deadline', 'interview_at',
          'follow_up_at', 'external_reference', 'notes'};
        final clean = Map<String, dynamic>.from(patch)..removeWhere((k, _) => !allowed.contains(k));
        if (clean.containsKey('status') && !applicationStatuses.contains(clean['status'])) throw AppException('Invalid status');
        await _c.from('applications').update(clean).eq('id', id);
      });

  Future<void> delete(String id) => guard(() => _c.from('applications').delete().eq('id', id));

  Future<List<CalendarEvent>> calendar(DateTime fromUtc, DateTime toUtc) => guard(() async {
        final rows = await _c.rpc('my_calendar_events', params: {'p_from': fromUtc.toIso8601String(), 'p_to': toUtc.toIso8601String()});
        return (rows as List).map((e) => CalendarEvent.fromJson((e as Map).cast<String, dynamic>())).toList();
      });
}

final journeyRepositoryProvider = Provider<JourneyRepository>((ref) => JourneyRepository(ref.watch(supabaseProvider)));

final applicationsProvider = FutureProvider.autoDispose<List<Application>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(journeyRepositoryProvider).list();
});

final applicationProvider = FutureProvider.autoDispose.family<Application, String>((ref, id) => ref.watch(journeyRepositoryProvider).get(id));
final applicationHistoryProvider =
    FutureProvider.autoDispose.family<List<StatusChange>, String>((ref, id) => ref.watch(journeyRepositoryProvider).history(id));
