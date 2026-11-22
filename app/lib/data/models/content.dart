import '../../core/utils/formatters.dart';

class Guide {
  Guide({required this.slug, required this.category, required this.titleEn, this.titleUr, required this.bodyEn, this.bodyUr});
  final String slug;
  final String category;
  final String titleEn;
  final String? titleUr;
  final String bodyEn;
  final String? bodyUr;
  String title(bool ur) => ur && (titleUr?.isNotEmpty ?? false) ? titleUr! : titleEn;
  String body(bool ur) => ur && (bodyUr?.isNotEmpty ?? false) ? bodyUr! : bodyEn;
  factory Guide.fromJson(Map<String, dynamic> j) => Guide(
      slug: j['slug'] as String, category: j['category'] as String, titleEn: j['title_en'] as String,
      titleUr: j['title_ur'] as String?, bodyEn: j['body_en'] as String, bodyUr: j['body_ur'] as String?);
}

class InterviewQuestion {
  InterviewQuestion({required this.category, required this.questionEn, this.questionUr, this.guidanceEn});
  final String category;
  final String questionEn;
  final String? questionUr;
  final String? guidanceEn;
  factory InterviewQuestion.fromJson(Map<String, dynamic> j) => InterviewQuestion(
      category: j['category'] as String, questionEn: j['question_en'] as String,
      questionUr: j['question_ur'] as String?, guidanceEn: j['guidance_en'] as String?);
}

class SuccessStory {
  SuccessStory({required this.id, required this.author, required this.title, required this.body, required this.type,
      this.institution, required this.status, this.publishedAt, this.isDemo = false});
  final String id;
  final String author;
  final String title;
  final String body;
  final String type;
  final String? institution;
  final String status;
  final DateTime? publishedAt;
  final bool isDemo;
  factory SuccessStory.fromJson(Map<String, dynamic> j) => SuccessStory(
      id: j['id'] as String, author: j['author_display_name'] as String, title: j['title'] as String, body: j['body'] as String,
      type: j['story_type'] as String, institution: j['institution_name'] as String?, status: j['status'] as String,
      publishedAt: parseTs(j['published_at']), isDemo: j['is_demo'] == true);
}

class Mentor {
  Mentor({required this.id, required this.name, required this.expertise, this.institution, this.bio, this.contactUrl});
  final String id;
  final String name;
  final List<String> expertise;
  final String? institution;
  final String? bio;
  final String? contactUrl;
  factory Mentor.fromJson(Map<String, dynamic> j) => Mentor(
      id: j['id'] as String, name: j['display_name'] as String,
      expertise: (j['expertise'] as List?)?.map((e) => e.toString()).toList() ?? [],
      institution: j['institution_name'] as String?, bio: j['bio'] as String?, contactUrl: j['contact_url'] as String?);
}

class Forecast {
  Forecast({required this.recurrenceKey, required this.cycles, this.nextOpening, this.nextDeadline});
  final String recurrenceKey;
  final int cycles;
  final DateTime? nextOpening;
  final DateTime? nextDeadline;
  factory Forecast.fromJson(Map<String, dynamic> j) => Forecast(
      recurrenceKey: j['recurrence_key'] as String, cycles: (j['cycles_observed'] as num).toInt(),
      nextOpening: parseTs(j['estimated_next_opening']), nextDeadline: parseTs(j['estimated_next_deadline']));
}

/// CV builder data, stored as JSON in cv_documents.data.
class CvData {
  CvData({this.name = '', this.headline = '', this.email = '', this.phone = '', this.city = '', this.summary = '',
      List<CvEntry>? education, List<CvEntry>? experience, List<String>? skills, List<String>? certifications, this.template = 'modern'})
      : education = education ?? [],
        experience = experience ?? [],
        skills = skills ?? [],
        certifications = certifications ?? [];
  String name, headline, email, phone, city, summary, template;
  final List<CvEntry> education;
  final List<CvEntry> experience;
  final List<String> skills;
  final List<String> certifications;

  Map<String, dynamic> toJson() => {
        'name': name, 'headline': headline, 'email': email, 'phone': phone, 'city': city, 'summary': summary,
        'education': education.map((e) => e.toJson()).toList(), 'experience': experience.map((e) => e.toJson()).toList(),
        'skills': skills, 'certifications': certifications,
      };
  factory CvData.fromJson(Map<String, dynamic> j, {String template = 'modern'}) => CvData(
        name: (j['name'] ?? '') as String, headline: (j['headline'] ?? '') as String, email: (j['email'] ?? '') as String,
        phone: (j['phone'] ?? '') as String, city: (j['city'] ?? '') as String, summary: (j['summary'] ?? '') as String,
        education: ((j['education'] as List?) ?? []).map((e) => CvEntry.fromJson((e as Map).cast<String, dynamic>())).toList(),
        experience: ((j['experience'] as List?) ?? []).map((e) => CvEntry.fromJson((e as Map).cast<String, dynamic>())).toList(),
        skills: ((j['skills'] as List?) ?? []).map((e) => e.toString()).toList(),
        certifications: ((j['certifications'] as List?) ?? []).map((e) => e.toString()).toList(),
        template: template,
      );
}

class CvEntry {
  CvEntry({this.title = '', this.place = '', this.period = '', this.details = ''});
  String title, place, period, details;
  Map<String, dynamic> toJson() => {'title': title, 'place': place, 'period': period, 'details': details};
  factory CvEntry.fromJson(Map<String, dynamic> j) => CvEntry(
      title: (j['title'] ?? '') as String, place: (j['place'] ?? '') as String,
      period: (j['period'] ?? '') as String, details: (j['details'] ?? '') as String);
}
