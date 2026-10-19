import 'package:code2ticket/core/currency/rates_controller.dart';
import 'package:code2ticket/core/db/rate_cache.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/core/time/zones.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

class MemorySettings implements SettingsStore {
  final Map<String, String> values = {};
  bool failing = false;

  @override
  Future<String?> getSetting(String key, {String userId = ''}) async {
    if (failing) throw StateError('settings rusak');
    return values['$userId|$key'];
  }

  @override
  Future<void> setSetting(String key, String? value, {String userId = ''}) async {
    if (failing) throw StateError('settings rusak');
    if (value == null) {
      values.remove('$userId|$key');
    } else {
      values['$userId|$key'] = value;
    }
  }
}

class MemoryRates implements RateCache {
  final List<CachedRate> rows = [];
  bool failing = false;

  @override
  Future<void> saveRates(String base, List<CachedRate> rates) async {
    if (failing) throw StateError('cache kurs rusak');
    for (final r in rates) {
      rows.removeWhere((x) => x.target == r.target);
      rows.add(r);
    }
  }

  @override
  Future<List<CachedRate>> loadRates(String base) async {
    if (failing) throw StateError('cache kurs rusak');
    return List.of(rows);
  }
}

/// Klien yang selalu gagal: tes tidak boleh menyentuh jaringan.
http.Client offlineClient() => MockClient((_) async => throw http.ClientException('offline'));

/// Penyedia pengaturan tampilan + kurs untuk tes layar. Tanpa kurs: nilai ditampilkan dalam USD.
List<SingleChildWidget> displayProviders({SettingsController? settings, RatesController? rates}) {
  initTimeZones();
  return [
    ChangeNotifierProvider<SettingsController>.value(value: settings ?? SettingsController(MemorySettings())),
    ChangeNotifierProvider<RatesController>.value(value: rates ?? RatesController(MemoryRates(), client: offlineClient())),
  ];
}
