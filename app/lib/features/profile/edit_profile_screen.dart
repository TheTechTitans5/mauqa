import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

/// Profile editor split into independent sections so users can update one part at a time.
class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key, this.section});
  final String? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fp = ref.watch(fullProfileProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('profile.edit'))),
      body: AsyncView<FullProfile>(
        value: fp,
        onRetry: () => ref.invalidate(fullProfileProvider),
        data: (p) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              GlassCard(
                  child: Row(children: [
                Expanded(
                    child: Text(
                        context.t('profile.completion', {'n': p.completion}),
                        style: Theme.of(context).textTheme.titleMedium)),
                SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                        value: p.completion / 100,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8))),
              ])),
              const SizedBox(height: 12),
              _Section(
                  title: context.t('profile.personal'),
                  icon: Icons.person_outline,
                  initiallyExpanded: section == null || section == 'personal',
                  child: _PersonalForm(p: p.profile)),
              _Section(
                  title: context.t('profile.education'),
                  icon: Icons.school_outlined,
                  initiallyExpanded: section == 'education',
                  child: _EducationList(items: p.education)),
              _Section(
                  title: context.t('profile.skills'),
                  icon: Icons.psychology_outlined,
                  initiallyExpanded: section == 'skills',
                  child: _SkillGroupsEditor(items: p.skills)),
              // Interests are chosen on the Home page (see _InterestsPicker in home_screen.dart).
              _Section(
                  title: context.t('profile.experience'),
                  icon: Icons.work_outline,
                  initiallyExpanded: section == 'experience',
                  child: _ExperienceList(items: p.experiences)),
              _Section(
                  title: context.t('profile.certifications'),
                  icon: Icons.workspace_premium_outlined,
                  initiallyExpanded: section == 'certifications',
                  child: _CertificationList(items: p.certifications)),
              _Section(
                  title: context.t('profile.optional'),
                  icon: Icons.lock_outline,
                  initiallyExpanded: section == 'sensitive',
                  child: _SensitiveForm(p: p.profile)),
            ]),
      ),
    );
  }
}

void _refreshAfterChange(WidgetRef ref) {
  ref.invalidate(fullProfileProvider);
  ref.invalidate(homeSummaryProvider);
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.icon,
      required this.child,
      this.initiallyExpanded = false});
  final String title;
  final IconData icon;
  final Widget child;
  final bool initiallyExpanded;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            shape: const Border(),
            leading: Icon(icon, color: AppColors.teal),
            title: Text(title, style: Theme.of(context).textTheme.titleMedium),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [child],
          ),
        ),
      );
}

class _PersonalForm extends ConsumerStatefulWidget {
  const _PersonalForm({required this.p});
  final Profile p;
  @override
  ConsumerState<_PersonalForm> createState() => _PersonalFormState();
}

