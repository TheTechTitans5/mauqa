import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Must be overridden in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('SharedPreferences not initialised'));

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.locale = const Locale('en'),
    this.textScale = 1.0,
    this.highContrast = false,
    this.simpleMode = false,
    this.lowData = false,
    this.reduceMotion = false,
    this.onboarded = false,
  });

  final ThemeMode themeMode;
  final Locale locale;
  final double textScale;
  final bool highContrast;
  final bool simpleMode;
  final bool lowData;
  final bool reduceMotion;
  final bool onboarded;

  bool get animationsOn => !reduceMotion && !lowData;

  AppSettings copyWith({ThemeMode? themeMode, Locale? locale, double? textScale, bool? highContrast, bool? simpleMode,
      bool? lowData, bool? reduceMotion, bool? onboarded}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale ?? this.locale,
        textScale: textScale ?? this.textScale,
        highContrast: highContrast ?? this.highContrast,
        simpleMode: simpleMode ?? this.simpleMode,
        lowData: lowData ?? this.lowData,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        onboarded: onboarded ?? this.onboarded,
      );
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier(this._prefs) : super(_read(_prefs));
  final SharedPreferences _prefs;

  static AppSettings _read(SharedPreferences p) => AppSettings(
        themeMode: ThemeMode.values[(p.getInt('themeMode') ?? 0).clamp(0, 2)],
        locale: Locale(p.getString('locale') ?? 'en'),
        textScale: (p.getDouble('textScale') ?? 1.0).clamp(0.85, 1.6),
        highContrast: p.getBool('highContrast') ?? false,
        simpleMode: p.getBool('simpleMode') ?? false,
        lowData: p.getBool('lowData') ?? false,
        reduceMotion: p.getBool('reduceMotion') ?? false,
        onboarded: p.getBool('onboarded') ?? false,
      );

  Future<void> update(AppSettings s) async {
    state = s;
    await Future.wait([
      _prefs.setInt('themeMode', s.themeMode.index),
      _prefs.setString('locale', s.locale.languageCode),
      _prefs.setDouble('textScale', s.textScale),
      _prefs.setBool('highContrast', s.highContrast),
      _prefs.setBool('simpleMode', s.simpleMode),
      _prefs.setBool('lowData', s.lowData),
      _prefs.setBool('reduceMotion', s.reduceMotion),
      _prefs.setBool('onboarded', s.onboarded),
    ]);
  }
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(ref.watch(sharedPrefsProvider)),
);
