import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/content.dart';

/// The built-in PDF fonts cover Latin-1 only; map common punctuation and drop unsupported characters.
String latin1Safe(String s) => s
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll('•', '-')
    .replaceAll('…', '...')
    .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'), '');

/// Builds the CV PDF for the selected template. Pure function: no Flutter UI dependencies.
Future<Uint8List> buildCvPdf(CvData cv) async {
  final accent = switch (cv.template) {
    'classic' => PdfColor.fromHex('#101D35'),
    'compact' => PdfColor.fromHex('#7966D9'),
    _ => PdfColor.fromHex('#16B8A6'),
  };
  final compact = cv.template == 'compact';
  final base = compact ? 9.5 : 10.5;
  String t(String s) => latin1Safe(s.trim());

  pw.Widget heading(String text) => pw.Padding(
        padding: pw.EdgeInsets.only(top: compact ? 8 : 14, bottom: 4),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(text.toUpperCase(), style: pw.TextStyle(fontSize: base + 1, fontWeight: pw.FontWeight.bold, color: accent, letterSpacing: 1)),
          pw.Container(height: 1.2, color: accent, margin: const pw.EdgeInsets.only(top: 2)),
        ]),
      );

  pw.Widget entry(CvEntry e) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Expanded(child: pw.Text(t(e.title), style: pw.TextStyle(fontSize: base, fontWeight: pw.FontWeight.bold))),
            if (e.period.trim().isNotEmpty) pw.Text(t(e.period), style: pw.TextStyle(fontSize: base - 1, color: PdfColors.grey700)),
          ]),
          if (e.place.trim().isNotEmpty) pw.Text(t(e.place), style: pw.TextStyle(fontSize: base - 0.5, fontStyle: pw.FontStyle.italic)),
          if (e.details.trim().isNotEmpty)
            for (final line in e.details.split('\n').where((l) => l.trim().isNotEmpty))
              pw.Bullet(text: t(line.replaceFirst(RegExp(r'^[-*•]\s*'), '')), style: pw.TextStyle(fontSize: base - 0.5)),
        ]),
      );

  final contact = [cv.email, cv.phone, cv.city].map(t).where((s) => s.isNotEmpty).join('  |  ');
  final doc = pw.Document(title: '${t(cv.name)} CV', author: t(cv.name), creator: 'Mauqa');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.all(compact ? 28 : 40),
    build: (ctx) => [
      if (cv.template == 'modern')
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(t(cv.name), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            if (cv.headline.trim().isNotEmpty) pw.Text(t(cv.headline), style: const pw.TextStyle(fontSize: 12, color: PdfColors.white)),
            if (contact.isNotEmpty) pw.Text(contact, style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.white)),
          ]),
        )
      else
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text(t(cv.name), style: pw.TextStyle(fontSize: compact ? 18 : 22, fontWeight: pw.FontWeight.bold, color: accent)),
          if (cv.headline.trim().isNotEmpty) pw.Text(t(cv.headline), style: pw.TextStyle(fontSize: base + 1)),
          if (contact.isNotEmpty) pw.Text(contact, style: pw.TextStyle(fontSize: base - 1, color: PdfColors.grey700)),
        ]),
      if (cv.summary.trim().isNotEmpty) ...[heading('Profile'), pw.Text(t(cv.summary), style: pw.TextStyle(fontSize: base, lineSpacing: 2))],
      if (cv.education.isNotEmpty) ...[heading('Education'), for (final e in cv.education) entry(e)],
      if (cv.experience.isNotEmpty) ...[heading('Experience'), for (final e in cv.experience) entry(e)],
      if (cv.skills.isNotEmpty) ...[heading('Skills'), pw.Text(cv.skills.map(t).join('  -  '), style: pw.TextStyle(fontSize: base))],
      if (cv.certifications.isNotEmpty) ...[heading('Certifications'), for (final c in cv.certifications) pw.Bullet(text: t(c), style: pw.TextStyle(fontSize: base))],
    ],
  ));
  return doc.save();
}