class _PersonalFormState extends ConsumerState<_PersonalForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.p.fullName);
  late final _phone = TextEditingController(text: widget.p.phone);
  late final _cnic = TextEditingController(text: widget.p.cnic);
  late final _city = TextEditingController(text: widget.p.city);
  late final _nationality =
      TextEditingController(text: widget.p.nationality ?? 'Pakistani');
  late final _languages =
      TextEditingController(text: widget.p.languages.join(', '));
  late DateTime? _dob = widget.p.dateOfBirth;
  // Gender is required. Older profiles may have no gender or "prefer_not_to_say"; they start empty here and
  // are asked to choose one when they save. The database still accepts the old values.
  static const _genders = ['female', 'male', 'transgender'];
  late String? _gender = _genders.contains(widget.p.gender) ? widget.p.gender : null;
  late String? _province = widget.p.province;
  late String? _category = widget.p.userCategory;
  late String? _employment = widget.p.employmentStatus;
  bool _dirty = false, _busy = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _cnic,
      _city,
      _nationality,
      _languages
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _reset() {
    setState(() {
      _name.text = widget.p.fullName ?? '';
      _phone.text = widget.p.phone ?? '';
      _cnic.text = widget.p.cnic ?? '';
      _city.text = widget.p.city ?? '';
      _nationality.text = widget.p.nationality ?? 'Pakistani';
      _languages.text = widget.p.languages.join(', ');
      _dob = widget.p.dateOfBirth;
      _gender = _genders.contains(widget.p.gender) ? widget.p.gender : null;
      _province = widget.p.province;
      _category = widget.p.userCategory;
      _employment = widget.p.employmentStatus;
      _dirty = false;
    });
  }

  Future<void> _pickAvatar() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null || !mounted) return;
    if (f.bytes!.length > 2 * 1024 * 1024)
      return showSnack(context, 'Photo must be under 2 MB', error: true);
    final ext = (f.extension ?? 'jpg').toLowerCase();
    if (await runAction(
        context,
        () => ref
            .read(profileRepositoryProvider)
            .uploadAvatar(f.bytes!, ext == 'jpeg' ? 'jpg' : ext),
        success: context.t('common.saved'))) {
      _refreshAfterChange(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? nn(String s) => s.trim().isEmpty ? null : s.trim();
    return Form(
      key: _form,
      onChanged: () => setState(() => _dirty = true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
            onPressed: _pickAvatar,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(context.t('profile.photo'))),
        const SizedBox(height: 12),
        TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: context.t('auth.fullName')),
            validator: (v) => Validators.required(v)),
        const SizedBox(height: 12),
        TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: context.t('auth.phone')),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? null : Validators.phonePk(v)),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake_outlined),
          title: Text(context.t('profile.dob')),
          subtitle: Text(_dob == null ? '—' : isoDate(_dob!)),
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime(2003),
                firstDate: DateTime(1930),
                lastDate: DateTime.now());
            if (d != null)
              setState(() {
                _dob = d;
                _dirty = true;
              });
          },
        ),
        DropdownButtonFormField<String>(
          key: const ValueKey('profile-gender'),
          value: _gender,
          decoration: InputDecoration(
              labelText: context.t('profile.gender'),
              helperText: context.t('profile.genderHelp'),
              helperMaxLines: 2),
          items: [
            for (final g in _genders)
              DropdownMenuItem(value: g, child: Text(context.t('gender.$g'))),
          ],
          validator: (v) =>
              v == null ? context.t('profile.genderRequired') : null,
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _category,
          decoration: InputDecoration(labelText: context.t('profile.category')),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (final c in userCategories)
              DropdownMenuItem(value: c, child: Text(pretty(c)))
          ],
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _employment,
          decoration:
              InputDecoration(labelText: context.t('profile.employment')),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (final c in employmentStatuses)
              DropdownMenuItem(value: c, child: Text(pretty(c)))
          ],
          onChanged: (v) => setState(() => _employment = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
            controller: _nationality,
            decoration: const InputDecoration(labelText: 'Nationality')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: _province,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.t('profile.province')),
          items: [
            const DropdownMenuItem(value: null, child: Text('—')),
            for (final p in provinces)
              DropdownMenuItem(value: p, child: Text(p))
          ],
          onChanged: (v) => setState(() => _province = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
            controller: _city,
            decoration: InputDecoration(labelText: context.t('profile.city'))),
        const SizedBox(height: 12),
        TextFormField(
            controller: _languages,
            decoration: InputDecoration(
                labelText: context.t('profile.languages'),
                hintText: context.t('profile.languagesHint'))),
        const SizedBox(height: 12),
        TextFormField(
            controller: _cnic,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: context.t('profile.cnic'),
                helperText:
                    'Only add if an opportunity requires it. Format 12345-1234567-1'),
            validator: Validators.cnic),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _dirty ? _reset : null,
                  child: Text(context.t('common.cancel')))),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) {
                        if (_gender == null) {
                          showSnack(context, context.t('profile.genderRequired'),
                              error: true);
                        }
                        return;
                      }
                      setState(() => _busy = true);
                      final ok = await runAction(
                          context,
                          () => ref
                                  .read(profileRepositoryProvider)
                                  .updateProfile({
                                'full_name': nn(_name.text),
                                'phone': _phone.text.trim().isEmpty
                                    ? null
                                    : Validators.normalizePhone(_phone.text),
                                'cnic': nn(_cnic.text),
                                'city': nn(_city.text),
                                'nationality': nn(_nationality.text),
                                'languages': _languages.text
                                    .split(RegExp('[,،]')) // English or Urdu comma
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty)
                                    .toList(),
                                'date_of_birth':
                                    _dob == null ? null : isoDate(_dob!),
                                'gender': _gender,
                                'province': _province,
                                'user_category': _category,
                                'employment_status': _employment,
                              }),
                          success: context.t('profile.recsUpdated'));
                      if (!mounted) return;
                      setState(() {
                        _busy = false;
                        if (ok) _dirty = false;
                      });
                      if (ok) _refreshAfterChange(ref);
                    },
              child: Text(context.t('common.save')),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _SensitiveForm extends ConsumerStatefulWidget {
  const _SensitiveForm({required this.p});
  final Profile p;
  @override
  ConsumerState<_SensitiveForm> createState() => _SensitiveFormState();
}

