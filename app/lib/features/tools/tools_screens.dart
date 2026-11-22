import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/content.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class ToolsHubScreen extends StatelessWidget {
  const ToolsHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final tools = [
      (Icons.description_rounded, context.t('tools.cv'), 'Build a clean CV and export it as PDF', '/tools/cv', AppColors.tealGradient),
      (Icons.mail_rounded, context.t('tools.cover'), 'Templates for jobs, internships and scholarships', '/tools/cover-letter', AppColors.lavenderGradient),
      (Icons.checklist_rounded, context.t('tools.readiness'), 'See how ready your profile and documents are', '/tools/readiness', AppColors.amberGradient),
      (Icons.record_voice_over_rounded, context.t('tools.interview'), 'Common questions with guidance', '/tools/interview', AppColors.lavenderGradient),
      (Icons.menu_book_rounded, context.t('tools.guides'), 'Scholarship, internship, SOP, CV and test guides', '/tools/guides', AppColors.tealGradient),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('tools.title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        for (final (i, t) in tools.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: EntranceFade(
              index: i,
              child: TiltCard(
                child: GlassCard(
                  onTap: () => context.push(t.$4),
                  child: Row(children: [
                    Container(width: 56, height: 56, decoration: BoxDecoration(gradient: LinearGradient(colors: t.$5), borderRadius: BorderRadius.circular(18)),
                        child: Icon(t.$1, color: Colors.white)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.$2, style: Theme.of(context).textTheme.titleMedium),
                      Text(t.$3, style: Theme.of(context).textTheme.bodySmall),
                    ])),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

const _guideCategories = {
  null: 'All', 'scholarship': 'Scholarships', 'internship': 'Internships', 'job': 'Jobs', 'government_scheme': 'Government schemes',
  'cv': 'CV', 'interview': 'Interviews', 'statement_of_purpose': 'SOP', 'personal_statement': 'Personal statement',
  'aptitude_test': 'Aptitude tests', 'entry_test': 'Entry tests', 'english': 'English', 'digital_skills': 'Digital skills',
  'free_courses': 'Free courses', 'certification': 'Certifications', 'tips': 'Tips', 'faq': 'FAQ',
};

class GuidesScreen extends ConsumerStatefulWidget {
  const GuidesScreen({super.key, this.category});
  final String? category;
  @override
  ConsumerState<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends ConsumerState<GuidesScreen> {
  late String? _cat = widget.category;
  @override
  Widget build(BuildContext context) {
    final guides = ref.watch(guidesProvider(_cat));
    return Scaffold(
      appBar: AppBar(title: Text(context.t('tools.guides'))),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final e in _guideCategories.entries)
              Padding(padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(label: Text(e.value), selected: _cat == e.key, onSelected: (_) => setState(() => _cat = e.key))),
          ]),
        ),
        Expanded(
          child: AsyncView<List<Guide>>(
            value: guides,
            onRetry: () => ref.invalidate(guidesProvider(_cat)),
            data: (list) => list.isEmpty
                ? EmptyState(message: context.t('common.none'), icon: Icons.menu_book_rounded)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => GlassCard(
                      onTap: () => context.push('/tools/guides/${list[i].slug}'),
                      child: Row(children: [
                        const Icon(Icons.article_outlined, color: AppColors.teal),
                        const SizedBox(width: 12),
                        Expanded(child: Text(list[i].title(context.isUrdu), style: Theme.of(context).textTheme.titleSmall)),
                        Pill(_guideCategories[list[i].category] ?? list[i].category),
                      ]),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

class GuideDetailScreen extends ConsumerWidget {
  const GuideDetailScreen({super.key, required this.slug});
  final String slug;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(guidesProvider(null));
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView<List<Guide>>(
        value: all,
        onRetry: () => ref.invalidate(guidesProvider(null)),
        data: (list) {
          final g = list.where((x) => x.slug == slug).firstOrNull;
          if (g == null) return EmptyState(message: context.t('common.none'));
          final ur = context.isUrdu;
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text(g.title(ur), style: Theme.of(context).textTheme.headlineSmall),
            if (ur && g.bodyUr == null) const InfoBanner(text: 'Urdu version coming soon — showing English.'),
            const SizedBox(height: 16),
            SelectableText(g.body(ur), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
          ]);
        },
      ),
    );
  }
}

final _questionsProvider = FutureProvider.autoDispose<List<InterviewQuestion>>((ref) => ref.watch(contentRepositoryProvider).interviewQuestions());

class InterviewPrepScreen extends ConsumerStatefulWidget {
  const InterviewPrepScreen({super.key});
  @override
  ConsumerState<InterviewPrepScreen> createState() => _InterviewPrepScreenState();
}

class _InterviewPrepScreenState extends ConsumerState<InterviewPrepScreen> {
  int _i = 0;
  bool _reveal = false;
  String? _cat;

  @override
  Widget build(BuildContext context) {
    final qs = ref.watch(_questionsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('tools.interview'))),
      body: AsyncView<List<InterviewQuestion>>(
        value: qs,
        onRetry: () => ref.invalidate(_questionsProvider),
        data: (all) {
          final list = _cat == null ? all : all.where((q) => q.category == _cat).toList();
          if (list.isEmpty) return EmptyState(message: context.t('common.none'));
          final q = list[_i % list.length];
          return ListView(padding: const EdgeInsets.all(20), children: [
            Wrap(spacing: 8, children: [
              for (final c in const [null, 'general', 'scholarship', 'internship', 'behavioural', 'technical'])
                ChoiceChip(label: Text(c == null ? 'All' : pretty(c)), selected: _cat == c, onSelected: (_) => setState(() { _cat = c; _i = 0; _reveal = false; })),
            ]),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: GlassCard(
                key: ValueKey('${_cat}_$_i'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Question ${(_i % list.length) + 1} of ${list.length}', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  Text(context.isUrdu && q.questionUr != null ? q.questionUr! : q.questionEn, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  if (_reveal && q.guidanceEn != null) InfoBanner(text: q.guidanceEn!, color: AppColors.teal, icon: Icons.lightbulb_outline)
                  else TextButton.icon(onPressed: () => setState(() => _reveal = true), icon: const Icon(Icons.lightbulb_outline), label: const Text('Show guidance')),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => setState(() { _i = (_i - 1 + list.length) % list.length; _reveal = false; }), child: const Text('Previous'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: () => setState(() { _i = (_i + 1) % list.length; _reveal = false; }), child: const Text('Next'))),
            ]),
            const SizedBox(height: 16),
            TextButton(onPressed: () => context.push('/tools/guides?category=interview'), child: const Text('Read the interview preparation guide')),
          ]);
        },
      ),
    );
  }
}

const _coverTemplates = {
  'job': '''Dear Hiring Manager,

I am writing to apply for the {role} position at {org}. I recently {education}, and I am keen to bring my skills in {skills} to your team.

In my previous experience, I {achievement}. I believe this has prepared me to contribute from the first day.

I would welcome the opportunity to discuss how I can support {org}. Thank you for your time and consideration.

Sincerely,
{name}''',
  'internship': '''Dear {org} Team,

I am a {education} student and would like to apply for the {role} internship. I am particularly interested in this opportunity because {motivation}.

Through my coursework and projects, I have developed {skills}. During this internship, I hope to learn from your team while contributing to real work.

Thank you for considering my application.

Kind regards,
{name}''',
  'scholarship': '''Dear Selection Committee,

I am applying for the {role}. I am currently {education}, and this scholarship would allow me to {motivation}.

Despite {challenge}, I have {achievement}. I plan to use what I learn to give back to my community in Pakistan.

Thank you for considering my application.

Respectfully,
{name}''',
};

class CoverLetterScreen extends ConsumerStatefulWidget {
  const CoverLetterScreen({super.key, this.opportunityId});
  final String? opportunityId;
  @override
  ConsumerState<CoverLetterScreen> createState() => _CoverLetterScreenState();
}

class _CoverLetterScreenState extends ConsumerState<CoverLetterScreen> {
  String _template = 'job';
  String? _editingId;
  final _title = TextEditingController(text: 'Cover letter');
  final _body = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _fill(FullProfile? p, String? role, String? org) {
    final edu = p?.education.isEmpty ?? true ? null : p!.education.first;
    var t = _coverTemplates[_template]!;
    final values = {
      'name': p?.profile.fullName ?? '[Your name]',
      'role': role ?? '[role / programme]',
      'org': org ?? '[organisation]',
      'education': edu == null ? '[your education]' : '${pretty(edu.level)}${edu.degreeProgram != null ? ' in ${edu.degreeProgram}' : ''}${edu.institutionName != null ? ' at ${edu.institutionName}' : ''}',
      'skills': (p?.skills.isEmpty ?? true) ? '[your key skills]' : p!.skills.take(3).map((s) => s.name).join(', '),
      'achievement': '[a specific achievement with a result]',
      'motivation': '[why this opportunity matters to you]',
      'challenge': '[a challenge you overcame]',
    };
    values.forEach((k, v) => t = t.replaceAll('{$k}', v));
    _body.text = t;
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(fullProfileProvider).valueOrNull;
    final opp = widget.opportunityId == null ? null : ref.watch(opportunityDetailProvider(widget.opportunityId!)).valueOrNull?.base;
    final saved = ref.watch(_lettersProvider);
    if (!_filled && p != null) {
      _filled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _fill(p, opp?.title, opp?.organizationName)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.t('tools.cover')), actions: [
        IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy_rounded), onPressed: () async {
          await Clipboard.setData(ClipboardData(text: _body.text));
          if (context.mounted) showSnack(context, 'Copied');
        }),
        IconButton(tooltip: context.t('opp.share'), icon: const Icon(Icons.share_outlined), onPressed: () => Share.share(_body.text)),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'job', label: Text('Job')), ButtonSegment(value: 'internship', label: Text('Internship')),
            ButtonSegment(value: 'scholarship', label: Text('Scholarship'))],
          selected: {_template},
          onSelectionChanged: (v) => setState(() { _template = v.first; _fill(p, opp?.title, opp?.organizationName); }),
        ),
        const SizedBox(height: 12),
        const InfoBanner(text: 'Replace every [bracketed] part with your own specific details. Generic letters are easy to spot.'),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 12),
        TextField(controller: _body, maxLines: 18, decoration: const InputDecoration(alignLabelWithHint: true, labelText: 'Letter')),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.save_outlined),
          label: Text(context.t('common.save')),
          onPressed: () async {
            if (_body.text.trim().isEmpty) return;
            if (await runAction(context, () => ref.read(contentRepositoryProvider).saveCoverLetter(
                  id: _editingId, title: _title.text.trim().isEmpty ? 'Cover letter' : _title.text.trim(), template: _template,
                  body: _body.text, opportunityId: widget.opportunityId), success: context.t('common.saved'))) {
              ref.invalidate(_lettersProvider);
            }
          },
        ),
        const SizedBox(height: 20),
        if ((saved.valueOrNull ?? const []).isNotEmpty) Text('My letters', style: Theme.of(context).textTheme.titleMedium),
        for (final l in saved.valueOrNull ?? const <Map<String, dynamic>>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline),
            title: Text(l['title'] as String),
            subtitle: Text(l['template'] as String),
            onTap: () => setState(() { _editingId = l['id'] as String; _title.text = l['title'] as String; _body.text = l['body'] as String; _template = l['template'] as String; }),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
              if (await runAction(context, () => ref.read(contentRepositoryProvider).deleteCoverLetter(l['id'] as String))) ref.invalidate(_lettersProvider);
            }),
          ),
      ]),
    );
  }
}

