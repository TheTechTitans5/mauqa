import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/strings.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/activity.dart';
import '../../data/models/opportunity.dart';
import '../../data/models/profile.dart' show NamedItem, findByName, interestOptions, pretty;
import '../../data/repositories/content_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/opportunity_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/opportunity_card.dart';
import '../../widgets/visuals.dart';

typedef _FeedKey = ({String? category, String? status, bool featured, String order});

final _homeFeedProvider = FutureProvider.autoDispose.family<List<Opportunity>, _FeedKey>((ref, k) =>
    ref.watch(opportunityRepositoryProvider).feed(category: k.category, status: k.status, featured: k.featured, order: k.order));
final _trendingProvider = FutureProvider.autoDispose<List<Opportunity>>((ref) => ref.watch(opportunityRepositoryProvider).trending());
final recommendedProvider = FutureProvider.autoDispose<List<RecommendedOpportunity>>((ref) {
  ref.watch(fullProfileProvider); // refresh after profile edits
  return ref.watch(opportunityRepositoryProvider).recommended();
});
final _announcementsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(contentRepositoryProvider).announcements());

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.offset < 300) setState(() => _offset = _scroll.offset);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(homeSummaryProvider);
    ref.invalidate(recommendedProvider);
    ref.invalidate(_homeFeedProvider);
    ref.invalidate(_trendingProvider);
    ref.invalidate(notificationsProvider);
    await ref.read(homeSummaryProvider.future).catchError((_) => HomeSummary.empty());
  }

  @override
  Widget build(BuildContext context) {
    final simple = ref.watch(appSettingsProvider).simpleMode;
    final summary = ref.watch(homeSummaryProvider);
    final profile = ref.watch(fullProfileProvider);
    final name = profile.valueOrNull?.profile.firstName ?? '';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(controller: _scroll, slivers: [
          SliverToBoxAdapter(child: _Hero(name: name, summary: summary.valueOrNull, parallax: _offset)),
          SliverToBoxAdapter(child: _QuickCategories()),
          SliverToBoxAdapter(child: _StatsRow(summary: summary.valueOrNull)),
          if ((summary.valueOrNull?.completion ?? 100) < 80)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: GlassCard(
                  onTap: () => context.push('/profile/edit'),
                  child: Row(children: [
                    ProgressRing(value: (summary.valueOrNull?.completion ?? 0) / 100, size: 54),
                    const SizedBox(width: 14),
                    Expanded(child: Text(context.t('home.completeProfile'), style: Theme.of(context).textTheme.titleSmall)),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: _InterestsPicker()),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.forYou'), icon: Icons.auto_awesome_rounded, onSeeAll: () => context.go('/explore'))),
          _RecommendedList(),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.closingSoon'), icon: Icons.timer_outlined,
              onSeeAll: () => context.go('/explore?status=closing_soon'))),
          SliverToBoxAdapter(child: _Carousel(provider: _homeFeedProvider((category: null, status: 'closing_soon', featured: false, order: 'deadline')))),
          if (!simple) ...[
            SliverToBoxAdapter(child: SectionHeader(context.t('home.featured'), icon: Icons.workspace_premium_outlined)),
            SliverToBoxAdapter(child: _Carousel(provider: _homeFeedProvider((category: null, status: null, featured: true, order: 'deadline')))),
            SliverToBoxAdapter(child: SectionHeader(context.t('home.trending'), icon: Icons.local_fire_department_outlined)),
            SliverToBoxAdapter(child: _Carousel(provider: _trendingProvider)),
          ],
          SliverToBoxAdapter(child: SectionHeader(context.t('home.scholarships'), icon: Icons.school_outlined, onSeeAll: () => context.go('/explore?category=scholarships'))),
          SliverToBoxAdapter(child: _Carousel(provider: _homeFeedProvider((category: 'scholarships', status: null, featured: false, order: 'deadline')))),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.internships'), icon: Icons.badge_outlined, onSeeAll: () => context.go('/explore?category=internships'))),
          SliverToBoxAdapter(child: _Carousel(provider: _homeFeedProvider((category: 'internships', status: null, featured: false, order: 'deadline')))),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.schemes'), icon: Icons.account_balance_outlined, onSeeAll: () => context.go('/explore?category=government_schemes'))),
          SliverToBoxAdapter(child: _Carousel(provider: _homeFeedProvider((category: 'government_schemes', status: null, featured: false, order: 'deadline')))),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.recent'), icon: Icons.new_releases_outlined,
              onSeeAll: () => context.go('/explore'))),
          SliverToBoxAdapter(child: _Carousel(provider: _homeFeedProvider((category: null, status: null, featured: false, order: 'latest')))),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.progress'), icon: Icons.route_outlined, onSeeAll: () => context.go('/journey'))),
          SliverToBoxAdapter(child: _ProgressOverview(summary: summary.valueOrNull)),
          SliverToBoxAdapter(child: SectionHeader(context.t('home.notifications'), icon: Icons.notifications_none_rounded,
              onSeeAll: () => context.push('/notifications'))),
          SliverToBoxAdapter(child: _NotificationPreview()),
          SliverToBoxAdapter(child: _Announcements()),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.summary, required this.parallax});
  final String name;
  final HomeSummary? summary;
  final double parallax;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnimatedGradientBackground(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, top + 16, 20, 24),
        child: Stack(clipBehavior: Clip.none, children: [
          PositionedDirectional(
            end: -10,
            top: -10 - parallax * 0.3,
            child: Opacity(opacity: 0.9, child: Orb3D(size: 110, colors: const [AppColors.amber, AppColors.coral], icon: Icons.auto_awesome)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(context.t('app.name'), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const Spacer(),
              _Bell(unread: summary?.unread ?? 0),
            ]),
            const SizedBox(height: 18),
            Text(name.isEmpty ? context.t('home.greetingNoName') : context.t('home.greeting', {'name': name}),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(context.t('app.tagline'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            Semantics(
              textField: true,
              label: context.t('home.searchHint'),
              child: GestureDetector(
                onTap: () => context.go('/explore'),
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: fade(Colors.white, 0.16), borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: fade(Colors.white, 0.25))),
                  child: Row(children: [
                    const Icon(Icons.search_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(child: Text(context.t('home.searchHint'), style: const TextStyle(color: Colors.white70))),
                    const Icon(Icons.tune_rounded, color: Colors.white70),
                  ]),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell({required this.unread});
  final int unread;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.t('notif.title'),
        onPressed: () => context.push('/notifications'),
        icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_none_rounded, color: Colors.white)),
      );
}

class _QuickCategories extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <OpportunityCategory>[];
    if (cats.isEmpty) return const SizedBox(height: 16);
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final c = cats[i];
          final color = AppColors.fromHex(c.colorHex);
          return Semantics(
            button: true,
            label: c.name(context.isUrdu),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.go('/explore?category=${c.slug}'),
              child: SizedBox(
                width: 76,
                child: Column(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [Color.lerp(color, Colors.white, 0.3)!, color]),
                      boxShadow: [BoxShadow(color: fade(color, 0.35), blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: Icon(iconFor(c.icon), color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(c.name(context.isUrdu), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.summary});
  final HomeSummary? summary;
  @override
  Widget build(BuildContext context) {
    final s = summary;
    Widget stat(String label, int value, IconData icon, Color color, VoidCallback onTap) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            onTap: onTap,
            child: Column(children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text('$value', style: Theme.of(context).textTheme.titleLarge),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(children: [
        stat(context.t('home.interested'), s?.interested ?? 0, Icons.star_rounded, AppColors.amber, () => context.go('/saved?tab=interested')),
        const SizedBox(width: 10),
        stat(context.t('home.saved'), s?.saved ?? 0, Icons.bookmark_rounded, AppColors.teal, () => context.go('/saved')),
        const SizedBox(width: 10),
        stat(context.t('home.upcoming'), s?.upcomingDeadlines ?? 0, Icons.event_rounded, AppColors.coral, () => context.push('/calendar')),
        const SizedBox(width: 10),
        stat(context.t('home.newThisWeek'), s?.newThisWeek ?? 0, Icons.fiber_new_rounded, AppColors.lavender, () => context.go('/explore')),
      ]),
    );
  }
}

class _RecommendedList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(recommendedProvider);
    return recs.when(
      loading: () => const SliverToBoxAdapter(child: LoadingList(count: 2)),
      error: (e, _) => SliverToBoxAdapter(child: ErrorState(error: e, onRetry: () => ref.invalidate(recommendedProvider))),
      data: (list) => list.isEmpty
          ? SliverToBoxAdapter(child: EmptyState(message: context.t('home.completeProfile'), icon: Icons.person_search_rounded,
              action: () => context.push('/profile/edit'), actionLabel: context.t('profile.edit')))
          : SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.separated(
                itemCount: list.length.clamp(0, 5),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => OpportunityCard(
                  opportunity: list[i].opportunity,
                  reasons: list[i].recommendation.reasons,
                  eligibility: list[i].recommendation.eligibility,
                  index: i,
                ),
              ),
            ),
    );
  }
}

/// Interest picker on Home. This is where users choose interests (they are no longer edited in Edit Profile).
/// Choices are saved to user_interests, which recommendations and "new match" notifications already read.
class _InterestsPicker extends ConsumerStatefulWidget {
  const _InterestsPicker();
  @override
  ConsumerState<_InterestsPicker> createState() => _InterestsPickerState();
}

class _InterestsPickerState extends ConsumerState<_InterestsPicker> {
  final Set<String> _pending = {};

  String _label(BuildContext context, String interest) {
    final key = 'interest.$interest';
    final translated = context.t(key);
    return translated == key ? pretty(interest) : translated;
  }

  Future<void> _toggle(List<NamedItem> mine, String interest) async {
    final key = interest.trim().toLowerCase();
    if (key.isEmpty || _pending.contains(key)) return;
    final existing = findByName(mine, interest);
    final repo = ref.read(profileRepositoryProvider);
    setState(() => _pending.add(key));
    final ok = await runAction(
        context,
        () => existing == null
            ? repo.addInterest(interest.trim())
            : repo.removeInterest(existing.id));
    if (!mounted) return;
    setState(() => _pending.remove(key));
    if (ok) {
      ref.invalidate(fullProfileProvider); // also refreshes "Recommended for you"
      ref.invalidate(homeSummaryProvider);
    }
  }

  Future<void> _addCustom(List<NamedItem> mine) async {
    var text = '';
    final value = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(context.t('profile.addInterest')),
        content: TextField(
          autofocus: true,
          maxLength: 60,
          onChanged: (v) => text = v,
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(context.t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(d, text),
              child: Text(context.t('common.add'))),
        ],
      ),
    );
    final v = value?.trim() ?? '';
    if (v.isEmpty) return;
    if (!mounted) return;
    if (findByName(mine, v) != null) {
      return showSnack(context, context.t('common.alreadyAdded'));
    }
    await _toggle(mine, v);
  }

  @override
  Widget build(BuildContext context) {
    final fp = ref.watch(fullProfileProvider).valueOrNull;
    if (fp == null) return const SizedBox.shrink();
    final mine = fp.interests;
    final chosen = mine.map((i) => i.name.trim().toLowerCase()).toSet();
    final custom = mine.where((i) => !interestOptions.contains(i.name.trim().toLowerCase())).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.interests_outlined, color: AppColors.teal),
            const SizedBox(width: 8),
            Expanded(child: Text(context.t('home.interestsTitle'), style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 4),
          Text(context.t('home.interestsHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final o in interestOptions)
              FilterChip(
                label: Text(_label(context, o)),
                selected: chosen.contains(o),
                onSelected: _pending.contains(o) ? null : (_) => _toggle(mine, o),
              ),
            for (final i in custom)
              FilterChip(
                label: Text(i.name),
                selected: true,
                onSelected: _pending.contains(i.name.trim().toLowerCase()) ? null : (_) => _toggle(mine, i.name),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.t('profile.addInterest')),
              onPressed: () => _addCustom(mine),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Carousel extends ConsumerWidget {
  const _Carousel({required this.provider});
  final ProviderListenable<AsyncValue<List<Opportunity>>> provider;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(provider);
    return SizedBox(
      height: 190,
      child: v.when(
        loading: () => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => const Skeleton(width: 250, height: 180, radius: 22),
        ),
        error: (e, _) => Center(child: TextButton.icon(onPressed: () => ref.invalidate(_homeFeedProvider), icon: const Icon(Icons.refresh), label: Text(context.t('common.retry')))),
        data: (items) => items.isEmpty
            ? Center(child: Text(context.t('common.none'), style: Theme.of(context).textTheme.bodySmall))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => OpportunityMiniCard(opportunity: items[i]),
              ),
      ),
    );
  }
}

class _ProgressOverview extends StatelessWidget {
  const _ProgressOverview({required this.summary});
  final HomeSummary? summary;
  @override
  Widget build(BuildContext context) {
    final byStatus = summary?.applicationsByStatus ?? const {};
    final total = byStatus.values.fold<int>(0, (a, b) => a + b);
    final week = summary?.week ?? const {};
    const groups = {
      'planning': ['interested', 'planning', 'preparing_documents'],
      'applied': ['applied', 'under_review', 'shortlisted', 'interview_scheduled'],
      'selected': ['selected'],
      'rejected': ['rejected', 'withdrawn'],
    };
    const colors = {'planning': AppColors.lavender, 'applied': AppColors.teal, 'selected': AppColors.success, 'rejected': Colors.grey};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        onTap: () => context.go('/journey'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (total == 0)
            Text(context.t('journey.empty'))
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(children: [
                for (final g in groups.entries)
                  if (g.value.fold<int>(0, (a, s) => a + (byStatus[s] ?? 0)) > 0)
                    Expanded(
                      flex: g.value.fold<int>(0, (a, s) => a + (byStatus[s] ?? 0)),
                      child: Container(height: 12, color: colors[g.key]),
                    ),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 6, children: [
              for (final g in groups.entries)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[g.key], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${context.t('status.${g.key == 'planning' ? 'planning' : g.key}')}: ${g.value.fold<int>(0, (a, s) => a + (byStatus[s] ?? 0))}'),
                ]),
            ]),
          ],
          const Divider(height: 24),
          Text(context.t('home.weekly'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _WeekStat(Icons.visibility_outlined, week['viewed'] ?? 0, 'Viewed'),
            _WeekStat(Icons.bookmark_add_outlined, week['saved'] ?? 0, context.t('home.saved')),
            _WeekStat(Icons.star_outline_rounded, week['interested'] ?? 0, context.t('home.interested')),
            _WeekStat(Icons.send_outlined, week['applied'] ?? 0, context.t('status.applied')),
          ]),
        ]),
      ),
    );
  }
}

class _WeekStat extends StatelessWidget {
  const _WeekStat(this.icon, this.value, this.label);
  final IconData icon;
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, size: 20, color: AppColors.teal),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]);
}

class _NotificationPreview extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
    if (list.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(context.t('notif.empty')));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final n in list.take(3))
            ListTile(
              leading: Icon(n.isRead ? Icons.notifications_none : Icons.notifications_active_rounded, color: n.isRead ? null : AppColors.coral),
              title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(n.body, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(timeAgo(n.createdAt), style: Theme.of(context).textTheme.labelSmall),
              onTap: () => context.push(n.opportunityId != null ? '/opportunity/${n.opportunityId}' : '/notifications'),
            ),
        ]),
      ),
    );
  }
}

class _Announcements extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_announcementsProvider).valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(children: [
        for (final a in list) InfoBanner(text: '${a['title']}: ${a['body']}', color: AppColors.lavender, icon: Icons.campaign_outlined),
      ]),
    );
  }
}