class _SensitiveFormState extends ConsumerState<_SensitiveForm> {
  late String? _range = widget.p.incomeRange;
  late final _exact =
      TextEditingController(text: widget.p.incomeMonthlyPkr?.toString() ?? '');
  late bool? _disability = widget.p.hasDisability;
  late bool _share = widget.p.shareSensitive;

  @override
  void dispose() {
    _exact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InfoBanner(
          text: context.t('profile.sensitiveNote'),
          color: AppColors.lavender,
          icon: Icons.privacy_tip_outlined),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        value: _range,
        decoration: InputDecoration(labelText: context.t('profile.income')),
        items: [
          const DropdownMenuItem(value: null, child: Text('Prefer not to say')),
          for (final r in incomeRanges)
            DropdownMenuItem(
                value: r,
                child: Text(
                    'PKR ${r.replaceAll('_', '–').replaceAll('k', ',000')}')),
        ],
        onChanged: (v) => setState(() => _range = v),
      ),
      const SizedBox(height: 12),
      TextField(
          controller: _exact,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Exact monthly household income (PKR, optional)')),
      const SizedBox(height: 8),
      DropdownButtonFormField<bool?>(
        value: _disability,
        decoration: InputDecoration(labelText: context.t('profile.disability')),
        items: const [
          DropdownMenuItem(value: null, child: Text('Prefer not to say')),
          DropdownMenuItem(value: true, child: Text('Yes')),
          DropdownMenuItem(value: false, child: Text('No')),
        ],
        onChanged: (v) => setState(() => _disability = v),
      ),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _share,
          title: Text(context.t('profile.shareSensitive')),
          onChanged: (v) => setState(() => _share = v)),
      FilledButton(
        onPressed: () async {
          final exact = int.tryParse(_exact.text.trim());
          if (_exact.text.trim().isNotEmpty && (exact == null || exact < 0))
            return showSnack(context, 'Enter a valid amount', error: true);
          if (await runAction(
              context,
              () => ref.read(profileRepositoryProvider).updateProfile({
                    'household_income_range': _range,
                    'household_income_monthly_pkr': exact,
                    'has_disability': _disability,
                    'share_sensitive_for_eligibility': _share,
                  }),
              success: context.t('profile.recsUpdated'))) {
            _refreshAfterChange(ref);
          }
        },
        child: Text(context.t('common.save')),
      ),
    ]);
  }
}

