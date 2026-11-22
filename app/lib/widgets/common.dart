import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/strings.dart';
import '../core/theme/app_colors.dart';
import '../data/supabase_client.dart';
import 'visuals.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll, this.icon});
  final String title;
  final VoidCallback? onSeeAll;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 20, color: AppColors.teal), const SizedBox(width: 8)],
          Expanded(child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium))),
          if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: Text(context.t('common.seeAll'))),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.auto_awesome_rounded, this.action, this.actionLabel});
  final String message;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Orb3D(size: 110, icon: icon),
            const SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 16), FilledButton(onPressed: action, child: Text(actionLabel ?? ''))],
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final e = mapError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Orb3D(size: 96, colors: const [AppColors.coral, AppColors.amber], icon: e.isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded),
          const SizedBox(height: 16),
          Text(e.message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(context.t('common.retry'))),
        ]),
      ),
    );
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 4, this.height = 120});
  final int count;
  final double height;
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(20),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => Skeleton(height: height, radius: 22),
      );
}

/// Renders an AsyncValue with consistent loading / error / data states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, required this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;
  final Widget? loading;
  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => loading ?? const LoadingList(),
        error: (e, _) => ErrorState(error: e, onRetry: onRetry),
      );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, this.color = AppColors.amber, this.icon = Icons.info_outline_rounded});
  final String text;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: fade(color, 0.14), borderRadius: BorderRadius.circular(16), border: Border.all(color: fade(color, 0.5))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.teal, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: fade(color, 0.14), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );
}

/// Verification label using cautious wording (never claims fraud).
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.status, this.reported = false, this.demo = false});
  final String status;
  final bool reported;
  final bool demo;
  @override
  Widget build(BuildContext context) {
    if (demo) return const Pill('DEMO', color: AppColors.lavender, icon: Icons.science_outlined);
    if (reported) return Pill(context.t('verify.reported'), color: AppColors.coral, icon: Icons.flag_outlined);
    return switch (status) {
      'verified' => Pill(context.t('verify.verified'), color: AppColors.success, icon: Icons.verified_rounded),
      'pending_verification' => Pill(context.t('verify.pending'), color: AppColors.warning, icon: Icons.hourglass_top_rounded),
      'expired' => Pill(context.t('verify.expired'), color: Colors.grey, icon: Icons.history_rounded),
      'rejected' => Pill(context.t('verify.rejected'), color: AppColors.coral, icon: Icons.block_rounded),
      _ => Pill(context.t('verify.unverified'), color: Colors.blueGrey, icon: Icons.help_outline_rounded),
    };
  }
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? AppColors.coral : null));
}

/// Runs an async action with error reporting via snackbar. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showSnack(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, mapError(e).message, error: true);
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? body, String? confirmLabel, bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.t('common.cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.coral) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel ?? context.t('common.confirm')),
        ),
      ],
    ),
  );
  return r == true;
}
