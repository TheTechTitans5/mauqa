import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/offline_cache.dart';
import '../models/activity.dart';
import '../models/opportunity.dart';
import '../supabase_client.dart';

/// Saved, Interested (with reminders), comparisons, reports and corrections.
class EngagementRepository {
  EngagementRepository(this._c, this._cache);
  final SupabaseClient _c;
  final OfflineCache _cache;

  Future<Set<String>> savedIds() => guard(() async {
        final rows = await _c.from('saved_opportunities').select('opportunity_id').eq('user_id', requireUserId(_c));
        return rows.map((r) => r['opportunity_id'] as String).toSet();
      });

  Future<Set<String>> interestedIds() => guard(() async {
        final rows = await _c.from('interested_opportunities').select('opportunity_id').eq('user_id', requireUserId(_c));
        return rows.map((r) => r['opportunity_id'] as String).toSet();
      });

  Future<List<SavedEntry>> saved() async {
    final uid = requireUserId(_c);
    try {
      final rows = await guard(() => _c.from('saved_opportunities').select('folder, reminders_enabled, opportunity_id, created_at')
          .eq('user_id', uid).order('created_at', ascending: false));
      final opps = await _feedByIds(rows.map((r) => r['opportunity_id'] as String).toList());
      final list = [
        for (final r in rows)
          if (opps[r['opportunity_id']] != null)
            SavedEntry(opportunity: opps[r['opportunity_id']]!, folder: r['folder'] as String?, remindersEnabled: r['reminders_enabled'] == true)
      ];
      await _cache.putOpportunities(uid, 'saved', list.map((e) => e.opportunity).toList());
      return list;
    } on AppException catch (e) {
      final cached = _cache.getOpportunities(uid, 'saved');
      if (e.isOffline && cached != null) {
        return cached.items.map((o) => SavedEntry(opportunity: o, remindersEnabled: false)).toList();
      }
      rethrow;
    }
  }

  Future<List<InterestedEntry>> interested() async {
    final uid = requireUserId(_c);
    try {
      final rows = await guard(() => _c.from('interested_opportunities').select('opportunity_id, reminders_enabled, reminder_offsets_days, note, created_at')
          .eq('user_id', uid).order('created_at', ascending: false));
      final opps = await _feedByIds(rows.map((r) => r['opportunity_id'] as String).toList());
      final list = [
        for (final r in rows)
          if (opps[r['opportunity_id']] != null)
            InterestedEntry(
              opportunity: opps[r['opportunity_id']]!,
              remindersEnabled: r['reminders_enabled'] == true,
              offsets: (r['reminder_offsets_days'] as List? ?? []).map((e) => (e as num).toInt()).toList(),
              note: r['note'] as String?,
            )
      ];
      await _cache.putOpportunities(uid, 'interested', list.map((e) => e.opportunity).toList());
      return list;
    } on AppException catch (e) {
      final cached = _cache.getOpportunities(uid, 'interested');
      if (e.isOffline && cached != null) {
        return cached.items.map((o) => InterestedEntry(opportunity: o, remindersEnabled: true, offsets: const [])).toList();
      }
      rethrow;
    }
  }

