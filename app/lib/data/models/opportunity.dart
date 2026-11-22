import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];
int? _int(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

/// Row of the `opportunity_feed` view — used by cards, lists and search results.
class Opportunity {
  Opportunity({
    required this.id,
    required this.title,
    this.titleUr,
    this.summary,
    required this.organizationId,
    required this.organizationName,
    this.organizationVerified = false,
    this.organizationLogoUrl,
    this.organizationWebsite,
    this.orgType,
    required this.categorySlug,
    required this.categoryNameEn,
    this.categoryNameUr,
    this.categoryIcon,
    this.categoryColor,
    this.fundingType,
    this.amountText,
    this.amountMinPkr,
    this.amountMaxPkr,
    this.workMode,
    this.locationText,
    this.isNationwide = true,
    this.provinces = const [],
    this.cities = const [],
    this.educationLevels = const [],
    this.fieldsOfStudy = const [],
    this.requiredSkills = const [],
    this.minAge,
    this.maxAge,
    this.genderEligibility = 'any',
    this.openingDate,
    this.deadline,
    this.tags = const [],
    this.hasApplicationFee = false,
    this.applicationFeePkr,
    this.verificationStatus = 'unverified',
    this.isFeatured = false,
    this.isReported = false,
    this.isDemo = false,
    this.lastCheckedAt,
    this.lastVerifiedAt,
    this.sourceUrl,
    this.officialApplicationUrl,
    this.saveCount = 0,
    this.interestCount = 0,
    this.viewCount = 0,
    this.createdAt,
    this.effectiveStatus = 'open',
    this.durationText,
    this.recurrenceKey,
  });

  final String id;
  final String title;
  final String? titleUr;
  final String? summary;
  final String organizationId;
  final String organizationName;
  final bool organizationVerified;
  final String? organizationLogoUrl;
  final String? organizationWebsite;
  final String? orgType;
  final String categorySlug;
  final String categoryNameEn;
  final String? categoryNameUr;
  final String? categoryIcon;
  final String? categoryColor;
  final String? fundingType;
  final String? amountText;
  final int? amountMinPkr;
  final int? amountMaxPkr;
  final String? workMode;
  final String? locationText;
  final bool isNationwide;
  final List<String> provinces;
  final List<String> cities;
  final List<String> educationLevels;
  final List<String> fieldsOfStudy;
  final List<String> requiredSkills;
  final int? minAge;
  final int? maxAge;
  final String genderEligibility;
  final DateTime? openingDate;
  final DateTime? deadline;
  final List<String> tags;
  final bool hasApplicationFee;
  final int? applicationFeePkr;
  final String verificationStatus;
  final bool isFeatured;
  final bool isReported;
  final bool isDemo;
  final DateTime? lastCheckedAt;
  final DateTime? lastVerifiedAt;
  final String? sourceUrl;
  final String? officialApplicationUrl;
  final int saveCount;
  final int interestCount;
  final int viewCount;
  final DateTime? createdAt;
  /// open | closing_soon | upcoming | closed (computed by the database)
  final String effectiveStatus;
  final String? durationText;
  /// Links yearly cycles of the same programme (used for history/forecast estimates).
  final String? recurrenceKey;

  bool get isClosed => effectiveStatus == 'closed';
  bool get isVerified => verificationStatus == 'verified';
  String localizedTitle(bool urdu) => urdu && (titleUr?.isNotEmpty ?? false) ? titleUr! : title;
  String categoryName(bool urdu) => urdu && (categoryNameUr?.isNotEmpty ?? false) ? categoryNameUr! : categoryNameEn;
  int? get daysLeft => deadline == null ? null : Pkt.daysUntil(deadline!);

  String get location {
    if (workMode == 'remote') return 'Remote';
    if (locationText?.isNotEmpty ?? false) return locationText!;
    if (isNationwide) return 'Nationwide';
    return [...cities, ...provinces].join(', ');
  }

  String? get fundingLabel => amountText ?? switch (fundingType) {
        'fully_funded' => 'Fully funded',
        'partially_funded' => 'Partially funded',
        'paid' => 'Paid',
        'unpaid' => 'Unpaid',
        _ => null,
      };

  factory Opportunity.fromJson(Map<String, dynamic> j) => Opportunity(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        titleUr: j['title_ur'] as String?,
        summary: j['summary'] as String?,
        organizationId: (j['organization_id'] ?? '') as String,
        organizationName: (j['organization_name'] ?? '') as String,
        organizationVerified: j['organization_verified'] == true,
        organizationLogoUrl: j['organization_logo_url'] as String?,
        organizationWebsite: j['organization_website'] as String?,
        orgType: j['org_type'] as String?,
        categorySlug: (j['category_slug'] ?? '') as String,
        categoryNameEn: (j['category_name_en'] ?? '') as String,
        categoryNameUr: j['category_name_ur'] as String?,
        categoryIcon: j['category_icon'] as String?,
        categoryColor: j['category_color'] as String?,
        fundingType: j['funding_type'] as String?,
        amountText: j['amount_text'] as String?,
        amountMinPkr: _int(j['amount_min_pkr']),
        amountMaxPkr: _int(j['amount_max_pkr']),
        workMode: j['work_mode'] as String?,
        locationText: j['location_text'] as String?,
        isNationwide: j['is_nationwide'] != false,
        provinces: _strings(j['provinces']),
        cities: _strings(j['cities']),
        educationLevels: _strings(j['education_levels']),
        fieldsOfStudy: _strings(j['fields_of_study']),
        requiredSkills: _strings(j['required_skills']),
        minAge: _int(j['min_age']),
        maxAge: _int(j['max_age']),
        genderEligibility: (j['gender_eligibility'] ?? 'any') as String,
        openingDate: parseTs(j['opening_date']),
        deadline: parseTs(j['deadline']),
        tags: _strings(j['tags']),
        hasApplicationFee: j['has_application_fee'] == true,
        applicationFeePkr: _int(j['application_fee_pkr']),
        verificationStatus: (j['verification_status'] ?? 'unverified') as String,
        isFeatured: j['is_featured'] == true,
        isReported: j['is_reported'] == true,
        isDemo: j['is_demo'] == true,
        lastCheckedAt: parseTs(j['last_checked_at']),
        lastVerifiedAt: parseTs(j['last_verified_at']),
        sourceUrl: j['source_url'] as String?,
        officialApplicationUrl: j['official_application_url'] as String?,
        saveCount: _int(j['save_count']) ?? 0,
        interestCount: _int(j['interest_count']) ?? 0,
        viewCount: _int(j['view_count']) ?? 0,
        createdAt: parseTs(j['created_at']),
        effectiveStatus: (j['effective_status'] ?? 'open') as String,
        durationText: j['duration_text'] as String?,
        recurrenceKey: j['recurrence_key'] as String?,
      );

  /// For the offline cache.
  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'title_ur': titleUr, 'summary': summary, 'organization_id': organizationId,
        'organization_name': organizationName, 'organization_verified': organizationVerified, 'category_slug': categorySlug,
        'category_name_en': categoryNameEn, 'category_name_ur': categoryNameUr, 'category_icon': categoryIcon,
        'category_color': categoryColor, 'funding_type': fundingType, 'amount_text': amountText, 'work_mode': workMode,
        'location_text': locationText, 'is_nationwide': isNationwide, 'provinces': provinces, 'cities': cities,
        'deadline': deadline?.toIso8601String(), 'opening_date': openingDate?.toIso8601String(), 'tags': tags,
        'has_application_fee': hasApplicationFee, 'application_fee_pkr': applicationFeePkr,
        'verification_status': verificationStatus, 'is_featured': isFeatured, 'is_reported': isReported, 'is_demo': isDemo,
        'source_url': sourceUrl, 'official_application_url': officialApplicationUrl, 'effective_status': effectiveStatus,
        'last_checked_at': lastCheckedAt?.toIso8601String(), 'last_verified_at': lastVerifiedAt?.toIso8601String(),
      };
}