/// Suggested skills for each group. Labels come from strings.dart (`skillopt.<key>`); the English label is
/// what gets saved, because eligibility rules and recommendations compare English skill names.
const _skillSuggestions = <String, List<String>>{
  'curricular': [
    'python',
    'java',
    'cpp',
    'sql',
    'javascript',
    'flutter',
    'web_dev',
    'data_analysis',
    'excel',
    'mathematics',
    'statistics',
    'accounting',
    'research_writing',
    'lab_skills',
  ],
  'co_curricular': [
    'public_speaking',
    'debating',
    'leadership',
    'teamwork',
    'event_management',
    'society_management',
    'mun',
    'volunteering',
    'sports',
    'content_writing',
    'photography',
  ],
  'other': [
    'communication',
    'problem_solving',
    'time_management',
    'graphic_design',
    'social_media',
    'urdu_writing',
    'english_writing',
    'teaching',
    'customer_service',
    'freelancing',
  ],
};

final _english = S(const Locale('en'));

String _skillGroupTitle(BuildContext context, String group) => context.t(
    switch (group) {
      'curricular' => 'profile.skillsCurricular',
      'co_curricular' => 'profile.skillsCoCurricular',
      _ => 'profile.skillsOther',
    });

/// Shows a saved skill in the current language when it is one of the suggestions; custom skills as typed.
String _skillLabel(BuildContext context, String stored) {
  final key = stored.trim().toLowerCase();
  for (final group in _skillSuggestions.values) {
    for (final k in group) {
      if (_english.t('skillopt.$k').toLowerCase() == key) {
        return context.t('skillopt.$k');
      }
    }
  }
  return stored;
}

Future<void> _moveSkill(BuildContext context, WidgetRef ref, NamedItem skill,
    String group) async {
  final message =
      context.t('profile.skillMoved', {'group': _skillGroupTitle(context, group)});
  if (await runAction(
      context,
      () => ref
          .read(profileRepositoryProvider)
          .setSkillCategory(skill.id, group),
      success: message)) {
    _refreshAfterChange(ref);
  }
}

/// Skills in three groups — Curricular, Co-curricular, Other — each with its own input and suggestions.
/// All groups still save into the one flat user_skills list that the rest of the app reads.
class _SkillGroupsEditor extends StatelessWidget {
  const _SkillGroupsEditor({required this.items});
  final List<NamedItem> items;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.t('profile.skillsHint'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final g in skillGroups) ...[
          _SkillGroup(key: ValueKey('skill-group-$g'), group: g, all: items),
          if (g != skillGroups.last) const Divider(height: 28),
        ],
      ]);
}

class _SkillGroup extends ConsumerStatefulWidget {
  const _SkillGroup({super.key, required this.group, required this.all});
  final String group;
  final List<NamedItem> all;
  @override
  ConsumerState<_SkillGroup> createState() => _SkillGroupState();
}

class _SkillGroupState extends ConsumerState<_SkillGroup> {
  final _c = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _add(String value) async {
    final name = value.trim();
    if (name.isEmpty || _busy) return;
    if (name.length > 60) {
      return showSnack(context, context.t('profile.skillTooLong'), error: true);
    }
    final existing = findByName(widget.all, name);
    if (existing != null) {
      _c.clear();
      if (skillGroupOf(existing) == widget.group) {
        return showSnack(context, context.t('common.alreadyAdded'));
      }
      // Typing a skill that is already in another group moves it here.
      return _moveSkill(context, ref, existing, widget.group);
    }
    setState(() => _busy = true);
    final ok = await runAction(
        context,
        () => ref
            .read(profileRepositoryProvider)
            .addSkill(name, category: widget.group));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _c.clear();
      _refreshAfterChange(ref);
    }
  }

  Future<void> _remove(NamedItem skill) async {
    if (await runAction(context,
        () => ref.read(profileRepositoryProvider).removeSkill(skill.id))) {
      _refreshAfterChange(ref);
    }
  }

  Future<void> _chooseGroup(NamedItem skill) async {
    final target = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(context.t('profile.moveSkill'),
                    style: Theme.of(sheet).textTheme.titleMedium),
              ),
              for (final g in skillGroups)
                if (g != widget.group)
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: Text(_skillGroupTitle(context, g)),
                    onTap: () => Navigator.pop(sheet, g),
                  ),
            ]),
      ),
    );
    if (target == null) return;
    if (!mounted) return;
    await _moveSkill(context, ref, skill, target);
  }

  @override
  Widget build(BuildContext context) {
    final mine = groupSkills(widget.all)[widget.group] ?? const <NamedItem>[];
    final taken = widget.all.map((s) => s.name.trim().toLowerCase()).toSet();
    final suggestions = (_skillSuggestions[widget.group] ?? const <String>[])
        .where((k) => !taken.contains(_english.t('skillopt.$k').toLowerCase()))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_skillGroupTitle(context, widget.group),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: AppColors.teal, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (mine.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final s in mine)
            InputChip(
              label: Text(_skillLabel(context, s.name)),
              tooltip: context.t('profile.moveSkill'),
              onPressed: () => _chooseGroup(s),
              onDeleted: () => _remove(s),
            ),
        ]),
        const SizedBox(height: 8),
      ],
      TextField(
        key: ValueKey('skill-input-${widget.group}'),
        controller: _c,
        maxLength: 60,
        decoration: InputDecoration(
            hintText: context.t('profile.addSkill'),
            counterText: '',
            suffixIcon: IconButton(
                tooltip: context.t('common.add'),
                icon: const Icon(Icons.add_rounded),
                onPressed: _busy ? null : () => _add(_c.text))),
        onSubmitted: _add,
      ),
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final k in suggestions)
            ActionChip(
                label: Text(context.t('skillopt.$k')),
                onPressed:
                    _busy ? null : () => _add(_english.t('skillopt.$k'))),
        ]),
      ],
    ]);
  }
}

