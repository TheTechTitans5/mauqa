import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity.dart';
import '../models/content.dart';
import '../models/opportunity.dart';
import '../supabase_client.dart';

/// Filters for the search RPC. Empty lists / nulls mean "no filter".
@immutable
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.categories = const [],
    this.provinces = const [],
    this.cities = const [],
    this.educationLevels = const [],
    this.fields = const [],
    this.skills = const [],
    this.fundingTypes = const [],
    this.workModes = const [],
    this.orgTypes = const [],
    this.statuses = const [],
    this.gender,
    this.age,
    this.maxExperienceMonths,
    this.minAmountPkr,
    this.verifiedOnly = false,
    this.incomeBased = false,
    this.hideDemo = false,
    this.deadlineBefore,
    this.sort = 'relevance',
  });

  final String query;
  final List<String> categories, provinces, cities, educationLevels, fields, skills, fundingTypes, workModes, orgTypes, statuses;
  final String? gender;
  final int? age;
  final int? maxExperienceMonths;
  final int? minAmountPkr;
  final bool verifiedOnly;
  final bool incomeBased;
  final bool hideDemo;
  final DateTime? deadlineBefore;
  final String sort;

  int get activeCount => [categories, provinces, cities, educationLevels, fields, skills, fundingTypes, workModes, orgTypes, statuses]
          .where((l) => l.isNotEmpty).length +
      [gender, age, maxExperienceMonths, minAmountPkr, deadlineBefore].where((v) => v != null).length +
      (verifiedOnly ? 1 : 0) + (incomeBased ? 1 : 0);

  Map<String, dynamic> toRpcFilters() {
    final m = <String, dynamic>{};
    void list(String k, List<String> v) { if (v.isNotEmpty) m[k] = v; }
    list('categories', categories);
    list('provinces', provinces);
    list('cities', cities);
    list('education_levels', educationLevels);
    list('fields', fields);
    list('skills', skills);
    list('funding_types', fundingTypes);
    list('work_modes', workModes);
    list('org_types', orgTypes);
    list('statuses', statuses);
    if (gender != null) m['gender'] = gender;
    if (age != null) m['age'] = age;
    if (maxExperienceMonths != null) m['max_experience_months'] = maxExperienceMonths;
    if (minAmountPkr != null) m['min_amount_pkr'] = minAmountPkr;
    if (verifiedOnly) m['verified_only'] = true;
    if (incomeBased) m['income_based'] = true;
    if (hideDemo) m['hide_demo'] = true;
    if (deadlineBefore != null) m['deadline_before'] = deadlineBefore!.toUtc().toIso8601String();
    return m;
  }

  SearchFilters copyWith({
    String? query, List<String>? categories, List<String>? provinces, List<String>? cities, List<String>? educationLevels,
    List<String>? fields, List<String>? skills, List<String>? fundingTypes, List<String>? workModes, List<String>? orgTypes,
    List<String>? statuses, Object? gender = _keep, Object? age = _keep, Object? maxExperienceMonths = _keep,
    Object? minAmountPkr = _keep, bool? verifiedOnly, bool? incomeBased, bool? hideDemo, Object? deadlineBefore = _keep, String? sort,
  }) =>
      SearchFilters(
        query: query ?? this.query,
        categories: categories ?? this.categories,
        provinces: provinces ?? this.provinces,
        cities: cities ?? this.cities,
        educationLevels: educationLevels ?? this.educationLevels,
        fields: fields ?? this.fields,
        skills: skills ?? this.skills,
        fundingTypes: fundingTypes ?? this.fundingTypes,
        workModes: workModes ?? this.workModes,
        orgTypes: orgTypes ?? this.orgTypes,
        statuses: statuses ?? this.statuses,
        gender: gender == _keep ? this.gender : gender as String?,
        age: age == _keep ? this.age : age as int?,
        maxExperienceMonths: maxExperienceMonths == _keep ? this.maxExperienceMonths : maxExperienceMonths as int?,
        minAmountPkr: minAmountPkr == _keep ? this.minAmountPkr : minAmountPkr as int?,
        verifiedOnly: verifiedOnly ?? this.verifiedOnly,
        incomeBased: incomeBased ?? this.incomeBased,
        hideDemo: hideDemo ?? this.hideDemo,
        deadlineBefore: deadlineBefore == _keep ? this.deadlineBefore : deadlineBefore as DateTime?,
        sort: sort ?? this.sort,
      );

  SearchFilters cleared() => SearchFilters(query: query, sort: sort);

  @override
  bool operator ==(Object other) => other is SearchFilters && mapEquals(other.toRpcFilters(), toRpcFilters()) && other.query == query && other.sort == sort;
  @override
  int get hashCode => Object.hash(query, sort, toRpcFilters().toString());
}

