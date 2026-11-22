import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/content.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../core/utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t('community.title')),
          bottom: TabBar(tabs: [
            Tab(text: context.t('community.stories')),
            Tab(text: context.t('community.mentors')),
            const Tab(text: 'Submit')
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/community/new'),
          icon: const Icon(Icons.edit_rounded),
          label: Text(context.t('community.share')),
        ),
        body: TabBarView(
            children: [_Stories(), _Mentors(), const _SubmitOpportunity()]),
      ),
    );
  }
}

class _Stories extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AsyncView<List<SuccessStory>>(
        value: ref.watch(storiesProvider),
        onRetry: () => ref.invalidate(storiesProvider),
        data: (list) => list.isEmpty
            ? EmptyState(
                message: context.t('common.none'),
                icon: Icons.emoji_events_rounded)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final s = list[i];
                  return GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Pill(s.type, color: AppColors.lavender),
                            if (s.isDemo)
                              const Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Pill('DEMO', color: Colors.grey)),
                            if (s.status != 'approved')
                              Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child:
                                      Pill(s.status, color: AppColors.warning)),
                            const Spacer(),
                            PopupMenuButton<String>(
                              onSelected: (_) =>
                                  _reportStory(context, ref, s.id),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'report',
                                    child: Text(
                                        context.t('community.reportStory')))
                              ],
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text(s.title,
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              '${s.author}${s.institution != null ? ' · ${s.institution}' : ''}${s.publishedAt != null ? ' · ${Pkt.date(s.publishedAt)}' : ''}',
                              style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 8),
                          Text(s.body),
                        ]),
                  );
                },
              ),
      );
}

Future<void> _reportStory(
    BuildContext context, WidgetRef ref, String id) async {
  String reason = 'inappropriate';
  final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
          builder: (d, set) => AlertDialog(
                title: Text(context.t('community.reportStory')),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final r in const [
                    'inappropriate',
                    'spam',
                    'misleading',
                    'personal_information',
                    'other'
                  ])
                    RadioListTile<String>(
                        value: r,
                        groupValue: reason,
                        title: Text(r.replaceAll('_', ' ')),
                        onChanged: (v) => set(() => reason = v!)),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: Text(context.t('common.cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: Text(context.t('opp.report'))),
                ],
              )));
  if (ok == true && context.mounted) {
    await runAction(context,
        () => ref.read(contentRepositoryProvider).reportStory(id, reason, null),
        success: context.t('report.sent'));
  }
}

class _Mentors extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncView<List<Mentor>>(
        value: ref.watch(mentorsProvider),
        onRetry: () => ref.invalidate(mentorsProvider),
        data: (list) => list.isEmpty
            ? EmptyState(
                message:
                    'The mentorship directory opens once mentors are approved.',
                icon: Icons.groups_rounded)
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final m in list)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          child: Text(m.name.isEmpty ? '?' : m.name[0])),
                      title: Text(m.name),
                      subtitle: Text([
                        m.institution,
                        m.expertise.join(', '),
                        m.bio
                      ]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join('\n')),
                      isThreeLine: true,
                      trailing: m.contactUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => launchUrl(
                                  Uri.parse(m.contactUrl!),
                                  mode: LaunchMode.externalApplication)),
                    ),
                  ),
              ]),
      );
}

/// Lets organisations / users submit an opportunity for review (never published without verification).
class _SubmitOpportunity extends ConsumerStatefulWidget {
  const _SubmitOpportunity();
  @override
  ConsumerState<_SubmitOpportunity> createState() => _SubmitOpportunityState();
}

class _SubmitOpportunityState extends ConsumerState<_SubmitOpportunity> {
  final _form = GlobalKey<FormState>();
  final _org = TextEditingController();
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _apply = TextEditingController();
  final _desc = TextEditingController();
  @override
  void dispose() {
    for (final c in [_org, _title, _url, _apply, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const InfoBanner(
                  text:
                      'Know an opportunity we are missing? Submit the official link. Our team verifies it before it appears.'),
              TextFormField(
                  controller: _org,
                  decoration: const InputDecoration(labelText: 'Organisation'),
                  validator: (v) => Validators.required(v)),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _title,
                  decoration:
                      const InputDecoration(labelText: 'Opportunity title'),
                  validator: (v) => Validators.required(v)),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _url,
                  decoration: const InputDecoration(
                      labelText: 'Official announcement link'),
                  validator: (v) => Validators.httpsUrl(v, optional: false)),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _apply,
                  decoration: const InputDecoration(
                      labelText: 'Official application link (optional)'),
                  validator: (v) => Validators.httpsUrl(v)),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _desc,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(labelText: 'Short description')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (!_form.currentState!.validate()) return;
                  if (await runAction(
                      context,
                      () => ref
                              .read(engagementRepositoryProvider)
                              .submitOpportunity(
                                  org: _org.text.trim(),
                                  title: _title.text.trim(),
                                  sourceUrl: _url.text.trim(),
                                  payload: {
                                'description': _desc.text.trim(),
                                'official_application_url':
                                    _apply.text.trim().isEmpty
                                        ? null
                                        : _apply.text.trim()
                              }),
                      success: context.t('community.pending'))) {
                    _form.currentState!.reset();
                    for (final c in [_org, _title, _url, _apply, _desc]) {
                      c.clear();
                    }
                  }
                },
                child: const Text('Submit for review'),
              ),
            ]),
      );
}

class SubmitStoryScreen extends ConsumerStatefulWidget {
  const SubmitStoryScreen({super.key});
  @override
  ConsumerState<SubmitStoryScreen> createState() => _SubmitStoryScreenState();
}

class _SubmitStoryScreenState extends ConsumerState<SubmitStoryScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _inst = TextEditingController();
  String _type = 'scholarship';
  @override
  void dispose() {
    for (final c in [_name, _title, _body, _inst]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.t('community.share'))),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const InfoBanner(
                text:
                    'Stories are reviewed before publishing. Don’t include phone numbers, CNIC or other personal details.'),
            TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Display name (e.g. Ayesha K.)'),
                validator: (v) => Validators.required(v)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(
                    value: 'scholarship', child: Text('Scholarship')),
                DropdownMenuItem(
                    value: 'internship', child: Text('Internship')),
                DropdownMenuItem(value: 'job', child: Text('Job')),
                DropdownMenuItem(
                    value: 'fellowship', child: Text('Fellowship')),
                DropdownMenuItem(
                    value: 'alumni', child: Text('Alumni experience')),
                DropdownMenuItem(value: 'tip', child: Text('Application tip')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
                controller: _inst,
                decoration:
                    const InputDecoration(labelText: 'Institution (optional)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'At least 5 characters'
                    : null),
            const SizedBox(height: 12),
            TextFormField(
                controller: _body,
                maxLines: 10,
                maxLength: 8000,
                decoration: const InputDecoration(
                    labelText: 'Your story', alignLabelWithHint: true),
                validator: (v) => (v == null || v.trim().length < 50)
                    ? 'At least 50 characters'
                    : null),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (!_form.currentState!.validate()) return;
                if (await runAction(
                        context,
                        () => ref.read(contentRepositoryProvider).submitStory(
                            displayName: _name.text.trim(),
                            title: _title.text.trim(),
                            body: _body.text.trim(),
                            type: _type,
                            institution: _inst.text.trim().isEmpty
                                ? null
                                : _inst.text.trim()),
                        success: context.t('community.pending')) &&
                    context.mounted) {
                  ref.invalidate(storiesProvider);
                  context.pop();
                }
              },
              child: const Text('Submit for review'),
            ),
          ]),
        ),
      );
}
