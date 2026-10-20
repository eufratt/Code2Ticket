import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency/currency.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/time/zones.dart';
import '../auth/auth_controller.dart';
import '../notifications/notification_permission.dart';

/// Pengaturan: mata uang dan zona waktu default (disimpan di app_settings, per perangkat), notifikasi pengingat + status izin, dan kunci biometric.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _canCheckBiometrics = false;
  bool _biometricEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final auth = context.read<AuthController>();
    final canCheck = await auth.isBiometricAvailable();
    final enabled = await auth.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _canCheckBiometrics = canCheck;
      _biometricEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _onToggle(bool value) async {
    final ok = await context.read<AuthController>().setBiometricEnabled(value);
    if (!mounted) return;
    // Jika otentikasi gagal/dibatalkan, pastikan switch tetap off
    setState(() => _biometricEnabled = ok ? value : false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: Column(children: [
        if (context.watch<AuthController?>()?.offlineSession ?? false) const OfflineBanner(),
        Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, 0, Spacing.screen, Spacing.s24),
        children: [
          const SectionHeader('Mata uang default'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
            child: RadioGroup<String>(
              groupValue: s.currency,
              onChanged: (v) => v == null ? null : s.setCurrency(v),
              child: Column(children: [
                for (final c in supportedCurrencies)
                  RadioListTile<String>(key: Key('currency_$c'), value: c, title: Text(currencyName(c))),
              ]),
            ),
          ),
          const SizedBox(height: Spacing.sectionGap),
          const SectionHeader('Zona waktu default'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
            child: RadioGroup<AppZone>(
              groupValue: s.zone,
              onChanged: (v) => v == null ? null : s.setZone(v),
              child: Column(children: [
                for (final z in AppZone.values)
                  RadioListTile<AppZone>(
                    key: Key('zone_${z.name}'),
                    value: z,
                    title: Text('${z.title} (${zoneAbbreviation(now, z)})'),
                    subtitle: Text(z.ianaName),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: Spacing.sectionGap),
          if (context.watch<NotificationService?>() case final n?) ...[
            const SectionHeader('Notifikasi'),
            _NotificationSection(service: n),
            const SizedBox(height: Spacing.sectionGap),
          ],
          const SectionHeader('Keamanan'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
            child: SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Kunci biometric'),
              subtitle: _canCheckBiometrics
                  ? const Text('Minta verifikasi biometric saat membuka aplikasi')
                  : const Text('Perangkat tidak mendukung biometric'),
              value: _biometricEnabled,
              onChanged: (_loading || !_canCheckBiometrics) ? null : _onToggle,
            ),
          ),
        ],
      )),
      ]),
    );
  }
}

/// Saklar pengingat + status izin notifikasi sistem (ikon + teks, bukan hanya warna) dan tombol ke pengaturan sistem.
class _NotificationSection extends StatelessWidget {
  const _NotificationSection({required this.service});
  final NotificationService service;

  @override
  Widget build(BuildContext context) {
    final granted = service.permissionGranted;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
      child: Column(children: [
        SwitchListTile(
          key: const Key('switch_reminders'),
          secondary: const Icon(Icons.alarm),
          title: const Text('Notifikasi pengingat'),
          subtitle: const Text('Ingatkan 1 jam sebelum draw dan saat draw dijalankan, untuk giveaway yang tiketnya kamu punya.'),
          value: service.remindersEnabled,
          onChanged: (v) async {
            // Menyalakan tanpa izin: jelaskan dulu, baru minta izin sistem. Mematikan membatalkan semua jadwal.
            if (v && !service.permissionGranted) await explainAndRequestNotifications(context);
            await service.setRemindersEnabled(v);
          },
        ),
        const Divider(indent: Spacing.s16, endIndent: Spacing.s16),
        ListTile(
          key: const Key('notif_permission_status'),
          leading: Icon(granted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
          title: Text(granted ? 'Izin notifikasi: diizinkan' : 'Izin notifikasi: belum diizinkan'),
          subtitle: Text(granted
              ? 'Tiket baru, pengingat, dan hasil draw muncul di bilah status.'
              : 'Notifikasi tetap tersedia di pusat notifikasi dalam aplikasi (ikon lonceng di Home).'),
        ),
        if (granted) ...[
          const Divider(indent: Spacing.s16, endIndent: Spacing.s16),
          ListTile(
            key: const Key('notif_exact_status'),
            leading: Icon(service.exactAllowed ? Icons.timer_outlined : Icons.timer_off_outlined),
            title: Text(service.exactAllowed ? 'Ketepatan pengingat: Tepat waktu' : 'Ketepatan pengingat: Bisa terlambat beberapa menit'),
            subtitle: Text(service.exactAllowed
                ? 'Pengingat muncul tepat di waktunya, juga saat aplikasi tertutup.'
                : 'Izinkan alarm tepat waktu supaya pengingat tidak terlambat.'),
          ),
          if (!service.exactAllowed)
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.s16, 0, Spacing.s16, Spacing.s8),
              child: PrimaryButton(
                key: const Key('request_exact_alarm'),
                label: 'Izinkan alarm tepat waktu',
                icon: Icons.alarm_on_outlined,
                variant: ButtonVariant.secondary,
                onPressed: service.requestExactAlarms,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.s16, 0, Spacing.s16, Spacing.s8),
            child: PrimaryButton(
              key: const Key('send_test_notification'),
              label: 'Kirim notifikasi tes (1 menit)',
              icon: Icons.notification_add_outlined,
              variant: ButtonVariant.secondary,
              onPressed: () async {
                final ok = await service.scheduleTestNotification();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Notifikasi tes dijadwalkan 1 menit lagi. Boleh tutup aplikasi.' : 'Izin notifikasi belum ada.')));
                }
              },
            ),
          ),
        ],
        if (!granted)
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.s16, 0, Spacing.s16, Spacing.s8),
            child: PrimaryButton(
              key: const Key('open_system_notif_settings'),
              label: 'Buka pengaturan sistem',
              icon: Icons.settings_outlined,
              variant: ButtonVariant.secondary,
              onPressed: service.openSystemSettings,
            ),
          ),
      ]),
    );
  }
}