const _keep = Object();

class SearchPage {
  SearchPage(this.items, this.total);
  final List<Opportunity> items;
  final int total;
}

class OpportunityRepository {
  OpportunityRepository(this._c);
  final SupabaseClient _c;
  static const pageSize = 20;

  Future<SearchPage> search(SearchFilters f, {int offset = 0}) => guard(() async {
        final res = await _c.rpc('search_opportunities', params: {
          'p_query': f.query.trim().isEmpty ? null : f.query.trim(),
          'p_filters': f.toRpcFilters(),
          'p_sort': f.sort,
          'p_limit': pageSize,
          'p_offset': offset,
        });
        final m = (res as Map).cast<String, dynamic>();
        final items = (m['items'] as List).map((e) => Opportunity.fromJson((e as Map).cast<String, dynamic>())).toList();
        return SearchPage(items, (m['total'] as num).toInt());
      });

  Future<List<Opportunity>> feed({String? category, String? status, bool featured = false, String order = 'deadline', int limit = 10}) =>
      guard(() async {
        var q = _c.from('opportunity_feed').select().neq('effective_status', 'closed');
        if (category != null) q = q.eq('category_slug', category);
        if (status != null) q = q.eq('effective_status', status);
        if (featured) q = q.eq('is_featured', true);
        final rows = order == 'latest'
            ? await q.order('created_at', ascending: false).limit(limit)
            : await q.order('deadline', ascending: true, nullsFirst: false).limit(limit);
        return rows.map(Opportunity.fromJson).toList();
      });