  Future<Map<String, Opportunity>> _feedByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    // Closed listings are intentionally included so users can see what happened to things they followed.
    final rows = await guard(() => _c.from('opportunity_feed').select().inFilter('id', ids));
    return {for (final r in rows) r['id'] as String: Opportunity.fromJson(r)};
  }

  Future<void> save(String opportunityId, {String? folder, bool reminders = false}) => guard(() => _c.from('saved_opportunities').upsert(
      {'user_id': requireUserId(_c), 'opportunity_id': opportunityId, 'folder': folder, 'reminders_enabled': reminders},
      onConflict: 'user_id,opportunity_id'));

  Future<void> unsave(String opportunityId) => guard(() =>
      _c.from('saved_opportunities').delete().eq('user_id', requireUserId(_c)).eq('opportunity_id', opportunityId));

  Future<void> setSavedReminders(String opportunityId, bool enabled) => guard(() => _c.from('saved_opportunities')
      .update({'reminders_enabled': enabled}).eq('user_id', requireUserId(_c)).eq('opportunity_id', opportunityId));

  /// Marking Interested schedules reminders in the database (default 7/3/1/0 days, PKT 09:00).
  Future<void> markInterested(String opportunityId, {bool reminders = true, List<int> offsets = const [7, 3, 1, 0]}) =>
      guard(() => _c.from('interested_opportunities').upsert({
            'user_id': requireUserId(_c),
            'opportunity_id': opportunityId,
            'reminders_enabled': reminders,
            'reminder_offsets_days': offsets,
          }, onConflict: 'user_id,opportunity_id'));

  Future<void> removeInterested(String opportunityId) => guard(() =>
      _c.from('interested_opportunities').delete().eq('user_id', requireUserId(_c)).eq('opportunity_id', opportunityId));

  Future<void> updateReminders(String opportunityId, {required bool enabled, required List<int> offsets}) => guard(() => _c
      .from('interested_opportunities')
      .update({'reminders_enabled': enabled, 'reminder_offsets_days': offsets})
      .eq('user_id', requireUserId(_c))
      .eq('opportunity_id', opportunityId));

  Future<void> moveInterestedToSaved(String opportunityId) => guard(() async {
        await save(opportunityId);
        await removeInterested(opportunityId);
      });

  Future<void> addCustomReminder({required String title, required DateTime atUtc, String? opportunityId, String? applicationId}) =>
      guard(() => _c.rpc('add_custom_reminder', params: {
            'p_title': title,
            'p_remind_at': atUtc.toUtc().toIso8601String(),
            'p_opportunity': opportunityId,
            'p_application': applicationId,
          }));

  Future<List<Map<String, dynamic>>> customReminders(String opportunityId) => guard(() async {
        final rows = await _c.from('reminders').select('id, title, remind_at, status')
            .eq('opportunity_id', opportunityId).eq('kind', 'custom').neq('status', 'cancelled').order('remind_at');
        return rows;
      });

  Future<void> deleteCustomReminder(String id) => guard(() => _c.from('reminders').delete().eq('id', id));

  Future<void> report({required String opportunityId, required String reason, String? details, String? evidenceUrl}) =>
      guard(() => _c.from('opportunity_reports').insert({
            'opportunity_id': opportunityId,
            'reporter_id': requireUserId(_c),
            'reason': reason,
            'details': details,
            'evidence_url': evidenceUrl,
          }));

  Future<void> suggestCorrection({required String opportunityId, required String field, required String value, String? evidenceUrl}) =>
      guard(() => _c.from('user_corrections').insert({
            'opportunity_id': opportunityId,
            'user_id': requireUserId(_c),
            'field': field,
            'suggested_value': value,
            'evidence_url': evidenceUrl,
          }));

  Future<void> submitOpportunity({required String org, required String title, required String sourceUrl, Map<String, dynamic> payload = const {}}) =>
      guard(() => _c.from('opportunity_submissions').insert({
            'submitted_by': requireUserId(_c),
            'organization_name': org,
            'title': title,
            'source_url': sourceUrl,
            'payload': payload,
          }));

  Future<void> saveComparison(String name, List<String> ids) =>
      guard(() => _c.from('comparisons').insert({'user_id': requireUserId(_c), 'name': name, 'opportunity_ids': ids}));

  Future<List<Map<String, dynamic>>> savedComparisons() => guard(() async {
        final rows = await _c.from('comparisons').select().eq('user_id', requireUserId(_c)).order('created_at', ascending: false);
        return rows;
      });

  Future<void> deleteComparison(String id) => guard(() => _c.from('comparisons').delete().eq('id', id));
}

final engagementRepositoryProvider =
    Provider<EngagementRepository>((ref) => EngagementRepository(ref.watch(supabaseProvider), ref.watch(offlineCacheProvider)));

/// Ids the user saved / is interested in — used to render toggle states everywhere.
final savedIdsProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(engagementRepositoryProvider).savedIds();
});
final interestedIdsProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(engagementRepositoryProvider).interestedIds();
});
final savedListProvider = FutureProvider.autoDispose<List<SavedEntry>>((ref) {
  ref.watch(savedIdsProvider);
  return ref.watch(engagementRepositoryProvider).saved();
});
final interestedListProvider = FutureProvider.autoDispose<List<InterestedEntry>>((ref) {
  ref.watch(interestedIdsProvider);
  return ref.watch(engagementRepositoryProvider).interested();
});

/// Comparison tray (2–4 ids), persisted locally.
class CompareTray extends StateNotifier<List<String>> {
  CompareTray(this._cache) : super(_cache.compareIds());
  final OfflineCache _cache;
  static const max = 4;

  /// Returns false when the tray is full.
  bool toggle(String id) {
    if (state.contains(id)) {
      state = [...state]..remove(id);
    } else {
      if (state.length >= max) return false;
      state = [...state, id];
    }
    _cache.setCompareIds(state);
    return true;
  }

  void setAll(List<String> ids) {
    state = ids.take(max).toList();
    _cache.setCompareIds(state);
  }

  void clear() => setAll(const []);
}

final compareTrayProvider = StateNotifierProvider<CompareTray, List<String>>((ref) => CompareTray(ref.watch(offlineCacheProvider)));
