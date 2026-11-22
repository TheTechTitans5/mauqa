import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../models/content.dart';
import '../supabase_client.dart';

/// Guides, interview questions, community content, CV/cover letters, dashboards and account data rights.
class ContentRepository {
  ContentRepository(this._c);
  final SupabaseClient _c;

  Future<HomeSummary> homeSummary() => guard(() async => HomeSummary(((await _c.rpc('home_summary')) as Map).cast<String, dynamic>()));

  Future<List<Guide>> guides({String? category}) => guard(() async {
        var q = _c.from('guides').select().eq('is_published', true);
        if (category != null) q = q.eq('category', category);
        final rows = await q.order('sort_order');
        return rows.map(Guide.fromJson).toList();
      });

  Future<List<InterviewQuestion>> interviewQuestions() => guard(() async {
        final rows = await _c.from('interview_questions').select().eq('is_published', true);
        return rows.map(InterviewQuestion.fromJson).toList();
      });

  Future<List<SuccessStory>> stories() => guard(() async {
        final rows = await _c.from('success_stories').select().order('published_at', ascending: false, nullsFirst: false).limit(50);
        return rows.map(SuccessStory.fromJson).toList();
      });

  Future<void> submitStory({required String displayName, required String title, required String body, required String type, String? institution}) =>
      guard(() => _c.from('success_stories').insert({
            'author_id': requireUserId(_c),
            'author_display_name': displayName,
            'title': title,
            'body': body,
            'story_type': type,
            'institution_name': institution,
          }));

  Future<void> reportStory(String storyId, String reason, String? details) => guard(() =>
      _c.from('content_reports').insert({'story_id': storyId, 'reporter_id': requireUserId(_c), 'reason': reason, 'details': details}));

  Future<List<Mentor>> mentors() => guard(() async {
        final rows = await _c.from('mentors').select().eq('status', 'approved').order('display_name');
        return rows.map(Mentor.fromJson).toList();
      });

  Future<List<Map<String, dynamic>>> announcements() => guard(() async {
        final rows = await _c.from('announcements').select('id, title, body, published_at').eq('is_published', true)
            .order('published_at', ascending: false).limit(5);
        return rows;
      });

  // ---------------------------------------------------------------- CV builder & cover letters
  Future<({String? id, CvData data})> loadCv() => guard(() async {
        final row = await _c.from('cv_documents').select().eq('user_id', requireUserId(_c)).order('updated_at', ascending: false).limit(1).maybeSingle();
        if (row == null) return (id: null, data: CvData());
        return (id: row['id'] as String?, data: CvData.fromJson((row['data'] as Map).cast<String, dynamic>(), template: row['template'] as String));
      });

  Future<String> saveCv(String? id, CvData data) => guard(() async {
        final row = {'user_id': requireUserId(_c), 'title': data.name.isEmpty ? 'My CV' : '${data.name} CV', 'template': data.template, 'data': data.toJson()};
        if (id == null) {
          final r = await _c.from('cv_documents').insert(row).select('id').single();
          return r['id'] as String;
        }
        await _c.from('cv_documents').update(row).eq('id', id);
        return id;
      });

  Future<List<Map<String, dynamic>>> coverLetters() => guard(() async {
        final rows = await _c.from('cover_letters').select().eq('user_id', requireUserId(_c)).order('updated_at', ascending: false);
        return rows;
      });

  Future<void> saveCoverLetter({String? id, required String title, required String template, required String body, String? opportunityId}) =>
      guard(() async {
        final row = {'user_id': requireUserId(_c), 'title': title, 'template': template, 'body': body, 'opportunity_id': opportunityId};
        if (id == null) {
          await _c.from('cover_letters').insert(row);
        } else {
          await _c.from('cover_letters').update(row).eq('id', id);
        }
      });

  Future<void> deleteCoverLetter(String id) => guard(() => _c.from('cover_letters').delete().eq('id', id));

  // ---------------------------------------------------------------- data rights
  Future<Map<String, dynamic>> exportMyData() => guard(() async {
        final res = await _c.functions.invoke('account', body: {'action': 'export'});
        return (res.data as Map).cast<String, dynamic>();
      });

  Future<void> deleteMyAccount() => guard(() async {
        await _c.functions.invoke('account', body: {'action': 'delete', 'confirm': 'DELETE'});
        await _c.auth.signOut();
      });

  /// kind: feedback | technical_issue | support — reviewed by staff in the admin dashboard.
  Future<void> sendFeedback(String kind, String message, {String? appVersion, String? platform}) => guard(() => _c.from('feedback').insert({
        'user_id': requireUserId(_c),
        'kind': kind,
        'message': message.trim(),
        'app_version': appVersion,
        'platform': platform,
      }));
}

final contentRepositoryProvider = Provider<ContentRepository>((ref) => ContentRepository(ref.watch(supabaseProvider)));
final homeSummaryProvider = FutureProvider.autoDispose<HomeSummary>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(contentRepositoryProvider).homeSummary();
});
final guidesProvider = FutureProvider.autoDispose.family<List<Guide>, String?>((ref, cat) => ref.watch(contentRepositoryProvider).guides(category: cat));
final storiesProvider = FutureProvider.autoDispose<List<SuccessStory>>((ref) => ref.watch(contentRepositoryProvider).stories());
final mentorsProvider = FutureProvider.autoDispose<List<Mentor>>((ref) => ref.watch(contentRepositoryProvider).mentors());
