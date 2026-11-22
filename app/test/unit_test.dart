import 'package:flutter_test/flutter_test.dart';
import 'package:mauqa/core/utils/formatters.dart';
import 'package:mauqa/core/utils/link_safety.dart';
import 'package:mauqa/core/utils/validators.dart';
import 'package:mauqa/data/models/activity.dart';
import 'package:mauqa/data/models/content.dart';
import 'package:mauqa/data/models/opportunity.dart';
import 'package:mauqa/data/models/profile.dart';
import 'package:mauqa/data/repositories/document_repository.dart';
import 'package:mauqa/data/repositories/opportunity_repository.dart';
import 'package:mauqa/features/calendar/ics.dart';
import 'package:mauqa/features/tools/cv_pdf.dart';

void main() {
  group('Validators', () {
    test('Pakistani phone numbers are normalised to E.164', () {
      expect(Validators.normalizePhone('0300 1234567'), '+923001234567');
      expect(Validators.normalizePhone('923001234567'), '+923001234567');
      expect(Validators.phonePk('03001234567'), isNull);
      expect(Validators.phonePk('0423456789'), isNotNull);
    });
    test('password, email, CNIC, CGPA', () {
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('longenough'), isNotNull);
      expect(Validators.password('longenough1'), isNull);
      expect(Validators.email('a@b.pk'), isNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.cnic(''), isNull, reason: 'CNIC is optional');
      expect(Validators.cnic('35202-1234567-1'), isNull);
      expect(Validators.cnic('3520212345671'), isNotNull);
      expect(Validators.cgpa('3.4'), isNull);
      expect(Validators.cgpa('4.5'), isNotNull);
      expect(Validators.score('900', '1100'), isNull);
      expect(Validators.score('1200', '1100'), isNotNull);
    });
  });

  group('Pakistan time', () {
    test('displays UTC deadlines in PKT', () {
      final utc = DateTime.utc(2026, 12, 15, 18, 59); // 23:59 PKT
      expect(Pkt.dateTime(utc), '15 Dec 2026, 11:59 PM PKT');
      expect(Pkt.date(DateTime.utc(2026, 12, 15, 20, 0)), '16 Dec 2026', reason: '20:00 UTC is already the next day in Pakistan');
    });
    test('days until uses Pakistan calendar days', () {
      final now = DateTime.utc(2026, 11, 21, 20, 0); // 01:00 on 22 Nov PKT
      expect(Pkt.daysUntil(DateTime.utc(2026, 11, 22, 18, 0), nowUtc: now), 0);
      expect(Pkt.daysUntil(DateTime.utc(2026, 11, 23, 18, 0), nowUtc: now), 1);
    });
    test('wall clock PKT → UTC', () {
      expect(Pkt.fromPktWallClock(2026, 12, 1, 9, 0), DateTime.utc(2026, 12, 1, 4, 0));
    });
    test('PKR formatting', () => expect(formatPkr(1500000), 'PKR 1,500,000'));
  });

  group('Link safety', () {
    test('official domains and subdomains pass', () {
      expect(checkLink('https://portal.hec.gov.pk/apply', officialDomains: ['hec.gov.pk']).ok, isTrue);
    });
    test('suspicious links are flagged', () {
      expect(checkLink('http://hec.gov.pk/x').ok, isFalse);
      expect(checkLink('https://bit.ly/x').ok, isFalse);
      expect(checkLink('https://wa.me/92300').ok, isFalse);
      expect(checkLink('https://hec-scholarship.com', officialDomains: ['hec.gov.pk']).flags, contains("Not on the organisation's official domain"));
      expect(checkLink(null).ok, isFalse);
    });
  });

  group('Search filters', () {
    test('only active filters are sent to the backend', () {
      const f = SearchFilters();
      expect(f.toRpcFilters(), isEmpty);
      expect(f.activeCount, 0);
      final g = f.copyWith(categories: ['scholarships'], provinces: ['Sindh'], verifiedOnly: true, age: 21);
      expect(g.toRpcFilters(), {'categories': ['scholarships'], 'provinces': ['Sindh'], 'age': 21, 'verified_only': true});
      expect(g.activeCount, 4);
      expect(g.copyWith(age: null).toRpcFilters().containsKey('age'), isFalse);
      expect(g.cleared().toRpcFilters(), isEmpty);
    });
  });

  group('Models', () {
    final feedRow = {
      'id': 'o1', 'title': 'Merit Scholarship', 'organization_id': 'g1', 'organization_name': 'Org', 'category_slug': 'scholarships',
      'category_name_en': 'Scholarships', 'category_name_ur': 'وظائف', 'deadline': '2026-12-15T18:59:00+00:00', 'is_nationwide': false,
      'provinces': ['Punjab'], 'cities': ['Lahore'], 'verification_status': 'verified', 'effective_status': 'open',
      'amount_min_pkr': 15000, 'funding_type': 'fully_funded', 'recurrence_key': 'merit-ug',
    };
    test('opportunity parses feed rows and round-trips through the offline cache', () {
      final o = Opportunity.fromJson(feedRow);
      expect(o.isVerified, isTrue);
      expect(o.location, 'Lahore, Punjab');
      expect(o.fundingLabel, 'Fully funded');
      expect(o.categoryName(true), 'وظائف');
      expect(o.recurrenceKey, 'merit-ug');
      final again = Opportunity.fromJson(o.toJson());
      expect(again.deadline, o.deadline);
      expect(again.title, o.title);
    });
    test('eligibility result accepts edge-function and stored shapes', () {
      final a = EligibilityResult.fromJson({
        'outcome': 'probably_eligible', 'score': 0.5, 'explanation': 'x', 'missingRequirements': ['Date of birth'],
        'matched': [{'label': 'CGPA', 'status': 'met', 'reason': 'ok', 'mandatory': true, 'type': 'cgpa_min'}],
        'unconfirmed': [{'label': 'Age', 'status': 'unknown', 'reason': '?', 'mandatory': true, 'type': 'age_range'}],
      });
      expect(a.missing, ['Date of birth']);
      expect(a.matched.single.type, 'cgpa_min');
      expect(EligibilityResult.fromJson({'outcome': 'eligible', 'missing_requirements': ['Document: cv'], 'explanation': ''}).missing, ['Document: cv']);
    });
    test('application title falls back to the snapshot when the listing is gone', () {
      final a = Application.fromJson({'id': 'a', 'status': 'applied', 'title_snapshot': 'Old listing', 'opportunity_id': null});
      expect(a.displayTitle, 'Old listing');
      expect(a.stage, applicationStatuses.indexOf('applied'));
    });
    test('education score labels', () {
      expect(EducationRecord(level: 'bachelor', scoreType: 'cgpa', scoreValue: 3.4, scoreMax: 4).scoreLabel, 'CGPA 3.40 / 4.0');
      expect(EducationRecord(level: 'intermediate', scoreType: 'percentage', scoreValue: 880, scoreMax: 1100).scoreLabel, '880 / 1100');
    });
  });

  group('Documents', () {
    test('validation of type and size', () {
      expect(DocumentRepository.validate('cv.pdf', 1000), isNull);
      expect(DocumentRepository.validate('photo.HEIC', 1000), 'docs.badType');
      expect(DocumentRepository.validate('big.pdf', maxDocumentBytes + 1), 'docs.tooLarge');
    });
  });

  group('CV PDF', () {
    test('latin1Safe maps punctuation and strips unsupported glyphs', () {
      expect(latin1Safe('2024 – 2026 “Top” • ok…'), '2024 - 2026 "Top" - ok...');
      expect(latin1Safe('Ali علی'), 'Ali ');
    });
    test('builds a valid PDF for every template', () async {
      for (final t in ['modern', 'classic', 'compact']) {
        final cv = CvData(name: 'Ayesha Khan', headline: 'BS CS', email: 'a@b.pk', summary: 'Motivated student.', template: t,
            education: [CvEntry(title: 'BS Computer Science', place: 'NUST', period: '2023 - 2027', details: 'CGPA 3.4\nDean’s list')],
            skills: ['Python', 'SQL']);
        final bytes = await buildCvPdf(cv);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      }
    });
  });

  group('Calendar export', () {
    test('produces RFC 5545 events in UTC with escaping and alarms', () {
      final ics = buildIcs([
        CalendarEvent(at: DateTime.utc(2026, 12, 15, 18, 59), type: 'interested_deadline', title: 'Merit, Scholarship; 2026', opportunityId: 'o1'),
      ], nowUtc: DateTime.utc(2026, 11, 21));
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('DTSTART:20261215T185900Z'));
      expect(ics, contains('SUMMARY:Deadline: Merit\\, Scholarship\\; 2026'));
      expect(ics, contains('TRIGGER:-P1D'));
      expect(ics.trim(), endsWith('END:VCALENDAR'));
      expect(RegExp('BEGIN:VEVENT').allMatches(ics).length, 1);
    });
  });
}
