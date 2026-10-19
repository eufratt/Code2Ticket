import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Tampil saat permintaan lambat (>5 detik) karena server gratis Render sedang bangun (cold start): AuthController.isWakingUp.
/// Tanpa AuthController di pohon widget (mis. pratinjau/tes komponen) tidak menampilkan apa pun.
class WakingUpNotice extends StatelessWidget {
  const WakingUpNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (!(context.watch<AuthController?>()?.isWakingUp ?? false)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s12),
      child: Semantics(
        liveRegion: true,
        child: Text(
          'Server sedang bangun, tunggu sebentar...',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.primary),
        ),
      ),
    );
  }
}