final _lettersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(contentRepositoryProvider).coverLetters());

/// Application readiness: profile completeness, documents and (optionally) one opportunity's requirements.
class ReadinessScreen extends ConsumerWidget {
  const ReadinessScreen({super.key, this.opportunityId});
  final String? opportunityId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(fullProfileProvider).valueOrNull;
    final docs = ref.watch(documentsProvider).valueOrNull;
    final opp = opportunityId == null ? null : ref.watch(opportunityDetailProvider(opportunityId!)).valueOrNull;
    final elig = opportunityId == null ? null : ref.watch(eligibilityProvider(opportunityId!)).valueOrNull;
    if (p == null || docs == null) return Scaffold(appBar: AppBar(), body: const LoadingList());

    final have = docs.map((d) => d.category).toSet();
    final checks = <(String, bool, String)>[
      ('Profile at least 80% complete', p.completion >= 80, '/profile/edit'),
      ('Education added with marks/CGPA', p.education.any((e) => e.scoreValue != null), '/profile/edit?section=education'),
      ('At least 3 skills', p.skills.length >= 3, '/profile/edit?section=skills'),
      ('CV uploaded', have.contains('cv'), '/documents'),
      ('CNIC / B-Form uploaded', have.contains('cnic'), '/documents'),
      ('Transcript uploaded', have.contains('transcript'), '/documents'),
      if (opp != null)
        for (final r in opp.documents.where((r) => r.isMandatory)) ('Required: ${r.label}', have.contains(r.category), '/documents?opportunityId=${opp.base.id}'),
      if (elig != null) ('Eligibility: ${elig.outcome.replaceAll('_', ' ')}', elig.outcome == 'eligible', '/opportunity/${opp?.base.id}/eligibility'),
    ];
    final score = checks.isEmpty ? 0.0 : checks.where((c) => c.$2).length / checks.length;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('tools.readiness'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        GlassCard(child: Row(children: [
          ProgressRing(value: score, size: 90),
          const SizedBox(width: 16),
          Expanded(child: Text(opp == null ? 'Overall application readiness' : 'Readiness for ${opp.base.title}', style: Theme.of(context).textTheme.titleMedium)),
        ])),
        const SizedBox(height: 12),
        for (final c in checks)
          Card(
            child: ListTile(
              leading: Icon(c.$2 ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: c.$2 ? AppColors.success : AppColors.coral),
              title: Text(c.$1),
              trailing: c.$2 ? null : const Icon(Icons.chevron_right_rounded),
              onTap: c.$2 ? null : () => context.push(c.$3),
            ),
          ),
      ]),
    );
  }
}

