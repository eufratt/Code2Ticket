import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_controller.dart';

/// Sementara (M2). Diganti bottom navigation 5 tab di M3.
class HomePlaceholder extends StatefulWidget {
  const HomePlaceholder({super.key});

  @override
  State<HomePlaceholder> createState() => _HomePlaceholderState();
}

class _HomePlaceholderState extends State<HomePlaceholder> {
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
    final auth = context.read<AuthController>();
    final ok = await auth.setBiometricEnabled(value);
    if (!mounted) return;
    if (ok) {
      setState(() => _biometricEnabled = value);
    } else {
      // Jika otentikasi gagal/dibatalkan, pastikan switch tetap off
      setState(() => _biometricEnabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final u = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Code2Ticket')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Halo, ${u?.fullName ?? '-'}',
                  style: Theme.of(context).textTheme.titleLarge),
              Text('@${u?.username} · ${u?.role} · Level ${u?.level}'),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: auth.logout,
                child: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
