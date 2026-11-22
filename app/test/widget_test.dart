import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mauqa/core/l10n/strings.dart';
import 'package:mauqa/core/settings/app_settings.dart';
import 'package:mauqa/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app(Widget child, {Locale locale = const Locale('en')}) async {
  SharedPreferences.setMockInitialValues({'reduceMotion': true});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [S.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('verification badges use cautious labels', (tester) async {
    await tester.pumpWidget(await _app(const Column(children: [
      VerificationBadge(status: 'verified'),
      VerificationBadge(status: 'pending_verification'),
      VerificationBadge(status: 'unverified', reported: true),
      VerificationBadge(status: 'verified', demo: true),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Verified official source'), findsOneWidget);
    expect(find.text('Pending verification'), findsOneWidget);
    expect(find.text('Reported for review'), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget, reason: 'demo records are never shown as verified');
    expect(find.textContaining('fraud', findRichText: true), findsNothing);
  });

  testWidgets('Urdu locale renders right-to-left with translated strings', (tester) async {
    await tester.pumpWidget(await _app(const VerificationBadge(status: 'verified'), locale: const Locale('ur')));
    await tester.pumpAndSettle();
    expect(find.text('تصدیق شدہ سرکاری ذریعہ'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.byType(VerificationBadge)));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('empty state shows message and action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(await _app(EmptyState(message: 'Nothing yet', action: () => tapped = true, actionLabel: 'Add')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing yet'), findsOneWidget);
    await tester.tap(find.text('Add'));
    expect(tapped, isTrue);
  });

  test('every Urdu key exists in English (fallback safety)', () {
    final en = S(const Locale('en'));
    final ur = S(const Locale('ur'));
    for (final key in ['nav.home', 'opp.apply', 'elig.probably', 'remind.7', 'status.selected', 'settings.deleteConfirm']) {
      expect(en.t(key), isNot(key));
      expect(ur.t(key), isNot(key));
    }
    expect(en.t('common.daysLeft', {'n': 3}), '3 days left');
    expect(ur.t('missing.key'), 'missing.key');
  });
}
