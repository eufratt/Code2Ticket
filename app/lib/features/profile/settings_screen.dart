import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/currency/currency.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/time/zones.dart';
import '../auth/auth_controller.dart';

/// Pengaturan: mata uang dan zona waktu default (disimpan di app_settings, per perangkat) + kunci biometric.
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
      body: ListView(
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
      ),
    );
  }
}
