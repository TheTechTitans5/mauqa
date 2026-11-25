import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mauqa/core/l10n/strings.dart';
import 'package:mauqa/core/settings/app_settings.dart';
import 'package:mauqa/data/models/profile.dart';
import 'package:mauqa/data/repositories/profile_repository.dart';
import 'package:mauqa/features/profile/edit_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

FullProfile _profile({String? gender, List<NamedItem> skills = const []}) => FullProfile(
      profile: Profile(id: 'u1', fullName: 'Test User', gender: gender, address: 'House 1, Street 2'),
      education: const [],
      skills: skills,
      interests: [NamedItem('i1', 'scholarships')],
      experiences: const [],
      certifications: const [],
      completion: 40,
    );

/// Edit Profile with an in-memory profile (no Supabase calls unless a save succeeds validation).
Future<Widget> _screen(FullProfile fp, {String? section, Locale locale = const Locale('en')}) async {
  SharedPreferences.setMockInitialValues({'reduceMotion': true});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      fullProfileProvider.overrideWith((ref) async => fp),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [S.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: EditProfileScreen(section: section),
    ),
  );
}

void main() {
  testWidgets('gender is required: no empty or "prefer not to say" choice, and Save is blocked until chosen', (tester) async {
    await tester.pumpWidget(await _screen(_profile(gender: 'prefer_not_to_say')));
    await tester.pumpAndSettle();

    expect(find.text('Gender'), findsWidgets);
    expect(find.text('Gender (optional)'), findsNothing);

    await tester.ensureVisible(find.text('Save').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();
    expect(find.text('Please choose your gender'), findsWidgets, reason: 'inline error and snackbar');

    await tester.ensureVisible(find.byKey(const ValueKey('profile-gender')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-gender')));
    await tester.pumpAndSettle();
    expect(find.text('Prefer not to say'), findsNothing);
    expect(find.text('Transgender'), findsWidgets);
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();
    expect(find.text('Female'), findsWidgets);

    await tester.pump(const Duration(seconds: 5)); // let the snackbar close
    await tester.pumpAndSettle();
  });

  testWidgets('no Address field, no Interests card, and the Languages hint has no Punjabi', (tester) async {
    await tester.pumpWidget(await _screen(_profile(gender: 'female')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Address'), findsNothing);
    expect(find.text('House 1, Street 2'), findsNothing, reason: 'saved address is kept in the database but not shown');
    expect(find.text('Interests'), findsNothing);
    expect(find.textContaining('Punjabi'), findsNothing);
    final hints = tester.widgetList<TextField>(find.byType(TextField)).map((t) => t.decoration?.hintText).whereType<String>();
    expect(hints, contains('Urdu, English'));
  });

  testWidgets('skills show three groups with their own inputs and suggestions', (tester) async {
    await tester.pumpWidget(await _screen(
      _profile(gender: 'male', skills: [NamedItem('s1', 'Python', category: 'curricular'), NamedItem('s2', 'Teaching')]),
      section: 'skills',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Curricular (academic & technical)'), findsOneWidget);
    expect(find.text('Co-curricular'), findsOneWidget);
    expect(find.text('Other skills'), findsOneWidget);
    for (final g in skillGroups) {
      expect(find.byKey(ValueKey('skill-input-$g')), findsOneWidget);
    }
    // chosen skills are chips in their group; a chosen skill is no longer offered as a suggestion
    expect(find.widgetWithText(InputChip, 'Python'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Python'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Teaching'), findsOneWidget, reason: 'ungrouped skill shows under Other');
    // suggestions from each group
    expect(find.widgetWithText(ActionChip, 'Java'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Model United Nations'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Freelancing'), findsOneWidget);
  });

  testWidgets('Urdu: personal form renders right-to-left with translated labels', (tester) async {
    await tester.pumpWidget(await _screen(_profile(gender: 'female'), locale: const Locale('ur')));
    await tester.pumpAndSettle();

    expect(find.text('جنس'), findsWidgets);
    expect(find.text('جنس (اختیاری)'), findsNothing);
    expect(find.text('پتہ (اختیاری)'), findsNothing);
    expect(find.text('خاتون'), findsWidgets);
    expect(Directionality.of(tester.element(find.byType(EditProfileScreen))), TextDirection.rtl);
  });

  testWidgets('Urdu: skill groups and suggestions are translated, technical names stay English', (tester) async {
    await tester.pumpWidget(await _screen(
      _profile(gender: 'female', skills: [NamedItem('s1', 'Leadership', category: 'co_curricular')]),
      section: 'skills',
      locale: const Locale('ur'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('نصابی (تعلیمی و تکنیکی)'), findsOneWidget);
    expect(find.text('ہم نصابی'), findsOneWidget);
    expect(find.text('دیگر مہارتیں'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'قیادت'), findsOneWidget, reason: 'saved English skill shown in Urdu');
    expect(find.widgetWithText(ActionChip, 'Python'), findsOneWidget, reason: 'technical names stay in English');
    expect(Directionality.of(tester.element(find.byType(EditProfileScreen))), TextDirection.rtl);
  });
}
