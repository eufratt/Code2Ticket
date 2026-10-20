import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/notifications/notification_models.dart';
import '../../features/tickets/ticket_models.dart';
import '../db/rate_cache.dart' show SettingsStore;
import 'draw_spoiler.dart';
import 'reminder_planner.dart';

/// Saluran notifikasi Android (muncul di pengaturan sistem; teks Indonesia).
const String notificationChannelId = 'code2ticket_main',
    notificationChannelName = 'Tiket dan hasil draw',
    notificationChannelDescription = 'Tiket baru, pengingat draw, dan hasil undian.';

/// Kunci app_settings. Notifikasi terakhir yang sudah ditampilkan disimpan per pengguna; sisanya per perangkat.
abstract final class NotifKeys {
  static const reminders = 'notif_reminders'; // '1' (bawaan) / '0'
  static const permissionAsked = 'notif_permission_asked';
  static const lastShown = 'notif_last_shown'; // id notifikasi server terbesar yang sudah ditampilkan (per pengguna)
  static const activeUser = 'notif_active_user'; // id pengguna aktif, untuk pemeriksaan latar belakang (bukan token)
}

/// Batas tipis ke plugin supaya logika bisa diuji dengan gateway palsu.
abstract class NotificationGateway {
  /// [onTap] dipanggil dengan muatan saat notifikasi diketuk (aplikasi hidup).
  Future<void> init(void Function(String? payload) onTap);

  /// Muatan notifikasi yang meluncurkan aplikasi dari keadaan tertutup (null bila bukan dari notifikasi).
  Future<String?> launchPayload();
  Future<bool> areEnabled();
  Future<bool> requestPermission();
  Future<void> openSystemSettings();
  Future<void> show(int id, String title, String body, String payload);
  /// Alarm exact diizinkan sistem? (Android 12+ bisa dicabut pengguna; di bawahnya selalu true.)
  Future<bool> canScheduleExact();

  /// Membuka layar izin alarm exact (Android 12-12L tanpa USE_EXACT_ALARM); hasilnya dibaca ulang lewat [canScheduleExact].
  Future<void> requestExactAlarms();

