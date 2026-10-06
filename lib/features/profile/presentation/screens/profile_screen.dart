import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:code2ticket/features/auth/presentation/controllers/auth_controller.dart';
import 'package:code2ticket/features/auth/presentation/controllers/auth_state.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _biometricEnabled = false;
  bool _isLoadingBiometric = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricPreference();
  }

  Future<void> _loadBiometricPreference() async {
    final enabled = await ref.read(authControllerProvider.notifier).isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricEnabled = enabled;
        _isLoadingBiometric = false;
      });
    }
  }

  Future<void> _handleToggleBiometric(bool value) async {
    final bioService = ref.read(biometricServiceProvider);
    final canBio = await bioService.isBiometricAvailable();

    if (value && !canBio) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perangkat tidak mendukung atau belum mengatur sidik jari / wajah.'),
          ),
        );
      }
      return;
    }

    if (value) {
      final authenticated = await bioService.authenticate(
        localizedReason: 'Konfirmasi biometrik untuk mengaktifkan kunci keamanan',
      );
      if (!authenticated) return;
    }

    await ref.read(authControllerProvider.notifier).setBiometricEnabled(value);
    if (mounted) {
      setState(() {
        _biometricEnabled = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Kunci biometrik aktif' : 'Kunci biometrik dinonaktifkan'),
        ),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Keluar'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authControllerProvider.notifier).logout();
              if (mounted) {
                context.go('/login');
              }
            },
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState is Authenticated ? authState.user : null;

    final displayName = user?.username ?? 'Pengguna Code2Ticket';
    final displayEmail = user?.email ?? 'user@code2ticket.app';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Pengguna'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 52,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primaryPurple,
                      child: const Icon(
                        Icons.verified_user_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              displayName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              displayEmail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.lightTextSecondary,
                  ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: const Text('Riwayat Aktivitas'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Riwayat aktivitas tersinkronisasi')),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Skor Mini Game'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/game'),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint_rounded),
                    title: const Text('Kunci Ulang Biometrik'),
                    subtitle: const Text('Kunci aplikasi saat dibuka kembali'),
                    value: _biometricEnabled,
                    onChanged: _isLoadingBiometric ? null : _handleToggleBiometric,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.currency_exchange_rounded),
                    title: const Text('Mata Uang & Kurs'),
                    subtitle: const Text('USD ke IDR via Frankfurter API'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {},
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded, color: AppColors.errorRed),
                    title: const Text(
                      'Keluar Akun',
                      style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold),
                    ),
                    onTap: _showLogoutDialog,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
