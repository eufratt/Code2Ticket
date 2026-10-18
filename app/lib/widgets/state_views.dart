import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../features/auth/auth_controller.dart';

/// Tampil saat permintaan lambat karena server gratis Render sedang bangun (cold start).
class WakingUpNotice extends StatelessWidget {
  const WakingUpNotice({super.key});
  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthController>().isWakingUp) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Server sedang bangun, tunggu sebentar...',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// Penanda bahwa data berasal dari cache (jaringan gagal), dengan waktu terakhir diperbarui.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.cachedAt});
  final DateTime? cachedAt;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cachedAt == null
                    ? 'Data offline · mencoba memuat ulang otomatis'
                    : 'Data offline · diperbarui ${formatWib(cachedAt!)}',
                style: TextStyle(fontSize: 12.5, color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), WakingUpNotice()],
        ),
      );
}

class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

/// Layar sementara untuk fitur yang dikerjakan di milestone berikutnya.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.note});
  final String title, note;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyView(icon: Icons.construction, message: 'Segera hadir\n$note'),
      );
}
