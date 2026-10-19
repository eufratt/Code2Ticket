import 'package:flutter/material.dart';

import '../display.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Penanda bahwa data berasal dari cache (jaringan gagal): strip tipis di atas konten, warna peringatan lembut.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.cachedAt});
  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final sc = context.colors.statusWarning;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: sc.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s8),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: sc.fg),
              const SizedBox(width: Spacing.s8),
              Expanded(
                child: Text(
                  cachedAt == null
                      ? 'Data offline · mencoba memuat ulang otomatis'
                      : 'Data offline · diperbarui ${context.when(cachedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: sc.fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
