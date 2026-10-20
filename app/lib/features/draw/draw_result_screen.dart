import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/db/rate_cache.dart' show SettingsStore;
import '../../core/display.dart';
import '../../core/format.dart';
import '../../core/notifications/draw_spoiler.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import '../notifications/notification_models.dart';
import '../notifications/notifications_controller.dart';
import '../tickets/ticket_models.dart';
import '../tickets/tickets_controller.dart';
import 'draw_controller.dart';
import 'shake.dart';

/// S-RESULT: hasil draw (pemenang, waktu, jumlah tiket, nasib tiketmu). Bila peserta membuka hasil yang BARU (penanda
/// "sudah dilihat" di SQLite lokal belum ada), tampil dulu layar "Goyangkan untuk melihat hasil" dengan tombol alternatif.
class DrawResultScreen extends StatefulWidget {
  const DrawResultScreen({super.key, required this.giveawayId, this.shakes = deviceShakes, this.runner});
  final String giveawayId;

  /// Hanya untuk tes: pengganti isolate untuk perhitungan hash.
  final VerifyRunner? runner;

  /// Sumber kejadian goyang (sensor); diganti di tes.
  final Stream<void> Function() shakes;

  @override
  State<DrawResultScreen> createState() => _DrawResultScreenState();
}

class _DrawResultScreenState extends State<DrawResultScreen> {
  late final DrawController _draw = DrawController(context.read<AuthedApi>(), widget.giveawayId, runner: widget.runner);
  late final DrawSeenStore _seenStore =
      DrawSeenStore(context.read<SettingsStore?>(), context.read<AuthController?>()?.user?.id ?? '');
  late final NotificationService? _notif = context.read<NotificationService?>();
  bool _ready = false, _seen = false, _revealed = false;

  @override
  void initState() {
    super.initState();
    _notif?.activeResultGiveawayId = widget.giveawayId;
    Future.microtask(_init);
  }

  @override
  void dispose() {
    if (_notif?.activeResultGiveawayId == widget.giveawayId) _notif?.activeResultGiveawayId = null;
    _draw.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final tickets = context.read<TicketsController?>();
    await Future.wait<void>([
      _draw.load(),
      if (tickets != null) tickets.load(), // hasil tiket terbaru dari server
      _seenStore.isSeen(widget.giveawayId).then((v) => _seen = v),
    ]);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _reveal() async {
    if (_revealed) return;
    setState(() => _revealed = true);
    final ids = [
      for (final n in context.read<NotificationsController?>()?.items ?? const <AppNotification>[])
        if (n.giveawayId == widget.giveawayId && isDrawResultType(n.type)) n.id,
    ];
    await _seenStore.markSeen(widget.giveawayId);
    await _notif?.onDrawRevealed(widget.giveawayId, ids);
  }

  @override
  Widget build(BuildContext context) {
    final tickets = context.watch<TicketsController?>();
    final mine = [for (final t in tickets?.items ?? const <Ticket>[]) if (t.giveawayId == widget.giveawayId) t];
    return ListenableBuilder(
      listenable: _draw,
      builder: (context, _) {
        final d = _draw;
        final Widget body;
        final loading = !_ready || d.state == LoadState.idle || d.state == LoadState.loading;
        if (loading) {
          body = const SkeletonLoader(key: ValueKey('loading'), shape: SkeletonShape.ticket, count: 3);
        } else if (d.state == LoadState.error) {
          body = ErrorState(key: const ValueKey('error'), message: d.error ?? 'Gagal memuat.', onRetry: d.load);
        } else if (!d.drawn) {
          body = const EmptyState(
            key: ValueKey('undrawn'),
            icon: Icons.hourglass_top,
            title: 'Belum diundi',
            message: 'Hasil muncul di sini setelah draw dijalankan. Kamu akan menerima notifikasi.',
          );
        } else if (mine.isNotEmpty && !_seen && !_revealed) {
          body = _ShakeGate(key: const ValueKey('gate'), shakes: widget.shakes, onReveal: _reveal);
        } else {
          body = _Results(key: const ValueKey('results'), draw: d, mine: mine, celebrate: _revealed);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Hasil Draw')),
          body: AnimatedSwitcher(
            duration: Motion.of(context, Motion.slow),
            switchInCurve: Motion.curve,
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child)),
            child: body,
          ),
        );
      },
    );
  }
}

/// Layar "Goyangkan untuk melihat hasil". Goyangan (sensor) atau tombol "Lihat hasil" sama-sama membuka hasil.
class _ShakeGate extends StatefulWidget {
  const _ShakeGate({super.key, required this.shakes, required this.onReveal});
  final Stream<void> Function() shakes;
  final VoidCallback onReveal;

  @override
  State<_ShakeGate> createState() => _ShakeGateState();
}