class _EducationList extends ConsumerWidget {
  const _EducationList({required this.items});
  final List<EducationRecord> items;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                e.isCurrent
                    ? Icons.radio_button_checked
                    : Icons.school_outlined,
                color: AppColors.teal),
            title: Text(
                '${pretty(e.level)}${e.degreeProgram != null ? ' · ${e.degreeProgram}' : ''}'),
            subtitle: Text([
              e.institutionName,
              e.department,
              e.scoreLabel,
              if (e.currentSemester != null) 'Semester ${e.currentSemester}'
            ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDialog(context,
                        title: 'Remove this education record?',
                        destructive: true) &&
                    context.mounted &&
                    await runAction(
                        context,
                        () => ref
                            .read(profileRepositoryProvider)
                            .deleteEducation(e.id!))) {
                  _refreshAfterChange(ref);
                }
              },
            ),
            onTap: () => _editEducation(context, ref, e),
          ),
        OutlinedButton.icon(
            onPressed: () => _editEducation(context, ref, null),
            icon: const Icon(Icons.add),
            label: Text(context.t('profile.addEducation'))),
      ]);
}

Future<void> _editEducation(
    BuildContext context, WidgetRef ref, EducationRecord? e) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EducationForm(initial: e),
  );
  if (saved == true) _refreshAfterChange(ref);
}

class _EducationForm extends ConsumerStatefulWidget {
  const _EducationForm({this.initial});
  final EducationRecord? initial;
  @override
  ConsumerState<_EducationForm> createState() => _EducationFormState();
}

class _EducationFormState extends ConsumerState<_EducationForm> {
  final _form = GlobalKey<FormState>();
  late String _level = widget.initial?.level ?? 'bachelor';
  late String _status = widget.initial?.enrollmentStatus ?? 'enrolled';
  late String _scoreType = widget.initial?.scoreType ?? 'cgpa';
  late bool _current = widget.initial?.isCurrent ?? true;
  late String? _institutionId = widget.initial?.institutionId;
  late String? _selectedDisplay = widget.initial?.institutionName;
  late final _institution =
      TextEditingController(text: widget.initial?.institutionName);
  late final _dept = TextEditingController(text: widget.initial?.department);
  late final _degree =
      TextEditingController(text: widget.initial?.degreeProgram);
  late final _field = TextEditingController(text: widget.initial?.fieldOfStudy);
  late final _semester =
      TextEditingController(text: widget.initial?.currentSemester?.toString());
  late final _gradYear =
      TextEditingController(text: widget.initial?.graduationYear?.toString());
  late final _score =
      TextEditingController(text: widget.initial?.scoreValue?.toString());
  late final _max = TextEditingController(
      text: widget.initial?.scoreMax?.toString() ?? '4.0');

