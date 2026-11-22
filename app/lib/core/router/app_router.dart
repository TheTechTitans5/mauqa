import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_client.dart';
import '../../features/auth/auth_screens.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/community/community_screens.dart';
import '../../features/compare/compare_screen.dart';
import '../../features/documents/documents_screen.dart';
import '../../features/eligibility/eligibility_screen.dart';
import '../../features/explore/explore_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/journey/journey_screens.dart';
import '../../features/notifications/notifications_screens.dart';
import '../../features/opportunity/opportunity_detail_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/settings/settings_screens.dart';
import '../../features/shell/main_shell.dart';
import '../../features/tools/cv_builder_screen.dart';
import '../../features/tools/tools_screens.dart';
import '../config/env.dart';

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> s) {
    _sub = s.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const _authPaths = {'/welcome', '/login', '/signup', '/otp', '/forgot'};

final routerProvider = Provider<GoRouter>((ref) {
  if (!Env.isConfigured) {
    return GoRouter(initialLocation: '/setup-required', routes: [
      GoRoute(path: '/setup-required', builder: (_, __) => const SetupRequiredScreen()),
    ]);
  }
  final client = ref.watch(supabaseProvider);
  final refresh = _AuthRefresh(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      if (!Env.isConfigured) return state.matchedLocation == '/setup-required' ? null : '/setup-required';
      final loggedIn = client.auth.currentSession != null;
      final loc = state.matchedLocation;
      final onAuth = _authPaths.contains(loc);
      if (!loggedIn && !onAuth && loc != '/reset-password' && loc != '/legal') return '/welcome';
      if (loggedIn && onAuth) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/setup-required', builder: (_, __) => const SetupRequiredScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/otp', builder: (_, s) => OtpScreen(phone: s.uri.queryParameters['phone'] ?? '')),
      GoRoute(path: '/forgot', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/legal', builder: (_, s) => LegalScreen(kind: s.uri.queryParameters['kind'] ?? 'terms')),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/explore', builder: (_, s) => ExploreScreen(
                  initialCategory: s.uri.queryParameters['category'],
                  initialQuery: s.uri.queryParameters['q'],
                  initialStatus: s.uri.queryParameters['status'],
                )),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/saved', builder: (_, s) => SavedScreen(initialTab: s.uri.queryParameters['tab']))]),
          StatefulShellBranch(routes: [GoRoute(path: '/journey', builder: (_, __) => const JourneyScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(path: '/opportunity/:id', builder: (_, s) => OpportunityDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/opportunity/:id/eligibility', builder: (_, s) => EligibilityScreen(opportunityId: s.pathParameters['id']!)),
      GoRoute(path: '/journey/new', builder: (_, s) => ApplicationFormScreen(opportunityId: s.uri.queryParameters['opportunityId'])),
      GoRoute(path: '/journey/:id', builder: (_, s) => ApplicationDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/profile/edit', builder: (_, s) => EditProfileScreen(section: s.uri.queryParameters['section'])),
      GoRoute(path: '/documents', builder: (_, s) => DocumentsScreen(checklistFor: s.uri.queryParameters['opportunityId'])),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/notifications/prefs', builder: (_, __) => const NotificationPrefsScreen()),
      GoRoute(path: '/compare', builder: (_, __) => const CompareScreen()),
      GoRoute(path: '/tools', builder: (_, __) => const ToolsHubScreen()),
      GoRoute(path: '/tools/cv', builder: (_, __) => const CvBuilderScreen()),
      GoRoute(path: '/tools/cover-letter', builder: (_, s) => CoverLetterScreen(opportunityId: s.uri.queryParameters['opportunityId'])),
      GoRoute(path: '/tools/guides', builder: (_, s) => GuidesScreen(category: s.uri.queryParameters['category'])),
      GoRoute(path: '/tools/guides/:slug', builder: (_, s) => GuideDetailScreen(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/tools/interview', builder: (_, __) => const InterviewPrepScreen()),
      GoRoute(path: '/tools/readiness', builder: (_, s) => ReadinessScreen(opportunityId: s.uri.queryParameters['opportunityId'])),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/settings/accessibility', builder: (_, __) => const AccessibilityScreen()),
      GoRoute(path: '/settings/privacy', builder: (_, __) => const PrivacyScreen()),
      GoRoute(path: '/settings/password', builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(path: '/settings/feedback', builder: (_, s) => FeedbackScreen(kind: s.uri.queryParameters['kind'] ?? 'feedback')),
      GoRoute(path: '/community', builder: (_, __) => const CommunityScreen()),
      GoRoute(path: '/community/new', builder: (_, __) => const SubmitStoryScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(appBar: AppBar(), body: Center(child: Text('Page not found: ${state.uri.path}'))),
  );
});
