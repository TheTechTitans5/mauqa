import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/l10n/strings.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'data/push_service.dart';
import 'data/repositories/notification_repository.dart';
import 'data/supabase_client.dart';

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref.watch(notificationRepositoryProvider)));

class MauqaApp extends ConsumerStatefulWidget {
  const MauqaApp({super.key});
  @override
  ConsumerState<MauqaApp> createState() => _MauqaAppState();
}

class _MauqaAppState extends ConsumerState<MauqaApp> {
  @override
  void initState() {
    super.initState();
    if (!Env.isConfigured) return;
    final client = Supabase.instance.client;
    client.auth.onAuthStateChange.listen((s) {
      final router = ref.read(routerProvider);
      if (s.event == AuthChangeEvent.passwordRecovery) router.go('/reset-password');
      if (s.event == AuthChangeEvent.signedIn) {
        ref.read(pushServiceProvider).initAndRegister(onOpen: (m) {
          final id = m.data['opportunity_id'];
          router.push(id is String && id.isNotEmpty ? '/opportunity/$id' : '/notifications');
        });
        _applyServerLanguage(client);
      }
    });
    if (client.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(pushServiceProvider).initAndRegister());
    }
  }

  /// Uses the language chosen at sign-up the first time this device sees the account.
  Future<void> _applyServerLanguage(SupabaseClient client) async {
    final settings = ref.read(appSettingsProvider);
    if (settings.onboarded) return;
    try {
      final row = await client.from('profiles').select('preferred_language').eq('id', requireUserId(client)).single();
      final lang = (row['preferred_language'] as String?) ?? 'en';
      await ref.read(appSettingsProvider.notifier).update(settings.copyWith(locale: Locale(lang), onboarded: true));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appSettingsProvider);
    final router = ref.watch(routerProvider);
    final urdu = s.locale.languageCode == 'ur';
    return MaterialApp.router(
      title: 'Mauqa',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: s.locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [S.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      themeMode: s.themeMode,
      theme: AppTheme.build(brightness: Brightness.light, highContrast: s.highContrast, isUrdu: urdu),
      darkTheme: AppTheme.build(brightness: Brightness.dark, highContrast: s.highContrast, isUrdu: urdu),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scale = s.textScale * (s.simpleMode ? 1.12 : 1.0);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(scale.clamp(0.85, 1.8)),
            disableAnimations: mq.disableAnimations || !s.animationsOn,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
