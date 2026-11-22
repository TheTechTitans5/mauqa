import '../../core/utils/formatters.dart';

double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int? _int(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

class Profile {
  Profile({
    required this.id,
    this.fullName,
    this.avatarPath,
    this.email,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.cnic,
    this.nationality,
    this.province,
    this.city,
    this.address,
    this.userCategory,
    this.employmentStatus,
    this.languages = const [],
    this.incomeRange,
    this.incomeMonthlyPkr,
    this.hasDisability,
    this.shareSensitive = false,
    this.preferredLanguage = 'en',
    this.recommendationPrefs = const {},
    this.profileVersion = 1,
  });

  final String id;
  final String? fullName;
  final String? avatarPath;
  final String? email;
  final String? phone;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? cnic;
  final String? nationality;
  final String? province;
  final String? city;
  final String? address;
  final String? userCategory;
  final String? employmentStatus;
  final List<String> languages;
  final String? incomeRange;
  final int? incomeMonthlyPkr;
  final bool? hasDisability;
  final bool shareSensitive;
  final String preferredLanguage;
  final Map<String, dynamic> recommendationPrefs;
  final int profileVersion;

  String get firstName => (fullName ?? '').trim().split(RegExp(r'\s+')).first;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        fullName: j['full_name'] as String?,
        avatarPath: j['avatar_path'] as String?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        dateOfBirth: j['date_of_birth'] == null ? null : DateTime.tryParse(j['date_of_birth'] as String),
        gender: j['gender'] as String?,
        cnic: j['cnic'] as String?,
        nationality: j['nationality'] as String?,
        province: j['province'] as String?,
        city: j['city'] as String?,
        address: j['address'] as String?,
        userCategory: j['user_category'] as String?,
        employmentStatus: j['employment_status'] as String?,
        languages: (j['languages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        incomeRange: j['household_income_range'] as String?,
        incomeMonthlyPkr: _int(j['household_income_monthly_pkr']),
        hasDisability: j['has_disability'] as bool?,
        shareSensitive: j['share_sensitive_for_eligibility'] == true,
        preferredLanguage: (j['preferred_language'] ?? 'en') as String,
        recommendationPrefs: (j['recommendation_prefs'] as Map?)?.cast<String, dynamic>() ?? const {},
        profileVersion: _int(j['profile_version']) ?? 1,
      );
}

class EducationRecord {
  EducationRecord({
    this.id,
    required this.level,
    this.institutionId,
    this.institutionName,
    this.department,
    this.degreeProgram,
    this.fieldOfStudy,
    this.currentSemester,
    this.enrollmentStatus = 'completed',
    this.startYear,
    this.graduationYear,
    this.scoreType,
    this.scoreValue,
    this.scoreMax,
    this.isCurrent = false,
  });

  final String? id;
  final String level;
  final String? institutionId;
  final String? institutionName;
  final String? department;
  final String? degreeProgram;
  final String? fieldOfStudy;
  final int? currentSemester;
  final String enrollmentStatus;
  final int? startYear;
  final int? graduationYear;
  final String? scoreType;
  final double? scoreValue;
  final double? scoreMax;
  final bool isCurrent;

  factory EducationRecord.fromJson(Map<String, dynamic> j) => EducationRecord(
        id: j['id'] as String?,
        level: j['level'] as String,
        institutionId: j['institution_id'] as String?,
        institutionName: (j['institutions'] as Map?)?['name'] as String? ?? j['institution_name'] as String?,
        department: j['department'] as String?,
        degreeProgram: j['degree_program'] as String?,
        fieldOfStudy: j['field_of_study'] as String?,
        currentSemester: _int(j['current_semester']),
        enrollmentStatus: (j['enrollment_status'] ?? 'completed') as String,
        startYear: _int(j['start_year']),
        graduationYear: _int(j['graduation_year']),
        scoreType: j['score_type'] as String?,
        scoreValue: _num(j['score_value']),
        scoreMax: _num(j['score_max']),
        isCurrent: j['is_current'] == true,
      );

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'level': level,
        'institution_id': institutionId,
        'institution_name': institutionName,
        'department': department,
        'degree_program': degreeProgram,
        'field_of_study': fieldOfStudy,
        'current_semester': currentSemester,
        'enrollment_status': enrollmentStatus,
        'start_year': startYear,
        'graduation_year': graduationYear,
        'score_type': scoreType,
        'score_value': scoreValue,
        'score_max': scoreMax,
        'is_current': isCurrent,
      };

  String get scoreLabel {
    if (scoreValue == null) return '';
    if (scoreType == 'cgpa') return 'CGPA ${scoreValue!.toStringAsFixed(2)}${scoreMax != null ? ' / ${scoreMax!.toStringAsFixed(1)}' : ''}';
    if (scoreMax != null) return '${scoreValue!.toStringAsFixed(0)} / ${scoreMax!.toStringAsFixed(0)}';
    return '${scoreValue!.toStringAsFixed(1)}%';
  }
}

class Experience {
  Experience({this.id, required this.kind, required this.title, this.organization, required this.startDate, this.endDate,
      this.isCurrent = false, this.description});
  final String? id;
  final String kind;
  final String title;
  final String? organization;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isCurrent;
  final String? description;

  factory Experience.fromJson(Map<String, dynamic> j) => Experience(
        id: j['id'] as String?,
        kind: j['kind'] as String,
        title: j['title'] as String,
        organization: j['organization'] as String?,
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: j['end_date'] == null ? null : DateTime.parse(j['end_date'] as String),
        isCurrent: j['is_current'] == true,
        description: j['description'] as String?,
      );
  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId, 'kind': kind, 'title': title, 'organization': organization,
        'start_date': _d(startDate), 'end_date': endDate == null ? null : _d(endDate!), 'is_current': isCurrent, 'description': description,
      };
}

