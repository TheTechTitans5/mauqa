import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../../data/models/profile.dart' show isoDate, pretty;
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key, this.checklistFor});
  /// When set, shows the required-document checklist for this opportunity.
  final String? checklistFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('docs.title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _upload(context, ref),
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(context.t('docs.upload')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(documentsProvider),
        child: AsyncView<List<UserDocument>>(
          value: docs,
          onRetry: () => ref.invalidate(documentsProvider),
          data: (list) {
            final have = list.map((d) => d.category).toSet();
            final done = commonDocuments.where(have.contains).length;
            return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
              InfoBanner(text: context.t('docs.private'), color: AppColors.teal, icon: Icons.lock_rounded),
              GlassCard(
                child: Row(children: [
                  ProgressRing(value: done / commonDocuments.length, size: 64, label: '$done/${commonDocuments.length}'),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.t('docs.completeness', {'n': done, 'total': commonDocuments.length}), style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final c in commonDocuments)
                        Pill(pretty(c), color: have.contains(c) ? AppColors.success : Colors.grey, icon: have.contains(c) ? Icons.check : Icons.close),
                    ]),
                  ])),
                ]),
              ),
              if (checklistFor != null) _OpportunityChecklist(opportunityId: checklistFor!, have: have),
              const SizedBox(height: 12),
              if (list.isEmpty) EmptyState(message: context.t('docs.empty'), icon: Icons.folder_open_rounded),
              for (final d in list) _DocTile(d: d),
            ]);
          },
        ),
      ),
    );
  }
}

class _OpportunityChecklist extends ConsumerWidget {
  const _OpportunityChecklist({required this.opportunityId, required this.have});
  final String opportunityId;
  final Set<String> have;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(opportunityDetailProvider(opportunityId)).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${context.t('tools.checklist')}: ${d.base.title}', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (d.documents.isEmpty) const Text('No document list published for this opportunity. Check the official announcement.'),
          for (final r in d.documents)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: have.contains(r.category),
              onChanged: null,
              title: Text(r.label),
              subtitle: Text(r.isMandatory ? context.t('common.required') : context.t('common.optional')),
            ),
        ]),
      ),
    );
  }
}

class _DocTile extends ConsumerWidget {
  const _DocTile({required this.d});
  final UserDocument d;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isImage = d.mimeType.startsWith('image/');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: fade(AppColors.teal, 0.15),
            child: Icon(isImage ? Icons.image_outlined : d.mimeType == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined, color: AppColors.teal),
          ),
          title: Text(d.title),
          subtitle: Text([
            pretty(d.category),
            '${(d.sizeBytes / 1024).toStringAsFixed(0)} KB',
            if (d.expiresOn != null) 'expires ${Pkt.date(d.expiresOn)}',
          ].join(' · '), style: TextStyle(color: d.isExpiringSoon ? AppColors.coral : null)),
          onTap: () => _open(context, ref, d),
          trailing: PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'open') await _open(context, ref, d);
              if (v == 'replace' && context.mounted) await _upload(context, ref, replacing: d);
              if (v == 'delete' && context.mounted) {
                if (!await confirmDialog(context, title: '${context.t('common.delete')} "${d.title}"?', destructive: true)) return;
                if (context.mounted && await runAction(context, () => ref.read(documentRepositoryProvider).delete(d), success: context.t('common.removed'))) {
                  ref.invalidate(documentsProvider);
                  ref.invalidate(fullProfileProvider);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: Text(context.t('docs.download'))),
              PopupMenuItem(value: 'replace', child: Text(context.t('docs.replace'))),
              PopupMenuItem(value: 'delete', child: Text(context.t('common.delete'))),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, WidgetRef ref, UserDocument d) async {
  try {
    final url = await ref.read(documentRepositoryProvider).signedUrl(d);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not open the document', error: true);
  }
}

Future<void> _upload(BuildContext context, WidgetRef ref, {UserDocument? replacing}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _UploadSheet(replacing: replacing),
  );
  if (done == true) {
    ref.invalidate(documentsProvider);
    ref.invalidate(fullProfileProvider);
  }
}

class _UploadSheet extends ConsumerStatefulWidget {
  const _UploadSheet({this.replacing});
  final UserDocument? replacing;
  @override
  ConsumerState<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<_UploadSheet> {
  late String _category = widget.replacing?.category ?? 'cv';
  late final _title = TextEditingController(text: widget.replacing?.title ?? '');
  DateTime? _expires;
  PlatformFile? _file;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _expires = widget.replacing?.expiresOn;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: allowedDocumentTypes.keys.toList(), withData: true);
    final f = r?.files.single;
    if (f == null) return;
    final err = DocumentRepository.validate(f.name, f.size);
    if (err != null) {
      if (mounted) showSnack(context, context.t(err), error: true);
      return;
    }
    setState(() {
      _file = f;
      if (_title.text.isEmpty) _title.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.replacing == null ? context.t('docs.upload') : context.t('docs.replace'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in documentCategories) DropdownMenuItem(value: c, child: Text(pretty(c)))],
          onChanged: (v) => setState(() => _category = v!),
        ),
        const SizedBox(height: 12),
        TextField(controller: _title, maxLength: 120, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Title')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(context.t('docs.expiry')),
          subtitle: Text(_expires == null ? '—' : isoDate(_expires!)),
          trailing: _expires == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _expires = null)),
          onTap: () async {
            final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
            if (d != null) setState(() => _expires = d);
          },
        ),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.attach_file_rounded),
          label: Text(_file == null ? 'Choose file (PDF, image or Word, max 10 MB)' : '${_file!.name} · ${(_file!.size / 1024).toStringAsFixed(0)} KB'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || _file?.bytes == null || _title.text.trim().isEmpty
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await runAction(context, () => ref.read(documentRepositoryProvider).upload(
                        category: _category, title: _title.text.trim(), fileName: _file!.name, bytes: _file!.bytes!,
                        expiresOn: _expires, replacing: widget.replacing,
                      ), success: context.t('common.saved'));
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) Navigator.pop(context, true);
                },
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.t('common.save')),
        ),
      ]),
    );
  }
}
