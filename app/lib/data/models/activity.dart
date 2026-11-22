import '../../core/utils/formatters.dart';
import 'opportunity.dart';

class CriterionResult {
  CriterionResult({required this.label, required this.status, required this.reason, required this.mandatory, required this.type});
  final String label;
  final String status; // met | not_met | unknown
  final String reason;
  final bool mandatory;
  final String type;
  factory CriterionResult.fromJson(Map<String, dynamic> j) => CriterionResult(
        label: (j['label'] ?? '') as String,
        status: (j['status'] ?? 'unknown') as String,
        reason: (j['reason'] ?? '') as String,
        mandatory: j['mandatory'] != false,
        type: (j['type'] ?? '') as String,
      );
}

class EligibilityResult {
  EligibilityResult({required this.outcome, required this.score, required this.matched, required this.failed,
      required this.unconfirmed, required this.missing, required this.explanation});
  final String outcome; // eligible | probably_eligible | not_eligible
  final double score;
  final List<CriterionResult> matched;
  final List<CriterionResult> failed;
  final List<CriterionResult> unconfirmed;
  final List<String> missing;
  final String explanation;

  static List<CriterionResult> _list(Object? v) =>
      v is List ? v.whereType<Map>().map((e) => CriterionResult.fromJson(e.cast<String, dynamic>())).toList() : [];

  /// Accepts the Edge Function shape (camelCase) and the stored row shape (snake_case).
  factory EligibilityResult.fromJson(Map<String, dynamic> j) => EligibilityResult(
        outcome: (j['outcome'] ?? 'probably_eligible') as String,
        score: (j['score'] as num?)?.toDouble() ?? 0,
        matched: _list(j['matched']),
        failed: _list(j['failed']),
        unconfirmed: _list(j['unconfirmed']),
        missing: ((j['missingRequirements'] ?? j['missing_requirements']) as List?)?.map((e) => e.toString()).toList() ?? [],
        explanation: (j['explanation'] ?? '') as String,
      );
}

class Recommendation {
  Recommendation({required this.opportunityId, required this.score, required this.reasons, this.eligibility});
  final String opportunityId;
  final double score;
  final List<String> reasons;
  final String? eligibility;
  factory Recommendation.fromJson(Map<String, dynamic> j) => Recommendation(
        opportunityId: j['opportunityId'] as String,
        score: (j['score'] as num).toDouble(),
        reasons: (j['reasons'] as List).map((e) => e.toString()).toList(),
        eligibility: j['eligibility'] as String?,
      );
}

class RecommendedOpportunity {
  RecommendedOpportunity(this.opportunity, this.recommendation);
  final Opportunity opportunity;
  final Recommendation recommendation;
}

const applicationStatuses = [
  'interested', 'planning', 'preparing_documents', 'applied', 'under_review',
  'shortlisted', 'interview_scheduled', 'selected', 'rejected', 'withdrawn',
];

class Application {
  Application({required this.id, this.opportunityId, this.title, this.organization, required this.status, this.appliedOn,
      this.deadline, this.interviewAt, this.followUpAt, this.notes, this.externalReference, this.officialUrl, this.updatedAt});
  final String id;
  final String? opportunityId;
  final String? title;
  final String? organization;
  final String status;
  final DateTime? appliedOn;
  final DateTime? deadline;
  final DateTime? interviewAt;
  final DateTime? followUpAt;
  final String? notes;
  final String? externalReference;
  final String? officialUrl;
  final DateTime? updatedAt;

  String get displayTitle => title ?? 'Application';
  int get stage => applicationStatuses.indexOf(status);

  factory Application.fromJson(Map<String, dynamic> j) {
    final o = (j['opportunities'] as Map?)?.cast<String, dynamic>();
    final org = (o?['organizations'] as Map?)?.cast<String, dynamic>();
    return Application(
      id: j['id'] as String,
      opportunityId: j['opportunity_id'] as String?,
      title: (j['custom_title'] as String?) ?? (o?['title'] as String?) ?? (j['title_snapshot'] as String?),
      organization: (j['custom_organization'] as String?) ?? (org?['name'] as String?),
      status: j['status'] as String,
      appliedOn: parseTs(j['applied_on']),
      deadline: parseTs(j['deadline']) ?? parseTs(o?['deadline']),
      interviewAt: parseTs(j['interview_at']),
      followUpAt: parseTs(j['follow_up_at']),
      notes: j['notes'] as String?,
      externalReference: j['external_reference'] as String?,
      officialUrl: (j['custom_url'] as String?) ?? (o?['official_application_url'] as String?),
      updatedAt: parseTs(j['updated_at']),
    );
  }
}