  @override
  void dispose() {
    for (final c in [
      _institution,
      _dept,
      _degree,
      _field,
      _semester,
      _gradYear,
      _score,
      _max
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uni =
        ['bachelor', 'master', 'mphil', 'phd', 'diploma'].contains(_level);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, children: [
          Text(context.t('profile.education'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _level,
            decoration: const InputDecoration(labelText: 'Level'),
            items: [
              for (final l in educationLevels)
                DropdownMenuItem(value: l, child: Text(pretty(l)))
            ],
            onChanged: (v) => setState(() {
              _level = v!;
              final isUni = ['bachelor', 'master', 'mphil', 'phd', 'diploma']
                  .contains(_level);
              _scoreType = isUni ? 'cgpa' : 'percentage';
              _max.text = isUni ? '4.0' : '1100';
            }),
          ),
          const SizedBox(height: 12),
          Autocomplete<Institution>(
            initialValue: TextEditingValue(text: _institution.text),
            displayStringForOption: (i) => i.display,
            optionsBuilder: (v) async {
              if (v.text != _selectedDisplay) {
                // user typed something new: forget the previously linked institution
                _institution.text = v.text;
                _institutionId = null;
                _selectedDisplay = null;
              }
              if (v.text.trim().length < 2)
                return const Iterable<Institution>.empty();
              try {
                return await ref
                    .read(profileRepositoryProvider)
                    .searchInstitutions(v.text.trim());
              } catch (_) {
                return const Iterable<Institution>.empty();
              }
            },
            onSelected: (i) {
              _institution.text = i.name;
              _institutionId = i.id;
              _selectedDisplay = i.display;
            },
            fieldViewBuilder: (context, controller, focus, onSubmit) =>
                TextFormField(
              controller: controller,
              focusNode: focus,
              decoration: const InputDecoration(
                  labelText: 'Institution',
                  helperText:
                      'Pick from the list when possible so eligibility can match it'),
            ),
          ),
          const SizedBox(height: 12),
          if (uni) ...[
            TextFormField(
                controller: _degree,
                decoration: const InputDecoration(
                    labelText: 'Degree / programme',
                    hintText: 'BS Computer Science')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _dept,
                decoration: const InputDecoration(labelText: 'Department')),
            const SizedBox(height: 12),
          ],
          TextFormField(
              controller: _field,
              decoration: const InputDecoration(
                  labelText: 'Field of study / group',
                  hintText: 'e.g. Computer Science, Pre-Engineering')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'Enrolment status'),
            items: const [
              DropdownMenuItem(
                  value: 'enrolled', child: Text('Currently enrolled')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(
                  value: 'awaiting_result', child: Text('Awaiting result')),
              DropdownMenuItem(
                  value: 'discontinued', child: Text('Discontinued')),
            ],
            onChanged: (v) => setState(() => _status = v!),
          ),
          const SizedBox(height: 12),
          Row(children: [
            if (uni && _status == 'enrolled') ...[
              Expanded(
                  child: TextFormField(
                      controller: _semester,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Semester'),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (v == null || v.isEmpty)
                            ? null
                            : (n == null || n < 1 || n > 16)
                                ? '1–16'
                                : null;
                      })),
              const SizedBox(width: 12),
            ],
            Expanded(
                child: TextFormField(
                    controller: _gradYear,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Graduation year'),
                    validator: Validators.year)),
          ]),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cgpa', label: Text('CGPA')),
              ButtonSegment(value: 'percentage', label: Text('Marks / %'))
            ],
            selected: {_scoreType},
            onSelectionChanged: (v) => setState(() {
              _scoreType = v.first;
              _max.text = _scoreType == 'cgpa' ? '4.0' : '100';
            }),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextFormField(
                    controller: _score,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText:
                            _scoreType == 'cgpa' ? 'CGPA' : 'Marks obtained'),
                    validator: (v) => _scoreType == 'cgpa'
                        ? (Validators.cgpa(v,
                            max: double.tryParse(_max.text) ?? 4))
                        : Validators.score(v, _max.text))),
            const SizedBox(width: 12),
            Expanded(
                child: TextFormField(
                    controller: _max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                        labelText:
                            _scoreType == 'cgpa' ? 'Out of' : 'Total marks'))),
          ]),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _current,
              onChanged: (v) => setState(() => _current = v),
              title: const Text('This is my current / latest education')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final rec = EducationRecord(
                id: widget.initial?.id,
                level: _level,
                institutionId: _institutionId,
                institutionName: _institution.text.trim().isEmpty
                    ? null
                    : _institution.text.trim(),
                department:
                    _dept.text.trim().isEmpty ? null : _dept.text.trim(),
                degreeProgram:
                    _degree.text.trim().isEmpty ? null : _degree.text.trim(),
                fieldOfStudy:
                    _field.text.trim().isEmpty ? null : _field.text.trim(),
                currentSemester: int.tryParse(_semester.text.trim()),
                enrollmentStatus: _status,
                graduationYear: int.tryParse(_gradYear.text.trim()),
                scoreType: _score.text.trim().isEmpty ? null : _scoreType,
                scoreValue: double.tryParse(_score.text.trim()),
                scoreMax: double.tryParse(_max.text.trim()),
                isCurrent: _current,
              );
              if (await runAction(
                      context,
                      () => ref
                          .read(profileRepositoryProvider)
                          .saveEducation(rec),
                      success: context.t('profile.recsUpdated')) &&
                  context.mounted) {
                Navigator.pop(context, true);
              }
            },
            child: Text(context.t('common.save')),
          ),
        ]),
      ),
    );
  }
}

