import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'game_controller.dart';
import 'maze.dart';
import 'maze_game.dart';
import 'tilt.dart';

/// Percepatan bola (sel/detik^2) per m/s^2 kemiringan, dan zona mati supaya ponsel yang diam di tangan tidak menggeser bola.
const double tiltGain = 1.5, tiltDeadZone = 0.6, tiltMax = 8;

/// Layar permainan: HUD (waktu, bintang, jeda), labirin (CustomPainter, digerakkan Ticker), tombol panah sebagai kontrol
/// alternatif (aksesibilitas, emulator), dan hasil (waktu, bintang, skor). Logika ada di [MazeGame]; layar hanya menyajikan.
/// Tidak ada animasi dekoratif, jadi "kurangi animasi" sistem tidak mengubah apa pun selain tidak adanya efek tambahan.
class MazePlayScreen extends StatefulWidget {
  const MazePlayScreen({super.key, required this.levelIndex, this.seed, this.tilt = deviceTilt});
  final int levelIndex;

  /// Hanya untuk tes: labirin deterministik.
  final int? seed;

  /// Sumber kemiringan (sensor); diganti di tes.
  final Stream<({double x, double y})> Function() tilt;

  @override
  State<MazePlayScreen> createState() => _MazePlayScreenState();
}

class _MazePlayScreenState extends State<MazePlayScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late MazeGame _game;
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  StreamSubscription<({double x, double y})>? _sub;
  Duration _last = Duration.zero;
  double _ax = 0, _ay = 0;
  GameOutcome? _outcome;
  bool _submitted = false;

  MazeLevel get _level => MazeLevel.all[widget.levelIndex.clamp(0, MazeLevel.all.length - 1)];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _newGame();
    WidgetsBinding.instance.addObserver(this);
    try {
      _sub = widget.tilt().listen((t) {
        double f(double v) => v.abs() < tiltDeadZone ? 0 : v.clamp(-tiltMax, tiltMax) * tiltGain;
        _ax = f(t.x);
        _ay = f(t.y);
      }, onError: (_) {});
    } catch (_) {
      _sub = null; // tanpa sensor: tombol panah tetap ada
    }
  }

  /// Ticker hanya hidup selama bermain (hemat baterai; tidak ada frame saat jeda, hasil, atau overlay awal).
  void _syncTicker() {
    if (_game.status == GameStatus.playing) {
      if (!_ticker.isActive) {
        _last = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  /// setState + sinkronisasi ticker setelah status permainan berubah.
  void _update(VoidCallback f) {
    setState(f);
    _syncTicker();
  }

  void _newGame() {
    final rnd = Random(widget.seed ?? DateTime.now().microsecondsSinceEpoch);
    _game = MazeGame(_level, Maze.generate(_level.cols, _level.rows, rnd, stars: _level.stars));
    _outcome = null;
    _submitted = false;
    _last = Duration.zero;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _game.status == GameStatus.playing) {
      if (mounted) _update(_game.pause);
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_game.status != GameStatus.playing) return;
    _game.tick(dt, ax: _ax, ay: _ay);
    _frame.value++;
    if (_game.finished) _finish();
  }

  void _nudge(Dir d) {
    if (!_game.nudge(d)) return;
    _frame.value++;
    if (_game.finished) _finish();
  }

  void _finish() {
    _update(() {});
    if (_game.score.worthSubmitting && !_submitted) _submit();
  }

  /// Kirim sekali; bila gagal, pemain bisa menekan "Kirim ulang" (satu permintaan pada satu waktu, tanpa retry otomatis).
  Future<void> _submit() async {
    final r = await context.read<GameController>().submitScore(_game.score);
    if (r == null || !mounted) return;
    setState(() {
      _outcome = r;
      _submitted = r.isOk;
    });
  }

  void _again() => _update(_newGame);

  @override
  Widget build(BuildContext context) {
    final status = _game.status;
    return Scaffold(
      appBar: AppBar(
        title: Text('Maze ${_level.name}'),
        actions: [
          IconButton(
            key: const Key('maze_pause'),
            tooltip: 'Jeda',
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: status == GameStatus.playing ? () => _update(_game.pause) : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, box) {
            // Papan persegi: sisanya untuk HUD dan tombol panah (kontrol ~190 dp); tidak lebih kecil dari 220.
            final side = min(box.maxWidth - Spacing.screen * 2, max(220.0, box.maxHeight - 72 - 200));
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s16),
              child: Column(
                children: [
                  ValueListenableBuilder<int>(valueListenable: _frame, builder: (_, _, _) => _Hud(game: _game)),
                  const SizedBox(height: Spacing.s8),
                  Semantics(
                    label: 'Labirin ${_level.cols} kali ${_level.rows}. Bintang ${_game.starsCollected} dari ${_game.maze.stars.length}. Gunakan tombol panah atau miringkan ponsel.',
                    child: SizedBox(
                      key: const Key('maze_board'),
                      width: side,
                      height: side,
                      child: CustomPaint(painter: _MazePainter(_game, context.colors, _frame)),
                    ),
                  ),
                  const SizedBox(height: Spacing.s12),
                  _DPad(onMove: _nudge, enabled: status == GameStatus.playing),
                  const SizedBox(height: Spacing.s8),
                  Text(
                    'Miringkan ponsel untuk menggulirkan bola, atau pakai tombol panah (satu sel tiap ketukan).',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.muted),
                  ),
                ],
              ),
            );
          }),
          if (status != GameStatus.playing) Positioned.fill(child: _Overlay(child: _panel(context, status))),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, GameStatus status) {
    switch (status) {
      case GameStatus.ready:
        return _Panel(
          icon: Icons.sports_esports_outlined,
          title: 'Siap?',
          message: 'Bawa bola ke pintu keluar secepatnya dan ambil bintang di jalan. Waktu: ${_level.seconds} detik.',
          actions: [PrimaryButton(key: const Key('maze_start'), label: 'Mulai', icon: Icons.play_arrow, onPressed: () => _update(_game.start))],
        );
      case GameStatus.paused:
        return _Panel(
          icon: Icons.pause_circle_outline,
          title: 'Dijeda',
          message: 'Waktu berhenti selama permainan dijeda.',
          actions: [
            PrimaryButton(key: const Key('maze_resume'), label: 'Lanjut', icon: Icons.play_arrow, onPressed: () => _update(_game.resume)),
            PrimaryButton(label: 'Keluar', variant: ButtonVariant.text, onPressed: () => context.pop()),
          ],
        );
      case GameStatus.cleared || GameStatus.timeUp:
        return _ResultPanel(
          game: _game,
          outcome: _outcome,
          submitting: context.watch<GameController>().submitting,
          onRetry: _submit,
          onAgain: _again,
        );
      case GameStatus.playing:
        return const SizedBox.shrink();
    }
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.game});
  final MazeGame game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final low = game.timeLeft <= 10 && game.status != GameStatus.ready;
    final secs = game.timeLeft.ceil();
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Sisa waktu $secs detik',
            excludeSemantics: true,
            child: Row(children: [
              Icon(low ? Icons.timer : Icons.timer_outlined, color: low ? c.error : c.muted),
              const SizedBox(width: Spacing.s4),
              Flexible(child: Text('$secs dtk', key: const Key('maze_time'), style: theme.textTheme.titleMedium?.copyWith(color: low ? c.error : null, fontFeatures: const [FontFeature.tabularFigures()]))),
            ]),
          ),
        ),
        Semantics(
          label: 'Bintang ${game.starsCollected} dari ${game.maze.stars.length}',
          excludeSemantics: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.star, color: c.accent),
            const SizedBox(width: Spacing.s4),
            Text('${game.starsCollected}/${game.maze.stars.length}', key: const Key('maze_stars'), style: theme.textTheme.titleMedium),
          ]),
        ),
      ],
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({required this.onMove, required this.enabled});
  final void Function(Dir) onMove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget btn(Dir d, IconData icon, String label) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: IconButton.filledTonal(
            key: Key('dpad_${d.name}'),
            tooltip: label,
            iconSize: 28,
            constraints: const BoxConstraints.tightFor(width: 56, height: 56),
            onPressed: enabled ? () => onMove(d) : null,
            icon: Icon(icon),
          ),
        );
    const gap = SizedBox(width: Spacing.s8, height: Spacing.s8);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      btn(Dir.n, Icons.keyboard_arrow_up, 'Gerak ke atas'),
      gap,
      Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Dir.w, Icons.keyboard_arrow_left, 'Gerak ke kiri'),
        const SizedBox(width: 56 + Spacing.s16),
        btn(Dir.e, Icons.keyboard_arrow_right, 'Gerak ke kanan'),
      ]),
      gap,
      btn(Dir.s, Icons.keyboard_arrow_down, 'Gerak ke bawah'),
    ]);
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Overlays.imageScrimBottom,
        child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(Spacing.screen), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: child))),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.message, required this.actions});
  final IconData icon;
  final String title, message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      raised: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ExcludeSemantics(child: Icon(icon, size: 48, color: context.colors.primary)),
        const SizedBox(height: Spacing.s8),
        Semantics(header: true, liveRegion: true, child: Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
        const SizedBox(height: Spacing.s8),
        Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Spacing.s16),
        for (final a in actions) Padding(padding: const EdgeInsets.only(top: Spacing.s8), child: a),
      ]),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.game, required this.outcome, required this.submitting, required this.onRetry, required this.onAgain});
  final MazeGame game;
  final GameOutcome? outcome;
  final bool submitting;
  final VoidCallback onRetry, onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final s = game.score;
    final cleared = s.cleared;
    final total = game.maze.stars.length;
    final data = outcome?.data;
    return SurfaceCard(
      key: const Key('maze_result'),
      raised: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ExcludeSemantics(child: Icon(cleared ? Icons.emoji_events : Icons.timer_off_outlined, size: 48, color: cleared ? c.accent : c.muted)),
        const SizedBox(height: Spacing.s8),
        Semantics(header: true, liveRegion: true, child: Text(cleared ? 'Labirin selesai!' : 'Waktu habis', textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
        const SizedBox(height: Spacing.s12),
        // Bintang (ikon terisi/kosong + teks "x dari y": bukan hanya warna).
        Semantics(
          label: '$total bintang tersedia, ${s.stars} terkumpul',
          excludeSemantics: true,
          child: Wrap(alignment: WrapAlignment.center, children: [
            for (var i = 0; i < total; i++) Icon(i < s.stars ? Icons.star : Icons.star_border, color: c.accent, size: 24),
          ]),
        ),
        Text('${s.stars} dari $total bintang', style: theme.textTheme.bodyMedium),
        const SizedBox(height: Spacing.s12),
        _Row(label: 'Waktu', value: '${s.durationSec} detik'),
        if (cleared) _Row(label: 'Sisa waktu', value: '${s.secondsLeft} detik'),
        _Row(label: 'Skor', value: '${data?.score ?? s.score}', bold: true, valueKey: const Key('maze_score')),
        const SizedBox(height: Spacing.s12),
        if (!s.worthSubmitting)
          const InlineMessage('Skor 0 tidak dikirim ke papan peringkat.', tone: StatusTone.info)
        else if (submitting)
          const InlineMessage('Mengirim skor…', tone: StatusTone.info)
        else if (outcome == null)
          const InlineMessage('Skor belum terkirim.', tone: StatusTone.warning)
        else if (!outcome!.isOk)
          InlineMessage(outcome!.error!)
        else
          InlineMessage(
            data!.dailyCapReached
                ? 'Skor tersimpan. Batas XP harian tercapai, tetapi skor tetap masuk papan peringkat.'
                : 'Skor tersimpan. +${data.xpEarned} XP.',
            tone: StatusTone.success,
          ),
        if (s.worthSubmitting && outcome?.isOk != true && !submitting) ...[
          const SizedBox(height: Spacing.s8),
          PrimaryButton(key: const Key('maze_retry_submit'), label: 'Kirim skor', icon: Icons.send, onPressed: onRetry),
        ],
        const SizedBox(height: Spacing.s8),
        PrimaryButton(key: const Key('maze_again'), label: 'Main lagi', icon: Icons.replay, onPressed: onAgain),
        const SizedBox(height: Spacing.s8),
        PrimaryButton(key: const Key('maze_open_leaderboard'), label: 'Papan peringkat', icon: Icons.leaderboard_outlined, variant: ButtonVariant.secondary, onPressed: () => context.push('/leaderboard')),
        PrimaryButton(label: 'Selesai', variant: ButtonVariant.text, onPressed: () => context.pop()),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false, this.valueKey});
  final String label, value;
  final bool bold;
  final Key? valueKey;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted))),
        Text(value, key: valueKey, style: (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class _MazePainter extends CustomPainter {
  _MazePainter(this.game, this.colors, Listenable repaint) : super(repaint: repaint);
  final MazeGame game;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final m = game.maze;
    final cell = size.width / m.cols;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.input)), Paint()..color = colors.surfaceVariant);
    // Pintu keluar: cincin ganda (bentuk, bukan hanya warna) di sel keluar; mulai: titik kecil.
    Offset center(Cell c) => Offset((c.$1 + 0.5) * cell, (c.$2 + 0.5) * cell);
    final exitPaint = Paint()..color = colors.statusSuccess.fg..style = PaintingStyle.stroke..strokeWidth = cell * 0.08;
    canvas.drawCircle(center(m.exit), cell * 0.36, exitPaint);
    canvas.drawCircle(center(m.exit), cell * 0.20, exitPaint);
    canvas.drawCircle(center(m.start), cell * 0.08, Paint()..color = colors.muted);
    // Bintang yang belum diambil.
    final starPaint = Paint()..color = colors.accent;
    for (final (_, c) in game.remainingStars) {
      final o = center(c);
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final r = (i.isEven ? 0.26 : 0.11) * cell;
        final a = -pi / 2 + i * pi / 5;
        final p = Offset(o.dx + r * cos(a), o.dy + r * sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), starPaint);
    }
    // Dinding (garis tebal membulat).
    final wall = Paint()
      ..color = colors.onBackground
      ..strokeWidth = max(2.0, cell * MazeGame.wallHalf * 2)
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r < m.rows; r++) {
      for (var c = 0; c < m.cols; c++) {
        final x = c * cell, y = r * cell;
        if (!m.canMove(c, r, Dir.n)) canvas.drawLine(Offset(x, y), Offset(x + cell, y), wall);
        if (!m.canMove(c, r, Dir.w)) canvas.drawLine(Offset(x, y), Offset(x, y + cell), wall);
        if (r == m.rows - 1 && !m.canMove(c, r, Dir.s)) canvas.drawLine(Offset(x, y + cell), Offset(x + cell, y + cell), wall);
        if (c == m.cols - 1 && !m.canMove(c, r, Dir.e)) canvas.drawLine(Offset(x + cell, y), Offset(x + cell, y + cell), wall);
      }
    }
    // Bola.
    final b = Offset(game.x * cell, game.y * cell);
    canvas.drawCircle(b, MazeGame.ballRadius * cell, Paint()..color = colors.primary);
    canvas.drawCircle(b, MazeGame.ballRadius * cell, Paint()..color = colors.onPrimary..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}
