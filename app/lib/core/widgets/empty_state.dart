import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'primary_button.dart';
import 'waking_up_notice.dart';

/// Keadaan kosong: ikon besar (64), judul, penjelasan satu kalimat, satu aksi opsional.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction, this.compact = false});
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Tanpa pemusatan dan gulir sendiri, untuk dipasang di dalam ListView.
  final bool compact;

  @override
  Widget build(BuildContext context) => _StateLayout(
        compact: compact,
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        iconColor: context.colors.muted,
      );
}

/// Keadaan galat: pesan jelas + "Coba lagi". Bila server sedang bangun (> 5 detik) ditambah keterangannya.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry, this.title = 'Gagal memuat', this.compact = false});
  final String message;
  final String title;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => _StateLayout(
        compact: compact,
        icon: Icons.cloud_off,
        title: title,
        message: message,
        actionLabel: 'Coba lagi',
        onAction: onRetry,
        iconColor: context.colors.error,
        footer: const WakingUpNotice(),
      );
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.compact,
    this.message,
    this.actionLabel,
    this.onAction,
    this.footer,
  });
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color iconColor;
  final bool compact;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final column = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: Icon(icon, size: 64, color: iconColor)),
            const SizedBox(height: Spacing.s16),
            Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
            if (message != null) ...[
              const SizedBox(height: Spacing.s8),
              Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Spacing.s24),
              PrimaryButton(label: actionLabel!, onPressed: onAction, expand: false),
            ],
            ?footer,
          ],
        );
    if (compact) return Padding(padding: const EdgeInsets.all(Spacing.s16), child: column);
    return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(Spacing.s24), child: column));
  }
}