  /// Menjadwalkan sesuai [mode]; bila exact ditolak sistem, jatuh ke inexact tanpa melempar.
  Future<void> schedule(PlannedReminder r, ScheduleMode mode);
  Future<List<int>> pendingIds();
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

/// Gateway nyata (flutter_local_notifications). Jadwal memakai waktu absolut (UTC); exactAllowWhileIdle bila alarm exact
/// diizinkan (USE_EXACT_ALARM / SCHEDULE_EXACT_ALARM di manifest), selain itu inexact yang bisa terlambat beberapa menit.
class PluginNotificationGateway implements NotificationGateway {
  PluginNotificationGateway([FlutterLocalNotificationsPlugin? plugin]) : _p = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _p;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      notificationChannelId,
      notificationChannelName,
      channelDescription: notificationChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init(void Function(String? payload) onTap) async {
    await _p.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => onTap(r.payload),
    );
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      notificationChannelId,
      notificationChannelName,
      description: notificationChannelDescription,
      importance: Importance.high,
    ));
  }

  @override
  Future<String?> launchPayload() async {
    final d = await _p.getNotificationAppLaunchDetails();
    return d != null && d.didNotificationLaunchApp ? d.notificationResponse?.payload : null;
  }

  @override
  Future<bool> areEnabled() async => await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async => await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<void> openSystemSettings() async {
    await _p.openAppNotificationSettings();
  }

  @override
  Future<void> show(int id, String title, String body, String payload) =>
      _p.show(id: id, title: title, body: body, notificationDetails: _details, payload: payload);

  @override
  Future<bool> canScheduleExact() async => await _android?.canScheduleExactNotifications() ?? false;

  @override
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  Future<void> _zoned(PlannedReminder r, AndroidScheduleMode mode) => _p.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: mode,
        payload: r.payload,
      );

  @override
  Future<void> schedule(PlannedReminder r, ScheduleMode mode) async {
    if (mode == ScheduleMode.exact) {
      try {
        return await _zoned(r, AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {/* izin dicabut di tengah jalan: jatuh ke inexact */}
    }
    await _zoned(r, AndroidScheduleMode.inexactAllowWhileIdle);
  }

  @override
  Future<List<int>> pendingIds() async => [for (final r in await _p.pendingNotificationRequests()) r.id];

  @override
  Future<void> cancel(int id) => _p.cancel(id: id);

  @override
  Future<void> cancelAll() => _p.cancelAll();
}

/// Notifikasi sistem: tiket baru (langsung), pengingat draw (terjadwal lokal), dan notifikasi server yang baru.
/// Semua pemanggilan aman: galat plugin/penyimpanan tidak pernah menjatuhkan aplikasi. Isi notifikasi tidak memuat
/// kode, token, atau data pribadi.
class NotificationService extends ChangeNotifier {
  NotificationService(this._gateway, this._store, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final NotificationGateway _gateway;
  final SettingsStore _store;
  final DateTime Function() _now;

  /// Saklar "Notifikasi pengingat" (bawaan aktif; per perangkat).
  bool remindersEnabled = true;

  /// Izin notifikasi sistem (POST_NOTIFICATIONS di Android 13+).
  bool permissionGranted = false;

  /// Alarm exact diizinkan sistem -> pengingat tepat waktu; false -> inexact (bisa terlambat beberapa menit).
  bool exactAllowed = false;
  ScheduleMode get scheduleMode => scheduleModeFor(exactAllowed: exactAllowed);

  /// Jadwal terakhir yang diterapkan; tidak diterapkan ulang bila sama (mencegah kerja berulang).
  String? _appliedSignature;
  List<Ticket> _tickets = const [];
  bool _ticketsKnown = false; // sebelum tiket dimuat, jadwal yang ada tidak disentuh (kecuali saklar dimatikan)
  String? _lastShownUser;
  int? _lastShown;

  Future<T?> _safe<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  /// Muatan notifikasi yang diketuk dan belum ditangani (juga yang meluncurkan aplikasi dari keadaan tertutup).
  /// Penanganan (membuka rute) ada di NotificationBridge; [onPending] memberi tahu bahwa ada muatan baru.
  String? pendingPayload;
  VoidCallback? onPending;

  void _handleTap(String? payload) {
    if (payload == null) return;
    pendingPayload = payload;
    onPending?.call();
  }

  /// Menyiapkan plugin dan membaca pengaturan. Mengembalikan muatan notifikasi yang meluncurkan aplikasi (bila ada).
  Future<String?> init() async {
    await _safe(() => _gateway.init(_handleTap));
    remindersEnabled = await _safe(() => _store.getSetting(NotifKeys.reminders)) != '0';
    await refreshPermission();
    final launch = await _safe<String?>(_gateway.launchPayload);
    _handleTap(launch);
    return launch;
  }

  Future<void> refreshPermission() async {
    final granted = await _safe(_gateway.areEnabled) ?? false;
    final exact = await _safe(_gateway.canScheduleExact) ?? false;
    if (granted != permissionGranted || exact != exactAllowed) {
      permissionGranted = granted;
      exactAllowed = exact;
      notifyListeners();
      if (granted) await _apply(force: true); // mode berubah -> jadwal dipasang ulang dengan mode baru
    }
  }

  /// Membuka layar izin alarm exact; status dibaca ulang saat app kembali ke foreground.
  Future<void> requestExactAlarms() async {
    await _safe(_gateway.requestExactAlarms);
    await refreshPermission();
  }

  /// Notifikasi tes 1 menit lagi lewat jalur penjadwalan yang sama dengan pengingat asli. false bila izin notifikasi belum ada.
  Future<bool> scheduleTestNotification() async {
    if (!permissionGranted) return false;
    await _safe(() => _gateway.schedule(testNotification(_now()), scheduleMode));
    return true;
  }

  /// true bila izin sudah ada atau baru diberikan. Dialog penjelasan ditampilkan UI SEBELUM memanggil ini.
  Future<bool> requestPermission() async {
    await _safe(() => _gateway.requestPermission());
    await refreshPermission();
    return permissionGranted;
  }

  Future<bool> wasPermissionAsked() async => await _safe(() => _store.getSetting(NotifKeys.permissionAsked)) == '1';
  Future<void> markPermissionAsked() => _safe(() => _store.setSetting(NotifKeys.permissionAsked, '1')).then((_) {});

  Future<void> openSystemSettings() => _safe(_gateway.openSystemSettings).then((_) {});

  Future<void> setRemindersEnabled(bool v) async {
    if (v == remindersEnabled) return;
    remindersEnabled = v;
    notifyListeners();
    await _safe(() => _store.setSetting(NotifKeys.reminders, v ? '1' : '0'));
    await _apply(force: true);
  }

  /// Menyelaraskan pengingat dengan tiket terbaru (tiap kali daftar tiket dimuat).
  Future<void> syncReminders(List<Ticket> tickets) {
    _tickets = tickets;
    _ticketsKnown = true;
    return _apply();
  }

  Future<void> _apply({bool force = false}) async {
    if (!_ticketsKnown && remindersEnabled) return;
    final desired = permissionGranted ? planReminders(_tickets, _now(), enabled: remindersEnabled) : const <PlannedReminder>[];
    final sig = '${scheduleMode.name}:${[for (final r in desired) '${r.id}@${r.at.millisecondsSinceEpoch}'].join(',')}';
    if (!force && sig == _appliedSignature) return;
    final pending = await _safe(_gateway.pendingIds) ?? const <int>[];
    final mode = scheduleMode;
    final diff = diffReminders(desired, pending);
    for (final id in diff.cancel) {
      await _safe(() => _gateway.cancel(id));
    }
    for (final r in diff.schedule) {
      await _safe(() => _gateway.schedule(r, mode));
      final gid = r.drawGiveawayId;
      if (gid != null && _activeUser != null) {
        await _safe(() => _store.setSetting(drawReminderKey(gid), '${r.at.millisecondsSinceEpoch}', userId: _activeUser!));
      }
    }
    if (desired.isEmpty) await _clearDrawMarkers(); // jadwal tidak dipasang: jalur server harus tetap tampil
    _appliedSignature = sig;
  }

  /// Notifikasi langsung: tiket berhasil dibuat.
  Future<void> onTicketCreated(RedeemedTicket t) async {
    if (!permissionGranted) return;
    final text = ticketCreatedText(t.ticketNumber, t.giveawayTitle);
    await _safe(() => _gateway.show(ticketCreatedId(t.id), text.title, text.body, giveawayPayload(t.giveawayId)));
  }

  /// Menampilkan notifikasi server yang baru (lihat [selectNewServer]); batas terakhir disimpan per pengguna.
  Future<void> showServerNotifications(String userId, List<AppNotification> items) async {
    if (_lastShownUser != userId) {
      _lastShownUser = userId;
      final v = await _safe(() => _store.getSetting(NotifKeys.lastShown, userId: userId));
      _lastShown = v == null ? null : int.tryParse(v);
    }
    final batch = selectNewServer(items, _lastShown);
    if (batch.lastShownId == (_lastShown ?? 0) && batch.show.isEmpty) return;
    // Simpan batas dulu: bila tampil gagal di tengah jalan, tidak ada duplikat pada pemeriksaan berikutnya.
    _lastShown = batch.lastShownId;
    await _safe(() => _store.setSetting(NotifKeys.lastShown, '${batch.lastShownId}', userId: userId));
    if (!permissionGranted) return;
    for (final n in batch.show) {
      final gid = n.giveawayId;
      var revealed = false;
      if (isDrawResultType(n.type) && gid != null) {
        revealed = await _safe(() => _store.getSetting(drawSeenKey(gid), userId: userId)) == '1';
        final marker = await _safe(() => _store.getSetting(drawReminderKey(gid), userId: userId));
        final fired = localDrawReminderFired(marker: marker, now: _now(), remindersEnabled: remindersEnabled);
        if (!shouldShowDrawResultNotification(giveawayId: gid, revealed: revealed, activeResultGiveawayId: activeResultGiveawayId, localReminderFired: fired)) continue;
      }
      final title = [for (final t in _tickets) if (t.giveawayId == gid) t.giveawayTitle].firstOrNull ?? '';
      final text = drawNotificationText(type: n.type, title: n.title, body: n.body, giveawayTitle: title, revealed: revealed);
      final id = gid != null && isDrawResultType(n.type) ? drawResultNotificationId(gid) : serverNotificationId(n.id);
      await _safe(() => _gateway.show(id, text.title, text.body, payloadForServer(n)));
    }
  }

  /// Giveaway yang layar hasilnya sedang terbuka (null = tidak ada); notifikasi hasil draw-nya tidak ditampilkan.
  /// Hanya di memori isolate utama (pemeriksaan latar belakang tidak mengetahuinya).
  String? activeResultGiveawayId;

  /// Reveal selesai: batalkan notifikasi hasil draw giveaway ini yang masih tampil atau terjadwal.
  Future<void> onDrawRevealed(String giveawayId, Iterable<int> serverNotificationIds) async {
    await _safe(() => _gateway.cancel(reminderId(giveawayId, ReminderKind.atDraw)));
    for (final id in serverNotificationIds) {
      await _safe(() => _gateway.cancel(serverNotificationId(id)));
    }
  }

  String? _activeUser;

  Future<void> _clearDrawMarkers() async {
    final u = _activeUser;
    if (u == null) return;
    for (final gid in {for (final t in _tickets) t.giveawayId}) {
      await _safe(() => _store.setSetting(drawReminderKey(gid), null, userId: u));
    }
  }

  /// Pengguna masuk: simpan id pengguna aktif (dibaca pemeriksaan latar belakang).
  Future<void> onSignedIn(String userId) {
    _activeUser = userId;
    return _safe(() => _store.setSetting(NotifKeys.activeUser, userId)).then((_) {});
  }

  /// Logout: semua jadwal dan notifikasi yang masih tampil dibatalkan, kondisi dihapus.
  Future<void> onLogout() async {
    await _clearDrawMarkers();
    _activeUser = null;
    _tickets = const [];
    _ticketsKnown = false;
    _appliedSignature = null;
    _lastShownUser = null;
    _lastShown = null;
    await _safe(_gateway.cancelAll);
    await _safe(() => _store.setSetting(NotifKeys.activeUser, null));
  }
}
