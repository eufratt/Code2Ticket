import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import '../theme/category_style.dart';
import 'status_chip.dart';

/// Radius lekukan sobekan (DESIGN.md 4).
const double kTicketNotch = 10;

/// Kartu tiket dua bagian. Atas: nama giveaway, kategori, nilai hadiah. Bawah (setelah garis putus): nomor tiket
/// (display, tabular) dan status. Lekukan setengah lingkaran di kedua sisi pada garis putus, digambar dengan
/// CustomPainter/ClipPath. Seluruh kartu dapat diketuk.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.title,
    required this.category,
    required this.ticketNumber,
    required this.status,
    this.prizeText,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String? category;

  /// Sudah diformat, mis. "#000012".
  final String ticketNumber;
  final AppStatus status;
  final String? prizeText;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    final style = CategoryStyle.of(category);

    final top = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: style.gradient, borderRadius: Radii.buttonAll),
            child: SizedBox(width: 44, height: 44, child: Icon(style.icon, color: Colors.white, size: 24)),
          ),
        ),
        const SizedBox(width: Spacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              if (prizeText != null && prizeText!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.s4),
                  child: Text(prizeText!, style: theme.textTheme.bodyMedium?.copyWith(color: c.accentText, fontWeight: FontWeight.w600)),
                ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.s4),
                  child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                ),
            ],
          ),
        ),
        if (onTap != null) Icon(Icons.chevron_right, color: c.muted),
      ],
    );

    final bottom = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.s12,
      runSpacing: Spacing.s8,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nomor tiket', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
            Text(
              ticketNumber,
              key: const Key('ticket_card_number'),
              style: AppTypography.tabular(theme.textTheme.displaySmall!),
            ),
          ],
        ),
        StatusChip(status),
      ],
    );

    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Part(top: true, onTap: onTap, child: top),
            _Part(top: false, onTap: onTap, child: bottom),
          ],
        ),
      ),
    );
  }
}

class _Part extends StatelessWidget {
  const _Part({required this.top, required this.child, this.onTap});
  final bool top;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      painter: _TicketPartPainter(top: top, colors: c),
      child: ClipPath(
        clipper: _TicketPartClipper(top: top),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            excludeFromSemantics: !top,
            child: Padding(
              padding: EdgeInsets.fromLTRB(Spacing.s16, top ? Spacing.s16 : Spacing.s16 + kTicketNotch / 2, Spacing.s16, top ? Spacing.s16 + kTicketNotch / 2 : Spacing.s16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Jalur satu bagian kartu: sudut membulat di sisi luar, lekukan setengah lingkaran di sisi garis putus.
Path ticketPartPath(Size size, {required bool top}) {
  final w = size.width, h = size.height;
  const r = Radii.card, n = kTicketNotch;
  const radius = Radius.circular(r);
  const notch = Radius.circular(n);
  final p = Path();
  if (top) {
    p
      ..moveTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: radius)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: radius)
      ..lineTo(w, h - n)
      ..arcToPoint(Offset(w - n, h), radius: notch, clockwise: false)
      ..lineTo(n, h)
      ..arcToPoint(Offset(0, h - n), radius: notch, clockwise: false)
      ..close();
  } else {
    p
      ..moveTo(0, n)
      ..arcToPoint(const Offset(n, 0), radius: notch, clockwise: false)
      ..lineTo(w - n, 0)
      ..arcToPoint(Offset(w, n), radius: notch, clockwise: false)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: radius)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: radius)
      ..close();
  }
  return p;
}

class _TicketPartClipper extends CustomClipper<Path> {
  const _TicketPartClipper({required this.top});
  final bool top;
  @override
  Path getClip(Size size) => ticketPartPath(size, top: top);
  @override
  bool shouldReclip(_TicketPartClipper old) => old.top != top;
}

class _TicketPartPainter extends CustomPainter {
  const _TicketPartPainter({required this.top, required this.colors});
  final bool top;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ticketPartPath(size, top: top);
    // Bayangan: tidak digambar melewati sisi garis putus supaya dua bagian menyatu.
    canvas.save();
    canvas.clipRect(top ? Rect.fromLTRB(-24, -24, size.width + 24, size.height) : Rect.fromLTRB(-24, 0, size.width + 24, size.height + 24));
    for (final s in AppShadows.card(colors)) {
      canvas.drawPath(path.shift(s.offset), Paint()..color = s.color..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma));
    }
    canvas.restore();
    canvas.drawPath(path, Paint()..color = colors.surface);
    canvas.drawPath(path, Paint()..color = colors.outline..style = PaintingStyle.stroke..strokeWidth = 1);
    if (!top) _dashedLine(canvas, size);
  }

  void _dashedLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colors.outline
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const dash = 6.0, gap = 5.0;
    var x = kTicketNotch + Spacing.s8;
    final end = size.width - kTicketNotch - Spacing.s8;
    while (x < end) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash > end ? end : x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_TicketPartPainter old) => old.top != top || old.colors != colors;
}
