import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/strings.dart';
import '../../data/local/offline_cache.dart';
import '../../data/models/opportunity.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/opportunity_card.dart';

class ExploreState {
  const ExploreState({this.filters = const SearchFilters(), this.items = const [], this.total = 0, this.loading = false, this.error});
  final SearchFilters filters;
  final List<Opportunity> items;
  final int total;
  final bool loading;
  final Object? error;
  bool get hasMore => items.length < total;
  ExploreState copyWith({SearchFilters? filters, List<Opportunity>? items, int? total, bool? loading, Object? error, bool clearError = false}) =>
      ExploreState(filters: filters ?? this.filters, items: items ?? this.items, total: total ?? this.total,
          loading: loading ?? this.loading, error: clearError ? null : (error ?? this.error));
}

class ExploreController extends StateNotifier<ExploreState> {
  ExploreController(this._repo, this._cache) : super(const ExploreState());
  final OpportunityRepository _repo;
  final OfflineCache _cache;
  int _generation = 0;

  Future<void> apply(SearchFilters f) async {
    final gen = ++_generation;
    state = state.copyWith(filters: f, loading: true, clearError: true);
    try {
      final page = await _repo.search(f);
      if (gen != _generation) return; // a newer search replaced this one
      state = state.copyWith(items: page.items, total: page.total, loading: false);
      if (f.query.trim().length >= 2) {
        await _cache.addSearch(f.query);
        _repo.logSearch(f.query, f.toRpcFilters());
      }
    } catch (e) {
      if (gen == _generation) state = state.copyWith(loading: false, error: e, items: const [], total: 0);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    final gen = _generation;
    state = state.copyWith(loading: true);
    try {
      final page = await _repo.search(state.filters, offset: state.items.length);
      if (gen != _generation) return;
      state = state.copyWith(items: [...state.items, ...page.items], total: page.total, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> refresh() => apply(state.filters);
}

final exploreProvider = StateNotifierProvider.autoDispose<ExploreController, ExploreState>(
    (ref) => ExploreController(ref.watch(opportunityRepositoryProvider), ref.watch(offlineCacheProvider)));

const _suggested = ['Need-based scholarship', 'Software internship', 'Women', 'Remote jobs', 'Startup grant', 'Punjab', 'Free training'];

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key, this.initialCategory, this.initialQuery, this.initialStatus});
  final String? initialCategory;
  final String? initialQuery;
  final String? initialStatus;
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery ?? '');
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(exploreProvider.notifier).apply(SearchFilters(
          query: widget.initialQuery ?? '',
          categories: widget.initialCategory == null ? const [] : [widget.initialCategory!],
          statuses: widget.initialStatus == null ? const [] : [widget.initialStatus!],
          sort: widget.initialStatus == 'closing_soon' ? 'deadline' : 'relevance',
        )));
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) ref.read(exploreProvider.notifier).loadMore();
    });
  }

  @override
  void didUpdateWidget(covariant ExploreScreen old) {
    super.didUpdateWidget(old);
    if (old.initialCategory != widget.initialCategory || old.initialStatus != widget.initialStatus) {
      final f = ref.read(exploreProvider).filters;
      ref.read(exploreProvider.notifier).apply(f.copyWith(
            categories: widget.initialCategory == null ? f.categories : [widget.initialCategory!],
            statuses: widget.initialStatus == null ? f.statuses : [widget.initialStatus!],
          ));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final f = ref.read(exploreProvider).filters;
      ref.read(exploreProvider.notifier).apply(f.copyWith(query: v));
    });
  }

  void _setQuery(String v) {
    _q.text = v;
    _onQuery(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(exploreProvider);
    final f = s.filters;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <OpportunityCategory>[];
    final history = ref.watch(offlineCacheProvider).searchHistory();

    return Scaffold(
      appBar: AppBar(title: Text(context.t('explore.title'))),
      body: RefreshIndicator(
        onRefresh: () => ref.read(exploreProvider.notifier).refresh(),
        child: CustomScrollView(controller: _scroll, slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    onChanged: _onQuery,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: context.t('home.searchHint'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => _setQuery('')),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: f.activeCount > 0,
                  label: Text('${f.activeCount}'),
                  child: IconButton.filledTonal(
                    tooltip: context.t('explore.filters'),
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: () async {
                      final r = await showModalBottomSheet<SearchFilters>(
                        context: context, isScrollControlled: true, showDragHandle: true,
                        builder: (_) => FilterSheet(initial: f, categories: cats),
                      );
                      if (r != null) ref.read(exploreProvider.notifier).apply(r);
                    },
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      avatar: Icon(iconFor(c.icon), size: 16),
                      label: Text(c.name(context.isUrdu)),
                      selected: f.categories.contains(c.slug),
                      onSelected: (v) => ref.read(exploreProvider.notifier).apply(f.copyWith(
                          categories: v ? [...f.categories, c.slug] : f.categories.where((x) => x != c.slug).toList())),
                    ),
                  ),
              ]),
            ),
          ),
          if (_q.text.isEmpty && f.activeCount == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (history.isNotEmpty) ...[
                    Row(children: [
                      Text(context.t('explore.history'), style: Theme.of(context).textTheme.labelLarge),
                      const Spacer(),
                      TextButton(onPressed: () async { await ref.read(offlineCacheProvider).clearSearchHistory(); setState(() {}); }, child: Text(context.t('explore.clear'))),
                    ]),
                    Wrap(spacing: 8, children: [for (final h in history) ActionChip(avatar: const Icon(Icons.history, size: 16), label: Text(h), onPressed: () => _setQuery(h))]),
                    const SizedBox(height: 8),
                  ],
                  Text(context.t('explore.suggested'), style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [for (final h in _suggested) ActionChip(label: Text(h), onPressed: () => _setQuery(h))]),
                ]),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(children: [
                Text(context.t('explore.results', {'n': s.total}), style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (f.activeCount > 0)
                  TextButton(onPressed: () => ref.read(exploreProvider.notifier).apply(f.cleared()), child: Text(context.t('explore.clear'))),
                PopupMenuButton<String>(
                  tooltip: context.t('explore.sort'),
                  initialValue: f.sort,
                  onSelected: (v) => ref.read(exploreProvider.notifier).apply(f.copyWith(sort: v)),
                  itemBuilder: (_) => [
                    for (final k in ['relevance', 'latest', 'deadline', 'popularity']) PopupMenuItem(value: k, child: Text(context.t('sort.$k'))),
                  ],
                  child: Row(children: [const Icon(Icons.sort_rounded, size: 18), const SizedBox(width: 4), Text(context.t('sort.${f.sort}'))]),
                ),
              ]),
            ),
          ),
          if (s.error != null && s.items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: s.error!, onRetry: () => ref.read(exploreProvider.notifier).refresh()))
          else if (s.loading && s.items.isEmpty)
            const SliverToBoxAdapter(child: LoadingList())
          else if (s.items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: EmptyState(message: context.t('explore.noResults'), icon: Icons.search_off_rounded))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              sliver: SliverList.separated(
                itemCount: s.items.length + (s.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => i >= s.items.length
                    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                    : OpportunityCard(opportunity: s.items[i], index: i),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Advanced filter bottom sheet.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, required this.categories});
  final SearchFilters initial;
  final List<OpportunityCategory> categories;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SearchFilters f = widget.initial;
  final _age = TextEditingController();
  final _exp = TextEditingController();
  final _amount = TextEditingController();
  final _field = TextEditingController();
  final _city = TextEditingController();

  @override
  void initState() {
    super.initState();
    _age.text = f.age?.toString() ?? '';
    _exp.text = f.maxExperienceMonths?.toString() ?? '';
    _amount.text = f.minAmountPkr?.toString() ?? '';
    _field.text = f.fields.join(', ');
    _city.text = f.cities.join(', ');
  }

  @override
  void dispose() {
    for (final c in [_age, _exp, _amount, _field, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _toggle(List<String> l, String v) => l.contains(v) ? (l.where((x) => x != v).toList()) : [...l, v];

  Widget _group(String title, List<(String, String)> options, List<String> selected, void Function(List<String>) set) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (value, label) in options)
              FilterChip(label: Text(label), selected: selected.contains(value), onSelected: (_) => setState(() => set(_toggle(selected, value)))),
          ]),
        ],
      );

  List<String> _csv(String s) => s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    final ur = context.isUrdu;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
            Text(context.t('explore.filters'), style: Theme.of(context).textTheme.titleLarge),
            _group(context.t('explore.categories'), [for (final c in widget.categories) (c.slug, c.name(ur))], f.categories,
                (v) => f = f.copyWith(categories: v)),
            _group('Status', [('open', 'Open'), ('closing_soon', context.t('home.closingSoon')), ('upcoming', context.t('common.opensSoon')), ('closed', context.t('common.closed'))],
                f.statuses, (v) => f = f.copyWith(statuses: v)),
            _group(context.t('profile.province'), [for (final p in provinces) (p, p)], f.provinces, (v) => f = f.copyWith(provinces: v)),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'Cities (comma separated)')),
            ),
            _group('Education level', [for (final l in educationLevels) (l, pretty(l))], f.educationLevels, (v) => f = f.copyWith(educationLevels: v)),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(controller: _field, decoration: const InputDecoration(labelText: 'Field of study (comma separated)')),
            ),
            _group('Funding', [('fully_funded', 'Fully funded'), ('partially_funded', 'Partially funded'), ('paid', 'Paid'), ('unpaid', 'Unpaid')],
                f.fundingTypes, (v) => f = f.copyWith(fundingTypes: v)),
            _group('Work mode', [('remote', 'Remote'), ('onsite', 'On-site'), ('hybrid', 'Hybrid')], f.workModes, (v) => f = f.copyWith(workModes: v)),
            _group('Organisation type', [('government', 'Government'), ('private', 'Private'), ('ngo', 'NGO'), ('university', 'University'), ('international', 'International')],
                f.orgTypes, (v) => f = f.copyWith(orgTypes: v)),
            Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text('Open to', style: Theme.of(context).textTheme.titleSmall)),
            Wrap(spacing: 8, children: [
              for (final g in const [(null, 'Everyone'), ('female', 'Women'), ('male', 'Men'), ('transgender', 'Transgender persons')])
                ChoiceChip(label: Text(g.$2), selected: f.gender == g.$1, onSelected: (_) => setState(() => f = f.copyWith(gender: g.$1))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'My age'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _exp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'My experience (months)'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum amount (PKR)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Income-based programmes only'), value: f.incomeBased,
                onChanged: (v) => setState(() => f = f.copyWith(incomeBased: v))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('settings.verifiedOnly')), value: f.verifiedOnly,
                onChanged: (v) => setState(() => f = f.copyWith(verifiedOnly: v))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(context.t('settings.hideDemo')), value: f.hideDemo,
                onChanged: (v) => setState(() => f = f.copyWith(hideDemo: v))),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Deadline before'),
              subtitle: Text(f.deadlineBefore == null ? 'Any time' : '${f.deadlineBefore!.toLocal()}'.split(' ').first),
              trailing: f.deadlineBefore == null ? const Icon(Icons.event) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => f = f.copyWith(deadlineBefore: null))),
              onTap: () async {
                final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
                if (d != null) setState(() => f = f.copyWith(deadlineBefore: DateTime.utc(d.year, d.month, d.day, 18, 59)));
              },
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, f.cleared()), child: Text(context.t('explore.clear')))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, f.copyWith(
                    age: int.tryParse(_age.text.trim()),
                    maxExperienceMonths: int.tryParse(_exp.text.trim()),
                    minAmountPkr: int.tryParse(_amount.text.trim()),
                    fields: _csv(_field.text),
                    cities: _csv(_city.text),
                  )),
                  child: Text(context.t('common.done')),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

