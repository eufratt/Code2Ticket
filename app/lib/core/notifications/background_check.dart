import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/notifications/notification_models.dart';
import '../api/api_client.dart';
import '../db/local_db.dart';
import '../db/rate_cache.dart' show SettingsStore;
import '../json.dart';
import '../session/session_store.dart';
import 'notification_service.dart';

/// Fase B: pemeriksaan notifikasi server di latar belakang (Android, WorkManager, ~15 menit, butuh jaringan).
/// Berjalan di isolate terpisah tanpa UI: token dibaca dari penyimpanan aman, tidak pernah dicatat atau dikirim ke mana pun
/// selain header Authorization ke server sendiri. Tidak pernah melempar galat (tugas selalu selesai "berhasil";
/// periode berikutnya mencoba lagi). Batas "terakhir ditampilkan" per pengguna dibagi dengan pemeriksaan foreground,
/// dan id notifikasi deterministik, jadi tidak ada duplikat.
const String backgroundTaskName = 'c2t_check_notifications', backgroundUniqueName = 'c2t_notifications_poll';

/// Satu pemeriksaan. Bagian yang bisa diganti diberikan lewat parameter supaya bisa diuji tanpa plugin.
Future<void> runBackgroundCheck({
  required SessionStore session,
  required SettingsStore store,
  required ApiClient api,
  required NotificationGateway gateway,
}) async {
  final token = await session.readToken();
  final userId = await store.getSetting(NotifKeys.activeUser);
  if (token == null || userId == null) return; // belum masuk / sudah logout: tidak ada yang diperiksa
  try {
    final r = await api.get('/notifications?limit=50', token: token);
    if (r['ok'] == false) return;
    final items = parseList(r['data'], AppNotification.tryParse);
    final svc = NotificationService(gateway, store);
    await svc.init(); // menyiapkan plugin di isolate ini dan membaca status izin
    await svc.showServerNotifications(userId, items);
  } on InvalidSessionException {
    return; // sesi berakhir: biarkan aplikasi yang menanganinya saat dibuka
  } catch (_) {
    return; // offline (NetworkException), 403, atau galat lain: coba lagi pada periode berikutnya
  }
}

/// Titik masuk isolate latar belakang.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundCheck(
        session: SessionStore(),
        store: LocalDb.instance,
        api: ApiClient(),
        gateway: PluginNotificationGateway(),
      );
    } catch (_) {
      // sengaja diam: tidak ada token atau data pribadi yang boleh masuk log
    }
    return true;
  });
}

/// Mengatur pemeriksaan berkala. Hanya Android; platform lain tidak melakukan apa-apa.
abstract class BackgroundPoller {
  Future<void> start();
  Future<void> stop();
}

class WorkmanagerPoller implements BackgroundPoller {
  bool _initialized = false;
  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> start() async {
    if (!_supported) return;
    try {
      if (!_initialized) {
        await Workmanager().initialize(backgroundDispatcher);
        _initialized = true;
      }
      await Workmanager().registerPeriodicTask(
        backgroundUniqueName,
        backgroundTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {/* usaha terbaik: Fase A tetap jalan */}
  }

  @override
  Future<void> stop() async {
    if (!_supported) return;
    try {
      await Workmanager().cancelByUniqueName(backgroundUniqueName);
    } catch (_) {}
  }
}