class _ExperienceList extends ConsumerWidget {
  const _ExperienceList({required this.items});
  final List<Experience> items;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(e.kind == 'internship'
                ? Icons.badge_outlined
                : e.kind == 'volunteer'
                    ? Icons.volunteer_activism_outlined
                    : Icons.work_outline),
            title: Text(e.title),
            subtitle: Text(
                '${e.organization ?? ''} · ${isoDate(e.startDate)} – ${e.isCurrent ? 'present' : e.endDate == null ? '' : isoDate(e.endDate!)}'),
            trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await runAction(
                      context,
                      () => ref
                          .read(profileRepositoryProvider)
                          .deleteExperience(e.id!))) _refreshAfterChange(ref);
                }),
            onTap: () => _editExperience(context, ref, e),
          ),
        OutlinedButton.icon(
            onPressed: () => _editExperience(context, ref, null),
            icon: const Icon(Icons.add),
            label: Text(context.t('profile.addExperience'))),
      ]);
}

Future<void> _editExperience(
    BuildContext context, WidgetRef ref, Experience? e) async {
  final title = TextEditingController(text: e?.title);
  final org = TextEditingController(text: e?.organization);
  final desc = TextEditingController(text: e?.description);
  String kind = e?.kind ?? 'internship';
  DateTime? start = e?.startDate;
  DateTime? end = e?.endDate;
  bool current = e?.isCurrent ?? false;
  final form = GlobalKey<FormState>();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
              child: Form(
                key: form,
                child: ListView(shrinkWrap: true, children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'work', label: Text('Work')),
                      ButtonSegment(
                          value: 'internship', label: Text('Internship')),
                      ButtonSegment(
                          value: 'volunteer', label: Text('Volunteer'))
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) => set(() => kind = v.first),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: title,
                      decoration:
                          const InputDecoration(labelText: 'Role / title'),
                      validator: (v) => Validators.required(v)),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: org,
                      decoration:
                          const InputDecoration(labelText: 'Organisation')),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start date'),
                      subtitle:
                          Text(start == null ? 'Required' : isoDate(start!)),
                      onTap: () async {
                        final d = await showDatePicker(
                            context: c,
                            initialDate: start ?? DateTime.now(),
                            firstDate: DateTime(1970),
                            lastDate: DateTime.now());
                        if (d != null) set(() => start = d);
                      }),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: current,
                      title: const Text('I currently do this'),
                      onChanged: (v) => set(() => current = v)),
                  if (!current)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('End date'),
                        subtitle: Text(end == null ? '—' : isoDate(end!)),
                        onTap: () async {
                          final d = await showDatePicker(
                              context: c,
                              initialDate: end ?? DateTime.now(),
                              firstDate: start ?? DateTime(1970),
                              lastDate: DateTime.now());
                          if (d != null) set(() => end = d);
                        }),
                  TextFormField(
                      controller: desc,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)')),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      if (!form.currentState!.validate()) return;
                      if (start == null)
                        return showSnack(c, 'Choose a start date', error: true);
                      if (!current && end != null && end!.isBefore(start!))
                        return showSnack(c, 'End date must be after start date',
                            error: true);
                      final x = Experience(
                          id: e?.id,
                          kind: kind,
                          title: title.text.trim(),
                          organization:
                              org.text.trim().isEmpty ? null : org.text.trim(),
                          startDate: start!,
                          endDate: current ? null : end,
                          isCurrent: current,
                          description: desc.text.trim().isEmpty
                              ? null
                              : desc.text.trim());
                      if (await runAction(
                              c,
                              () => ref
                                  .read(profileRepositoryProvider)
                                  .saveExperience(x)) &&
                          c.mounted) Navigator.pop(c, true);
                    },
                    child: Text(context.t('common.save')),
                  ),
                ]),
              ),
            )),
  );
  title.dispose();
  org.dispose();
  desc.dispose();
  if (ok == true) _refreshAfterChange(ref);
}

