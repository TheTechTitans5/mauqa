import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/app_settings.dart';
import '../models/opportunity.dart';

/// Keeps a copy of the user's saved and interested opportunities so they can be read offline.
class OfflineCache {
  OfflineCache(this._prefs);
  final SharedPreferences _prefs;

  String _key(String userId, String list) => 'cache.$userId.$list';

  Future<void> putOpportunities(String userId, String list, List<Opportunity> items) =>
      _prefs.setString(_key(userId, list), jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'items': items.map((o) => o.toJson()).toList()}));

  ({List<Opportunity> items, DateTime? at})? getOpportunities(String userId, String list) {
    final raw = _prefs.getString(_key(userId, list));
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final items = (j['items'] as List).map((e) => Opportunity.fromJson((e as Map).cast<String, dynamic>())).toList();
      return (items: items, at: DateTime.tryParse(j['at'] as String? ?? ''));
    } catch (_) {
      return null;
    }
  }

  List<String> searchHistory() => _prefs.getStringList('search.history') ?? const [];

  Future<void> addSearch(String q) async {
    final t = q.trim();
    if (t.length < 2) return;
    final list = [t, ...searchHistory().where((x) => x.toLowerCase() != t.toLowerCase())].take(10).toList();
    await _prefs.setStringList('search.history', list);
  }

  Future<void> clearSearchHistory() => _prefs.remove('search.history');

  /// Comparison tray (ids only), persisted between sessions.
  List<String> compareIds() => _prefs.getStringList('compare.ids') ?? const [];
  Future<void> setCompareIds(List<String> ids) => _prefs.setStringList('compare.ids', ids);

  Future<void> clearUser(String userId) async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('cache.$userId.')).toList()) {
      await _prefs.remove(k);
    }
  }
}

final offlineCacheProvider = Provider<OfflineCache>((ref) => OfflineCache(ref.watch(sharedPrefsProvider)));