class StatusChange {
  StatusChange({this.from, required this.to, required this.at, this.note});
  final String? from;
  final String to;
  final DateTime at;
  final String? note;
  factory StatusChange.fromJson(Map<String, dynamic> j) => StatusChange(
      from: j['from_status'] as String?, to: j['to_status'] as String, at: parseTs(j['changed_at'])!, note: j['note'] as String?);
}

const documentCategories = [
  'cnic', 'passport', 'cv', 'transcript', 'degree', 'domicile', 'photograph', 'recommendation_letter',
  'statement_of_purpose', 'personal_statement', 'income_certificate', 'experience_certificate', 'skill_certificate', 'other',
];
const commonDocuments = ['cnic', 'cv', 'transcript', 'domicile', 'photograph'];

class UserDocument {
  UserDocument({required this.id, required this.category, required this.title, required this.storagePath, required this.mimeType,
      required this.sizeBytes, this.expiresOn, this.createdAt});
  final String id;
  final String category;
  final String title;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final DateTime? expiresOn;
  final DateTime? createdAt;
  factory UserDocument.fromJson(Map<String, dynamic> j) => UserDocument(
        id: j['id'] as String,
        category: j['category'] as String,
        title: j['title'] as String,
        storagePath: j['storage_path'] as String,
        mimeType: j['mime_type'] as String,
        sizeBytes: (j['size_bytes'] as num).toInt(),
        expiresOn: parseTs(j['expires_on']),
        createdAt: parseTs(j['created_at']),
      );
  bool get isExpiringSoon => expiresOn != null && expiresOn!.difference(DateTime.now().toUtc()).inDays <= 30;
}

class AppNotification {
  AppNotification({required this.id, required this.type, required this.title, required this.body, this.opportunityId,
      this.applicationId, required this.isRead, required this.createdAt});
  final String id;
  final String type;
  final String title;
  final String body;
  final String? opportunityId;
  final String? applicationId;
  final bool isRead;
  final DateTime createdAt;
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        opportunityId: j['opportunity_id'] as String?,
        applicationId: j['application_id'] as String?,
        isRead: j['is_read'] == true,
        createdAt: parseTs(j['created_at'])!,
      );
}

class NotificationPrefs {
  NotificationPrefs(this.raw);
  final Map<String, dynamic> raw;
  bool flag(String k) => raw[k] == true;
  List<int> get defaultOffsets => (raw['default_reminder_offsets'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [7, 3, 1, 0];
  int get reminderHour => (raw['reminder_hour_local'] as num?)?.toInt() ?? 9;
  int? get quietStart => (raw['quiet_hours_start'] as num?)?.toInt();
  int? get quietEnd => (raw['quiet_hours_end'] as num?)?.toInt();
}

class CalendarEvent {
  CalendarEvent({required this.at, required this.type, required this.title, this.opportunityId, this.applicationId, this.reminderId});
  final DateTime at;
  final String type;
  final String title;
  final String? opportunityId;
  final String? applicationId;
  final String? reminderId;
  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
        at: parseTs(j['event_date'])!,
        type: j['event_type'] as String,
        title: (j['title'] ?? '') as String,
        opportunityId: j['opportunity_id'] as String?,
        applicationId: j['application_id'] as String?,
        reminderId: j['reminder_id'] as String?,
      );
}

class HomeSummary {
  HomeSummary(this.raw);
  final Map<String, dynamic> raw;
  int _i(String k) => (raw[k] as num?)?.toInt() ?? 0;
  int get completion => _i('profile_completion');
  int get saved => _i('saved_count');
  int get interested => _i('interested_count');
  int get unread => _i('unread_notifications');
  int get upcomingDeadlines => _i('upcoming_deadlines');
  int get newThisWeek => _i('new_this_week');
  Map<String, int> get applicationsByStatus =>
      ((raw['applications_by_status'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  Map<String, int> get week => ((raw['week_activity'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  static HomeSummary empty() => HomeSummary(const {});
}

class InterestedEntry {
  InterestedEntry({required this.opportunity, required this.remindersEnabled, required this.offsets, this.note});
  final Opportunity opportunity;
  final bool remindersEnabled;
  final List<int> offsets;
  final String? note;
}

class SavedEntry {
  SavedEntry({required this.opportunity, this.folder, required this.remindersEnabled});
  final Opportunity opportunity;
  final String? folder;
  final bool remindersEnabled;
}