class Certification {
  Certification({this.id, required this.name, this.issuer, this.issuedOn, this.expiresOn, this.credentialUrl});
  final String? id;
  final String name;
  final String? issuer;
  final DateTime? issuedOn;
  final DateTime? expiresOn;
  final String? credentialUrl;
  factory Certification.fromJson(Map<String, dynamic> j) => Certification(
        id: j['id'] as String?,
        name: j['name'] as String,
        issuer: j['issuer'] as String?,
        issuedOn: j['issued_on'] == null ? null : DateTime.parse(j['issued_on'] as String),
        expiresOn: j['expires_on'] == null ? null : DateTime.parse(j['expires_on'] as String),
        credentialUrl: j['credential_url'] as String?,
      );
  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId, 'name': name, 'issuer': issuer, 'issued_on': issuedOn == null ? null : _d(issuedOn!),
        'expires_on': expiresOn == null ? null : _d(expiresOn!), 'credential_url': credentialUrl,
      };
}

class NamedItem {
  NamedItem(this.id, this.name);
  final String id;
  final String name;
}

class Institution {
  Institution({required this.id, required this.name, this.shortName, this.city});
  final String id;
  final String name;
  final String? shortName;
  final String? city;
  factory Institution.fromJson(Map<String, dynamic> j) =>
      Institution(id: j['id'] as String, name: j['name'] as String, shortName: j['short_name'] as String?, city: j['city'] as String?);
  String get display => shortName == null ? name : '$name ($shortName)';
}

/// Everything shown on the profile screen in one object.
class FullProfile {
  FullProfile({required this.profile, required this.education, required this.skills, required this.interests,
      required this.experiences, required this.certifications, required this.completion});
  final Profile profile;
  final List<EducationRecord> education;
  final List<NamedItem> skills;
  final List<NamedItem> interests;
  final List<Experience> experiences;
  final List<Certification> certifications;
  final int completion;
}

String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String isoDate(DateTime d) => _d(d);
DateTime? parseDate(Object? v) => parseTs(v);

const provinces = ['Punjab', 'Sindh', 'Khyber Pakhtunkhwa', 'Balochistan', 'Islamabad Capital Territory', 'Gilgit-Baltistan', 'Azad Jammu and Kashmir'];
const educationLevels = ['matric', 'o_level', 'intermediate', 'a_level', 'diploma', 'bachelor', 'master', 'mphil', 'phd', 'other'];
const userCategories = ['student', 'graduate', 'job_seeker', 'entrepreneur', 'farmer', 'freelancer', 'other'];
const employmentStatuses = ['student', 'unemployed', 'employed_full_time', 'employed_part_time', 'self_employed', 'freelancing'];
const incomeRanges = ['below_25k', '25k_50k', '50k_100k', '100k_200k', 'above_200k'];
String pretty(String s) => s.replaceAll('_', ' ').replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