class EligibilityRule {
  EligibilityRule({required this.id, this.parentId, required this.nodeType, this.groupOperator, this.criterionType,
      this.params = const {}, this.label, this.isMandatory = true, this.sortOrder = 0});
  final String id;
  final String? parentId;
  final String nodeType;
  final String? groupOperator;
  final String? criterionType;
  final Map<String, dynamic> params;
  final String? label;
  final bool isMandatory;
  final int sortOrder;

  factory EligibilityRule.fromJson(Map<String, dynamic> j) => EligibilityRule(
        id: j['id'] as String,
        parentId: j['parent_id'] as String?,
        nodeType: j['node_type'] as String,
        groupOperator: j['group_operator'] as String?,
        criterionType: j['criterion_type'] as String?,
        params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
        label: j['label'] as String?,
        isMandatory: j['is_mandatory'] != false,
        sortOrder: _int(j['sort_order']) ?? 0,
      );
}

class RequiredDocument {
  RequiredDocument({required this.category, required this.label, this.isMandatory = true, this.notes});
  final String category;
  final String label;
  final bool isMandatory;
  final String? notes;
  factory RequiredDocument.fromJson(Map<String, dynamic> j) => RequiredDocument(
      category: j['category'] as String, label: j['label'] as String, isMandatory: j['is_mandatory'] != false, notes: j['notes'] as String?);
}

