import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../supabase_client.dart';

class ProfileRepository {
  ProfileRepository(this._c);
  final SupabaseClient _c;

  Future<FullProfile> load() => guard(() async {
        final uid = requireUserId(_c);
        final results = await Future.wait<dynamic>(<Future<dynamic>>[
          _c.from('profiles').select().eq('id', uid).single(),
          _c.from('education_records').select('*, institutions(name, short_name)').eq('user_id', uid).order('is_current', ascending: false),
          _c.from('user_skills').select('id, skill').eq('user_id', uid).order('created_at'),
          _c.from('user_interests').select('id, interest').eq('user_id', uid).order('created_at'),
          _c.from('user_experiences').select().eq('user_id', uid).order('start_date', ascending: false),
          _c.from('user_certifications').select().eq('user_id', uid).order('created_at', ascending: false),
          _c.rpc('profile_completion', params: {'p_user': uid}),
        ]);
        return FullProfile(
          profile: Profile.fromJson(results[0] as Map<String, dynamic>),
          education: (results[1] as List).map((e) => EducationRecord.fromJson(e as Map<String, dynamic>)).toList(),
          skills: (results[2] as List).map((e) => NamedItem(e['id'] as String, e['skill'] as String)).toList(),
          interests: (results[3] as List).map((e) => NamedItem(e['id'] as String, e['interest'] as String)).toList(),
          experiences: (results[4] as List).map((e) => Experience.fromJson(e as Map<String, dynamic>)).toList(),
          certifications: (results[5] as List).map((e) => Certification.fromJson(e as Map<String, dynamic>)).toList(),
          completion: (results[6] as num?)?.toInt() ?? 0,
        );
      });

  /// Updates editable profile columns. Protected columns (roles, suspension, version) are enforced server-side.
  Future<void> updateProfile(Map<String, dynamic> patch) => guard(() async {
        const allowed = {
          'full_name', 'phone', 'date_of_birth', 'gender', 'cnic', 'nationality', 'province', 'city', 'address', 'user_category',
          'employment_status', 'languages', 'household_income_range', 'household_income_monthly_pkr', 'has_disability',
          'share_sensitive_for_eligibility', 'preferred_language', 'recommendation_prefs', 'privacy_settings', 'avatar_path',
        };
        final clean = Map<String, dynamic>.from(patch)..removeWhere((k, _) => !allowed.contains(k));
        await _c.from('profiles').update(clean).eq('id', requireUserId(_c));
      });

  Future<void> saveEducation(EducationRecord r) => guard(() async {
        final uid = requireUserId(_c);
        if (r.isCurrent) {
          await _c.from('education_records').update({'is_current': false}).eq('user_id', uid).eq('is_current', true);
        }
        if (r.id == null) {
          await _c.from('education_records').insert(r.toRow(uid));
        } else {
          await _c.from('education_records').update(r.toRow(uid)).eq('id', r.id!);
        }
      });

  Future<void> deleteEducation(String id) => guard(() => _c.from('education_records').delete().eq('id', id));

  Future<void> addSkill(String skill) => guard(() => _c.from('user_skills').insert({'user_id': requireUserId(_c), 'skill': skill.trim()}));
  Future<void> removeSkill(String id) => guard(() => _c.from('user_skills').delete().eq('id', id));
  Future<void> addInterest(String v) => guard(() => _c.from('user_interests').insert({'user_id': requireUserId(_c), 'interest': v.trim()}));
  Future<void> removeInterest(String id) => guard(() => _c.from('user_interests').delete().eq('id', id));

  Future<void> saveExperience(Experience e) => guard(() async {
        final uid = requireUserId(_c);
        if (e.id == null) {
          await _c.from('user_experiences').insert(e.toRow(uid));
        } else {
          await _c.from('user_experiences').update(e.toRow(uid)).eq('id', e.id!);
        }
      });
  Future<void> deleteExperience(String id) => guard(() => _c.from('user_experiences').delete().eq('id', id));

  Future<void> saveCertification(Certification c) => guard(() async {
        final uid = requireUserId(_c);
        if (c.id == null) {
          await _c.from('user_certifications').insert(c.toRow(uid));
        } else {
          await _c.from('user_certifications').update(c.toRow(uid)).eq('id', c.id!);
        }
      });
  Future<void> deleteCertification(String id) => guard(() => _c.from('user_certifications').delete().eq('id', id));

  Future<List<Institution>> searchInstitutions(String q) => guard(() async {
        final rows = await _c.from('institutions').select('id, name, short_name, city')
            .or('name.ilike.%${q.replaceAll(RegExp(r'[,()%]'), '')}%,short_name.ilike.%${q.replaceAll(RegExp(r'[,()%]'), '')}%')
            .order('name').limit(20);
        return rows.map(Institution.fromJson).toList();
      });

  /// Avatars live in a private bucket; the app shows them through short-lived signed URLs.
  Future<String> uploadAvatar(Uint8List bytes, String ext) => guard(() async {
        final uid = requireUserId(_c);
        final mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
        final path = '$uid/avatar.$ext';
        await _c.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: true));
        await updateProfile({'avatar_path': path});
        return path;
      });

  Future<String?> avatarUrl(String? path) async {
    if (path == null) return null;
    try {
      return await _c.storage.from('avatars').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> myRoles() => guard(() async {
        final r = await _c.rpc('my_roles');
        return (r as List? ?? []).map((e) => e.toString()).toList();
      });
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(supabaseProvider)));

final fullProfileProvider = FutureProvider.autoDispose<FullProfile>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).load();
});

final avatarUrlProvider = FutureProvider.autoDispose.family<String?, String?>(
    (ref, path) => ref.watch(profileRepositoryProvider).avatarUrl(path));
