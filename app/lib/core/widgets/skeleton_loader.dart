import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'surface_card.dart';
import 'waking_up_notice.dart';

/// Bentuk kerangka yang menyerupai kartu yang sedang dimuat.
enum SkeletonShape { card, ticket, row }

/// Pengganti spinner penuh layar untuk daftar: blok abu dengan kilau halus (denyut warna).
/// Kilau berhenti bila pengguna meminta animasi dikurangi.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({super.key, this.count = 3, this.shape = SkeletonShape.card, this.showWakingNotice = true, this.shrinkWrap = false});
  final int count;
  final SkeletonShape shape;

  /// Tampilkan "Server sedang bangun..." di bawah bila server lambat (> 5 detik).
  final bool showWakingNotice;

  /// true = tinggi mengikuti isi (dipakai di dalam daftar yang bisa digulir); false = mengisi layar tanpa menggulir.
  final bool shrinkWrap;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _anim.stop();
    } else if (!_anim.isAnimating) {
      _anim.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _wrap(Widget child) {
    const padding = EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.s16);
    return widget.shrinkWrap
        ? Padding(padding: padding, child: child)
        : SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), padding: padding, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat',
      liveRegion: true,
      child: ExcludeSemantics(
        child: _SkeletonPulse(
          notifier: _anim,
          child: _wrap(
            Column(
              children: [
                for (var i = 0; i < widget.count; i++) ...[
                  if (i > 0) const SizedBox(height: Spacing.cardGap),
                  switch (widget.shape) {
                    SkeletonShape.card => const _CardSkeleton(),
                    SkeletonShape.ticket => const _TicketSkeleton(),
                    SkeletonShape.row => const _RowSkeleton(),
                  },
                ],
                if (widget.showWakingNotice) const WakingUpNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonPulse extends InheritedNotifier<Animation<double>> {
  const _SkeletonPulse({required Animation<double> notifier, required super.child}) : super(notifier: notifier);
}

/// Satu blok kerangka. Berdenyut bila berada di dalam [SkeletonLoader]; selain itu statis.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = Radii.input, this.circle = false});
  final double? width;
  final double height, radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.dependOnInheritedWidgetOfExactType<_SkeletonPulse>()?.notifier?.value ?? 0;
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(c.surfaceVariant, c.outline, t),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();
  @override
  Widget build(BuildContext context) => const SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(height: double.infinity, radius: 0)),
            Padding(
              padding: EdgeInsets.all(Spacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 18, width: 220),
                  SizedBox(height: Spacing.s8),
                  SkeletonBox(height: 14, width: 140),
                  SizedBox(height: Spacing.s12),
                  SkeletonBox(height: 12, width: 180),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TicketSkeleton extends StatelessWidget {
  const _TicketSkeleton();
  @override
  Widget build(BuildContext context) => const SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 18, width: 200),
            SizedBox(height: Spacing.s8),
            SkeletonBox(height: 14, width: 120),
            SizedBox(height: Spacing.s24),
            Row(children: [SkeletonBox(height: 28, width: 120), Spacer(), SkeletonBox(height: 24, width: 80, radius: Radii.full)]),
          ],
        ),
      );
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();
  @override
  Widget build(BuildContext context) => const Row(
        children: [
          SkeletonBox(height: 44, circle: true),
          SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [SkeletonBox(height: 14, width: 180), SizedBox(height: Spacing.s8), SkeletonBox(height: 12, width: 110)],
            ),
          ),
        ],
      );
}
