import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

enum StatusTone { info, success, warning, error, neutral }

/// Semua status pada tabel DESIGN.md bagian 4. Status selalu berupa teks (dan ikon), tidak hanya warna.
enum AppStatus {
  giveawayUpcoming('Segera dimulai', StatusTone.info, Icons.schedule),
  giveawayActive('Aktif', StatusTone.success, Icons.fiber_manual_record),
  giveawayDrawSoon('Draw segera', StatusTone.warning, Icons.hourglass_top),
  giveawayWaitingDraw('Menunggu draw', StatusTone.warning, Icons.hourglass_top),
  giveawayFinished('Selesai', StatusTone.neutral, Icons.flag_outlined),
  ticketEligible('Eligible', StatusTone.info, Icons.confirmation_number_outlined),
  ticketWaiting('Menunggu draw', StatusTone.warning, Icons.hourglass_top),
  ticketWon('Menang', StatusTone.success, Icons.emoji_events),
  ticketNotSelected('Tidak terpilih', StatusTone.neutral, Icons.remove_circle_outline),
  verified('Terverifikasi', StatusTone.success, Icons.verified),
  mismatch('Tidak cocok', StatusTone.error, Icons.error_outline);

  const AppStatus(this.label, this.tone, this.icon);
  final String label;
  final StatusTone tone;
  final IconData icon;
}

/// Pil kecil (label 12/600, radius penuh) dengan ikon.
class StatusChip extends StatelessWidget {
  const StatusChip(AppStatus status, {super.key})
      : label = null,
        tone = null,
        icon = null,
        _status = status;

  /// Untuk label di luar tabel status (mis. peran pengguna).
  const StatusChip.custom({super.key, required String this.label, required StatusTone this.tone, this.icon}) : _status = null;

  final AppStatus? _status;
  final String? label;
  final StatusTone? tone;
  final IconData? icon;

  static StatusColors colorsOf(AppColors c, StatusTone tone) => switch (tone) {
        StatusTone.info => c.statusInfo,
        StatusTone.success => c.statusSuccess,
        StatusTone.warning => c.statusWarning,
        StatusTone.error => c.statusError,
        StatusTone.neutral => c.statusNeutral,
      };

  @override
  Widget build(BuildContext context) {
    final text = _status?.label ?? label!;
    final iconData = _status?.icon ?? icon;
    final sc = colorsOf(context.colors, _status?.tone ?? tone!);
    return DecoratedBox(
      decoration: ShapeDecoration(color: sc.bg, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s8 + 2, vertical: Spacing.s4 + 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              Icon(iconData, size: iconData == Icons.fiber_manual_record ? 10 : 14, color: sc.fg),
              const SizedBox(width: Spacing.s4),
            ],
            Flexible(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.label.copyWith(color: sc.fg)),
            ),
          ],
        ),
      ),
    );
  }
}
