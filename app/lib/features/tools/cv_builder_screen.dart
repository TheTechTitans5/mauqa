import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/l10n/strings.dart';
import '../../data/models/content.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import 'cv_pdf.dart';

/// Prefills the CV from the profile so users only polish wording.
CvData cvFromProfile(FullProfile p) => CvData(
      name: p.profile.fullName ?? '',
      email: p.profile.email ?? '',
      phone: p.profile.phone ?? '',
      city: [p.profile.city, p.profile.province].whereType<String>().join(', '),
      headline: p.education.isEmpty ? '' : '${pretty(p.education.first.level)} ${p.education.first.degreeProgram ?? ''}'.trim(),
      education: [
        for (final e in p.education)
          CvEntry(
            title: [pretty(e.level), e.degreeProgram].whereType<String>().join(' - '),
            place: e.institutionName ?? '',
            period: [e.startYear, e.graduationYear].whereType<int>().join(' - '),
            details: e.scoreLabel,
          ),
      ],
      experience: [
        for (final x in p.experiences)
          CvEntry(
            title: x.title,
            place: x.organization ?? '',
            period: '${x.startDate.year} - ${x.isCurrent ? 'Present' : x.endDate?.year ?? ''}',
            details: x.description ?? '',
          ),
      ],
      skills: p.skills.map((s) => s.name).toList(),
      certifications: p.certifications.map((c) => [c.name, c.issuer].whereType<String>().join(', ')).toList(),
    );

class CvBuilderScreen extends ConsumerStatefulWidget {
  const CvBuilderScreen({super.key});
  @override
  ConsumerState<CvBuilderScreen> createState() => _CvBuilderScreenState();
}

class _CvBuilderScreenState extends ConsumerState<CvBuilderScreen> {
  CvData? _cv;
  String? _id;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(contentRepositoryProvider).loadCv();
      var data = saved.data;
      if (saved.id == null) {
        final p = await ref.read(fullProfileProvider.future);
        data = cvFromProfile(p);
      }
      if (mounted) setState(() { _cv = data; _id = saved.id; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _cv = CvData(); _loading = false; });
        showSnack(context, 'Could not load your saved CV — starting a new one.', error: true);
      }
    }
  }

  Future<void> _save() async {
    final cv = _cv!;
    await runAction(context, () async => _id = await ref.read(contentRepositoryProvider).saveCv(_id, cv), success: context.t('common.saved'));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingList());
    final cv = _cv!;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('tools.cv')), actions: [
        IconButton(tooltip: 'Refill from profile', icon: const Icon(Icons.sync_rounded), onPressed: () async {
          final p = await ref.read(fullProfileProvider.future);
          setState(() => _cv = cvFromProfile(p)..template = cv.template);
        }),
        IconButton(tooltip: context.t('common.save'), icon: const Icon(Icons.save_outlined), onPressed: _save),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.picture_as_pdf_rounded),
        label: Text(context.t('tools.exportPdf')),
        onPressed: () async {
          await _save();
          final bytes = await buildCvPdf(cv);
          final name = cv.name.trim().isEmpty ? 'CV' : '${cv.name.trim().replaceAll(RegExp(r'\s+'), '-')}-CV';
          await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
        },
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'modern', label: Text('Modern')), ButtonSegment(value: 'classic', label: Text('Classic')),
            ButtonSegment(value: 'compact', label: Text('Compact'))],
          selected: {cv.template},
          onSelectionChanged: (v) => setState(() => cv.template = v.first),
        ),
        const SizedBox(height: 12),
        _Field('Full name', cv.name, (v) => cv.name = v),
        _Field('Headline', cv.headline, (v) => cv.headline = v, hint: 'BS Computer Science student | Data analysis'),
        _Field('Email', cv.email, (v) => cv.email = v),
        _Field('Phone', cv.phone, (v) => cv.phone = v),
        _Field('City', cv.city, (v) => cv.city = v),
        _Field('Profile summary', cv.summary, (v) => cv.summary = v, lines: 4, hint: '2–3 sentences: who you are, strengths, what you want next'),
        _EntryList(title: 'Education', entries: cv.education, onChanged: () => setState(() {})),
        _EntryList(title: 'Experience', entries: cv.experience, onChanged: () => setState(() {})),
        _Field('Skills (comma separated)', cv.skills.join(', '), (v) { cv.skills..clear()..addAll(v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)); }),
        _Field('Certifications (one per line)', cv.certifications.join('\n'), (v) { cv.certifications..clear()..addAll(v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty)); }, lines: 3),
        const InfoBanner(text: 'Tip: don’t include your CNIC number, photo or full home address unless the employer asks for them.'),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.initial, this.onChanged, {this.lines = 1, this.hint});
  final String label;
  final String initial;
  final void Function(String) onChanged;
  final int lines;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(initialValue: initial, maxLines: lines, onChanged: onChanged, decoration: InputDecoration(labelText: label, hintText: hint)),
      );
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.title, required this.entries, required this.onChanged});
  final String title;
  final List<CvEntry> entries;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              for (final (i, e) in entries.indexed)
                Container(
                  key: ObjectKey(e),
                  margin: const EdgeInsets.only(top: 10),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: TextFormField(initialValue: e.title, onChanged: (v) => e.title = v, decoration: const InputDecoration(labelText: 'Title'))),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { entries.removeAt(i); onChanged(); }),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(initialValue: e.place, onChanged: (v) => e.place = v, decoration: const InputDecoration(labelText: 'Organisation / institution')),
                    const SizedBox(height: 8),
                    TextFormField(initialValue: e.period, onChanged: (v) => e.period = v, decoration: const InputDecoration(labelText: 'Period')),
                    const SizedBox(height: 8),
                    TextFormField(initialValue: e.details, maxLines: 3, onChanged: (v) => e.details = v, decoration: const InputDecoration(labelText: 'Details (one point per line)')),
                  ]),
                ),
              TextButton.icon(onPressed: () { entries.add(CvEntry()); onChanged(); }, icon: const Icon(Icons.add), label: Text('Add ${title.toLowerCase()}')),
            ]),
          ),
        ),
      );
}
