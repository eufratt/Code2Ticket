import 'package:flutter/foundation.dart';

import '../currency/currency.dart';
import '../db/rate_cache.dart';
import '../time/zones.dart';

/// Preferensi tampilan per perangkat (tabel app_settings, user_id kosong): mata uang dan zona waktu default.
class SettingsController extends ChangeNotifier {
  SettingsController(this._store);
  final SettingsStore _store;

  static const currencyKey = 'display_currency';
  static const zoneKey = 'display_timezone';

  String currency = 'IDR';
  AppZone zone = AppZone.wib;
  bool loaded = false;

  Future<void> load() async {
    try {
      final c = await _store.getSetting(currencyKey);
      if (c != null && supportedCurrencies.contains(c)) currency = c;
      final z = await _store.getSetting(zoneKey);
      if (z != null) zone = AppZone.fromName(z);
    } catch (_) {/* pakai bawaan */}
    loaded = true;
    notifyListeners();
  }

  Future<void> setCurrency(String code) async {
    if (!supportedCurrencies.contains(code) || code == currency) return;
    currency = code;
    notifyListeners();
    try {
      await _store.setSetting(currencyKey, code);
    } catch (_) {}
  }

  Future<void> setZone(AppZone z) async {
    if (z == zone) return;
    zone = z;
    notifyListeners();
    try {
      await _store.setSetting(zoneKey, z.name);
    } catch (_) {}
  }
}