/// Full details for the detail screen.
class OpportunityDetail {
  OpportunityDetail({required this.base, this.description, this.benefits, this.eligibilitySummary, this.applicationProcedure,
      this.selectionProcedure, this.importantInstructions, this.organizationDescription, this.officialDomains = const [],
      this.contactEmail, this.rules = const [], this.documents = const []});
  final Opportunity base;
  final String? description;
  final String? benefits;
  final String? eligibilitySummary;
  final String? applicationProcedure;
  final String? selectionProcedure;
  final String? importantInstructions;
  final String? organizationDescription;
  final List<String> officialDomains;
  final String? contactEmail;
  final List<EligibilityRule> rules;
  final List<RequiredDocument> documents;
}

class OpportunityCategory {
  OpportunityCategory({required this.id, required this.slug, required this.nameEn, required this.nameUr, required this.icon, required this.colorHex});
  final String id;
  final String slug;
  final String nameEn;
  final String nameUr;
  final String icon;
  final String colorHex;
  String name(bool urdu) => urdu ? nameUr : nameEn;
  factory OpportunityCategory.fromJson(Map<String, dynamic> j) => OpportunityCategory(
      id: j['id'] as String, slug: j['slug'] as String, nameEn: j['name_en'] as String, nameUr: j['name_ur'] as String,
      icon: (j['icon'] ?? 'star') as String, colorHex: (j['color_hex'] ?? '#16B8A6') as String);
}

const Map<String, IconData> categoryIcons = {
  'school': Icons.school_rounded, 'payments': Icons.payments_rounded, 'workspace_premium': Icons.workspace_premium_rounded,
  'badge': Icons.badge_rounded, 'work': Icons.work_rounded, 'stars': Icons.stars_rounded, 'construction': Icons.construction_rounded,
  'account_balance': Icons.account_balance_rounded, 'groups': Icons.groups_rounded, 'psychology': Icons.psychology_rounded,
  'menu_book': Icons.menu_book_rounded, 'verified': Icons.verified_rounded, 'rocket_launch': Icons.rocket_launch_rounded,
  'savings': Icons.savings_rounded, 'storefront': Icons.storefront_rounded, 'agriculture': Icons.agriculture_rounded,
  'diversity_3': Icons.diversity_3_rounded, 'accessible': Icons.accessible_rounded, 'science': Icons.science_rounded,
  'sync_alt': Icons.sync_alt_rounded, 'flight_takeoff': Icons.flight_takeoff_rounded, 'emoji_events': Icons.emoji_events_rounded,
  'campaign': Icons.campaign_rounded, 'volunteer_activism': Icons.volunteer_activism_rounded, 'diversity_1': Icons.diversity_1_rounded,
};

IconData iconFor(String? name) => categoryIcons[name] ?? Icons.star_rounded;