class _ShakeGateState extends State<_ShakeGate> with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    try {
      _sub = widget.shakes().listen((_) => widget.onReveal(), onError: (_) {});
    } catch (_) {
      _sub = null; // tanpa sensor: tombol tetap ada
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _wiggle.stop();
    } else if (!_wiggle.isAnimating) {
      _wiggle.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Center(
      key: const Key('shake_gate'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _wiggle,
                builder: (_, child) => Transform.rotate(angle: (_wiggle.value - 0.5) * 0.35, child: child),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
                  child: SizedBox(width: 144, height: 144, child: Icon(Icons.vibration, size: 80, color: c.onPrimaryContainer)),
                ),
              ),
            ),
            const SizedBox(height: Spacing.s24),
            Semantics(header: true, liveRegion: true, child: Text('Goyangkan untuk melihat hasil', textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
            const SizedBox(height: Spacing.s8),
            Text(
              'Hasil undian sudah keluar. Goyangkan ponselmu, atau tekan tombol di bawah bila tidak ingin menggoyangkannya.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: Spacing.s24),
            PrimaryButton(key: const Key('reveal_button'), label: 'Lihat hasil', icon: Icons.visibility_outlined, onPressed: widget.onReveal),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({super.key, required this.draw, required this.mine, required this.celebrate});
  final DrawController draw;
  final List<Ticket> mine;

  /// Baru dibuka lewat layar goyang: konfeti ringan bila menang.
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final rep = draw.report!;
    final winnerNumbers = {for (final w in draw.winners) w.ticketNumber};
    final mineNumbers = {for (final t in mine) t.ticketNumber};
    final won = mine.any((t) => t.result == TicketResult.winner) || mineNumbers.any(winnerNumbers.contains);
    final participated = mine.isNotEmpty;
    final tone = won ? StatusTone.success : StatusTone.neutral;
    final sc = StatusChip.colorsOf(c, tone);

    final list = ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
      children: [
        if (participated) ...[
          SurfaceCard(
            key: const Key('result_outcome'),
            color: sc.bg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(won ? Icons.emoji_events : Icons.remove_circle_outline, size: 40, color: sc.fg)),
                const SizedBox(width: Spacing.s12),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(won ? 'Tiketmu menang!' : 'Tiketmu tidak terpilih', style: theme.textTheme.titleLarge?.copyWith(color: sc.fg)),
                        const SizedBox(height: Spacing.s4),
                        Text(
                          won ? 'Selamat! Panitia akan menghubungimu untuk hadiahnya.' : 'Terima kasih sudah ikut. Kamu tetap bisa memeriksa keaslian hasilnya.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: sc.fg),
                        ),
                        const SizedBox(height: Spacing.s8),
                        Text('Tiketmu: ${(mineNumbers.toList()..sort()).map(formatTicketNumber).join(', ')}', style: theme.textTheme.bodySmall?.copyWith(color: sc.fg)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.s16),
        ],
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rep.drawnAtMs != null) _Info(icon: Icons.event_available, label: 'Diundi', value: context.when(DateTime.fromMillisecondsSinceEpoch(rep.drawnAtMs!))),
              if (rep.totalTickets != null) _Info(icon: Icons.confirmation_number_outlined, label: 'Tiket yang ikut', value: '${rep.totalTickets}'),
              _Info(icon: Icons.emoji_events_outlined, label: 'Pemenang', value: '${draw.winners.length}'),
            ],
          ),
        ),
        const SectionHeader('Daftar pemenang', padding: EdgeInsets.only(top: Spacing.s16)),
        if (draw.winners.isEmpty)
          const EmptyState(icon: Icons.group_off_outlined, title: 'Tidak ada pemenang', message: 'Giveaway ini berakhir tanpa peserta.', compact: true)
        else
          for (final w in draw.winners)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.s8),
              child: _WinnerRow(winner: w, isMine: mineNumbers.contains(w.ticketNumber)),
            ),
        const SizedBox(height: Spacing.s16),
        PrimaryButton(
          key: const Key('open_verify'),
          label: 'Cek Keaslian',
          icon: Icons.verified_outlined,
          variant: ButtonVariant.secondary,
          onPressed: () => context.push('/giveaway/${draw.giveawayId}/verify'),
        ),
      ],
    );
    if (!(celebrate && won) || Motion.reduced(context)) return list;
    return Stack(children: [list, const Positioned.fill(child: IgnorePointer(child: ExcludeSemantics(child: _Confetti())))]);
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.colors.muted),
          const SizedBox(width: Spacing.s8),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted))),
          const SizedBox(width: Spacing.s8),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _WinnerRow extends StatelessWidget {
  const _WinnerRow({required this.winner, required this.isMine});
  final DrawWinner winner;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return SurfaceCard(
      key: Key('result_winner_${winner.ticketNumber}'),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s12),
      color: isMine ? c.statusSuccess.bg : null,
      child: Row(
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
              child: SizedBox(width: 36, height: 36, child: Center(child: Text('${winner.rank}', style: theme.textTheme.titleSmall?.copyWith(color: c.onPrimaryContainer)))),
            ),
          ),
          const SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatTicketNumber(winner.ticketNumber), style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                if (winner.name.isNotEmpty) Text(winner.name, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
              ],
            ),
          ),
          if (isMine) const Padding(padding: EdgeInsets.only(left: Spacing.s8), child: StatusChip.custom(label: 'Tiketmu', tone: StatusTone.success, icon: Icons.emoji_events)),
        ],
      ),
    );
  }
}

/// Konfeti ringan (40 keping, ~2 detik, sekali). Tidak dipasang bila pengguna meminta animasi dikurangi.
class _Confetti extends StatefulWidget {
  const _Confetti();
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final colors = [c.primary, c.statusWarning.fg, c.statusSuccess.fg, c.statusInfo.fg, c.accent];
    return AnimatedBuilder(animation: _anim, builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_anim.value, colors)));
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.colors);
  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    for (var i = 0; i < 40; i++) {
      final x0 = rnd.nextDouble() * size.width;
      final speed = 0.6 + rnd.nextDouble() * 0.8;
      final sway = (rnd.nextDouble() - 0.5) * 60;
      final y = -20 + (size.height * 0.9) * (t * speed);
      final fade = (1 - t).clamp(0.0, 1.0);
      final paint = Paint()..color = colors[i % colors.length].withValues(alpha: fade);
      canvas.save();
      canvas.translate(x0 + sway * sin(t * 6 + i), y);
      canvas.rotate(t * 8 + i);
      canvas.drawRect(const Rect.fromLTWH(-4, -2, 8, 4), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