  Future<List<Opportunity>> trending({int limit = 10}) => guard(() async {
        final rows = await _c.rpc('trending_opportunities', params: {'p_limit': limit});
        return (rows as List).map((e) => Opportunity.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<List<Opportunity>> byIds(List<String> ids) => guard(() async {
        if (ids.isEmpty) return <Opportunity>[];
        final rows = await _c.from('opportunity_feed').select().inFilter('id', ids);
        final byId = {for (final r in rows) r['id'] as String: Opportunity.fromJson(r)};
        return ids.where(byId.containsKey).map((id) => byId[id]!).toList();
      });

  Future<OpportunityDetail> detail(String id) => guard(() async {
        final results = await Future.wait<dynamic>(<Future<dynamic>>[
          _c.from('opportunity_feed').select().eq('id', id).maybeSingle(),
          _c.from('opportunities').select('description, benefits, eligibility_summary, application_procedure, selection_procedure, '
              'important_instructions, organizations(description, official_domains, contact_email)').eq('id', id).maybeSingle(),
          _c.from('opportunity_eligibility_rules').select().eq('opportunity_id', id).order('sort_order'),
          _c.from('opportunity_documents').select().eq('opportunity_id', id),
        ]);
        final base = results[0] as Map<String, dynamic>?;
        if (base == null) throw AppException('This opportunity is no longer available.');
        final extra = (results[1] as Map<String, dynamic>?) ?? {};
        final org = (extra['organizations'] as Map?)?.cast<String, dynamic>() ?? {};
        _c.rpc('record_opportunity_view', params: {'p_opportunity': id}).then((_) {}, onError: (_) {});
        return OpportunityDetail(
          base: Opportunity.fromJson(base),
          description: extra['description'] as String?,
          benefits: extra['benefits'] as String?,
          eligibilitySummary: extra['eligibility_summary'] as String?,
          applicationProcedure: extra['application_procedure'] as String?,
          selectionProcedure: extra['selection_procedure'] as String?,
          importantInstructions: extra['important_instructions'] as String?,
          organizationDescription: org['description'] as String?,
          officialDomains: (org['official_domains'] as List?)?.map((e) => e.toString()).toList() ?? const [],
          contactEmail: org['contact_email'] as String?,
          rules: (results[2] as List).map((e) => EligibilityRule.fromJson(e as Map<String, dynamic>)).toList(),
          documents: (results[3] as List).map((e) => RequiredDocument.fromJson(e as Map<String, dynamic>)).toList(),
        );
      });

  Future<List<OpportunityCategory>> categories() => guard(() async {
        final rows = await _c.from('opportunity_categories').select().order('sort_order');
        return rows.map(OpportunityCategory.fromJson).toList();
      });

  /// Deterministic eligibility via the Edge Function (results are also stored server-side).
  Future<EligibilityResult> checkEligibility(String opportunityId, {bool force = false}) => guard(() async {
        final res = await _c.functions.invoke('eligibility-check', body: {'opportunity_id': opportunityId, 'force': force});
        final results = ((res.data as Map)['results'] as List);
        return EligibilityResult.fromJson(((results.first as Map)['result'] as Map).cast<String, dynamic>());
      });

  /// Stored (possibly stale) results for quick badges on cards.
  Future<Map<String, String>> storedOutcomes(List<String> ids) => guard(() async {
        if (ids.isEmpty) return <String, String>{};
        final rows = await _c.from('eligibility_checks').select('opportunity_id, outcome, is_stale').inFilter('opportunity_id', ids);
        return {for (final r in rows) if (r['is_stale'] != true) r['opportunity_id'] as String: r['outcome'] as String};
      });

  Future<List<RecommendedOpportunity>> recommended({int limit = 15}) => guard(() async {
        final res = await _c.functions.invoke('recommendations?limit=$limit');
        final recs = ((res.data as Map)['items'] as List).map((e) => Recommendation.fromJson((e as Map).cast<String, dynamic>())).toList();
        final opps = await byIds(recs.map((r) => r.opportunityId).toList());
        final byId = {for (final o in opps) o.id: o};
        return [for (final r in recs) if (byId[r.opportunityId] != null) RecommendedOpportunity(byId[r.opportunityId]!, r)];
      });

  Future<Forecast?> forecast(String recurrenceKey) => guard(() async {
        final row = await _c.from('opportunity_forecasts').select().eq('recurrence_key', recurrenceKey).maybeSingle();
        return row == null ? null : Forecast.fromJson(row);
      });

  Future<void> logSearch(String query, Map<String, dynamic> filters) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null || query.trim().length < 2) return;
    try {
      await _c.from('search_history').insert({'user_id': uid, 'query': query.trim(), 'filters': filters});
    } catch (_) {/* non-critical */}
  }
}

final opportunityRepositoryProvider = Provider<OpportunityRepository>((ref) => OpportunityRepository(ref.watch(supabaseProvider)));

final categoriesProvider = FutureProvider<List<OpportunityCategory>>((ref) => ref.watch(opportunityRepositoryProvider).categories());

final opportunityDetailProvider = FutureProvider.autoDispose.family<OpportunityDetail, String>(
    (ref, id) => ref.watch(opportunityRepositoryProvider).detail(id));

final eligibilityProvider = FutureProvider.autoDispose.family<EligibilityResult, String>(
    (ref, id) => ref.watch(opportunityRepositoryProvider).checkEligibility(id));