class _CertificationList extends ConsumerWidget {
  const _CertificationList({required this.items});
  final List<Certification> items;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.workspace_premium_outlined),
            title: Text(c.name),
            subtitle: Text([
              c.issuer,
              if (c.issuedOn != null) isoDate(c.issuedOn!)
            ].whereType<String>().join(' · ')),
            trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await runAction(
                      context,
                      () => ref
                          .read(profileRepositoryProvider)
                          .deleteCertification(c.id!)))
                    _refreshAfterChange(ref);
                }),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final name = TextEditingController();
            final issuer = TextEditingController();
            final url = TextEditingController();
            final form = GlobalKey<FormState>();
            final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                      title: Text(context.t('profile.addCertification')),
                      content: Form(
                          key: form,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            TextFormField(
                                controller: name,
                                decoration: const InputDecoration(
                                    labelText: 'Certificate name'),
                                validator: (v) => Validators.required(v)),
                            const SizedBox(height: 8),
                            TextFormField(
                                controller: issuer,
                                decoration:
                                    const InputDecoration(labelText: 'Issuer')),
                            const SizedBox(height: 8),
                            TextFormField(
                                controller: url,
                                decoration: const InputDecoration(
                                    labelText: 'Credential link (optional)'),
                                validator: (v) => Validators.httpsUrl(v)),
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: Text(context.t('common.cancel'))),
                        FilledButton(
                            onPressed: () {
                              if (form.currentState!.validate())
                                Navigator.pop(d, true);
                            },
                            child: Text(context.t('common.save'))),
                      ],
                    ));
            if (ok == true && context.mounted) {
              final cert = Certification(
                  name: name.text.trim(),
                  issuer:
                      issuer.text.trim().isEmpty ? null : issuer.text.trim(),
                  credentialUrl:
                      url.text.trim().isEmpty ? null : url.text.trim());
              if (await runAction(
                  context,
                  () => ref
                      .read(profileRepositoryProvider)
                      .saveCertification(cert))) _refreshAfterChange(ref);
            }
            name.dispose();
            issuer.dispose();
            url.dispose();
          },
          icon: const Icon(Icons.add),
          label: Text(context.t('profile.addCertification')),
        ),
      ]);
}
