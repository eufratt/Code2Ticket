import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../profile/profile_screen.dart' show badgeLabel;
import 'code_hunt.dart';
import 'code_hunt_widgets.dart';
import 'game_controller.dart';
import 'maze.dart';
import 'maze_game.dart';
import 'tilt.dart';
import 'tilt_filter.dart';

/// Layar permainan Code Hunt: HUD (waktu, segmen kode, kode rakitan, jeda), labirin (CustomPainter, digerakkan Ticker), tombol panah
/// sebagai kontrol alternatif (aksesibilitas, emulator), dan hasil (waktu, segmen, skor, Tiket Latihan). Narasi: chip kode (bola)
/// mengumpulkan segmen kode (bintang) lalu masuk Mesin Undian (pintu keluar); skor dan kontrak server tidak berubah. Logika ada di [MazeGame] dan [TiltFilter]
/// (gyroscope + accelerometer, parameter di tilt_filter.dart); layar hanya menyajikan.
/// Tidak ada animasi dekoratif, jadi "kurangi animasi" sistem tidak mengubah apa pun selain tidak adanya efek tambahan.
class MazePlayScreen extends StatefulWidget {
  const MazePlayScreen({super.key, required this.levelIndex, this.seed, this.tilt = deviceTilt});
  final int levelIndex;

  /// Hanya untuk tes: labirin deterministik.
  final int? seed;

  /// Sumber masukan sensor (gyroscope + accelerometer); diganti di tes.
  final Stream<TiltInput> Function() tilt;

  @override
  State<MazePlayScreen> createState() => _MazePlayScreenState();
}

class _MazePlayScreenState extends State<MazePlayScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late MazeGame _game;
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  StreamSubscription<TiltInput>? _sub;
  final TiltFilter _tilt = TiltFilter();
  Duration _last = Duration.zero;
  GameOutcome? _outcome;
  bool _submitted = false;
  late int _seed;
  late List<String> _segments;
  List<String> _badgesBefore = const [];
  PracticeTarget? _target;

  MazeLevel get _level => MazeLevel.all[widget.levelIndex.clamp(0, MazeLevel.all.length - 1)];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _newGame();
    WidgetsBinding.instance.addObserver(this);
    try {
      _sub = widget.tilt().listen((e) {
        final gyro = _tilt.gyroActive;
        _tilt.add(e);
        if (gyro != _tilt.gyroActive && mounted) setState(() {}); // label sensor
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
    _seed = widget.seed ?? DateTime.now().microsecondsSinceEpoch;
    final rnd = Random(_seed);
    _game = MazeGame(_level, Maze.generate(_level.cols, _level.rows, rnd, stars: _level.stars));
    _segments = practiceSegments(levelCodeSeed(_seed, widget.levelIndex), _game.maze.stars.length);
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
    final a = _tilt.ballAccel;
    _game.tick(dt, ax: a.x, ay: a.y);
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

  /// Posisi ponsel saat ini dianggap datar.
  void _calibrate() => _tilt.calibrate();

  void _begin() {
    _badgesBefore = context.read<AuthController?>()?.user?.badges ?? const [];
    _calibrate();
    _update(_game.start);
  }

  void _again() => _update(_newGame);

  @override
  Widget build(BuildContext context) {
    final status = _game.status;
    if (status == GameStatus.ready) _target = practiceTargetOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Code Hunt ${_level.name}'),
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
            final side = min(box.maxWidth - Spacing.screen * 2, max(220.0, box.maxHeight - 72 - 250));
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s16),
              child: Column(
                children: [
                  ValueListenableBuilder<int>(valueListenable: _frame, builder: (_, _, _) => _Hud(game: _game, segments: _segments)),
                  const SizedBox(height: Spacing.s8),
                  Semantics(
                    label: 'Labirin ${_level.cols} kali ${_level.rows}. Segmen kode ${_game.starsCollected} dari ${_game.maze.stars.length}. Antar chip kode ke Mesin Undian. Gunakan tombol panah atau miringkan ponsel.',
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
                  // Wrap: pada 320 dp / font 1,3x label dan tombol turun ke baris berikutnya, tidak meluap.
                  Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: Spacing.s8, children: [
                    Text(
                      _tilt.gyroActive ? 'Sensor: gyroscope + accelerometer' : 'Sensor: accelerometer',
                      key: const Key('maze_sensor'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.muted),
                    ),
                    PrimaryButton(
                      key: const Key('maze_calibrate'),
                      label: 'Kalibrasi ulang',
                      icon: Icons.my_location,
                      variant: ButtonVariant.text,
                      expand: false,
                      onPressed: status == GameStatus.playing ? _calibrate : null,
                    ),
                  ]),
                  Text(
                    'Posisi ponsel saat Mulai dianggap datar. Miringkan untuk menggulirkan bola, atau pakai tombol panah (satu sel tiap ketukan).',
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
          message: 'Antar chip kode ke Mesin Undian secepatnya dan kumpulkan ${_game.maze.stars.length} segmen kode di jalan. Waktu: ${_level.seconds} detik.',
          details: PracticeTargetLine(target: _target, center: true),
          actions: [PrimaryButton(key: const Key('maze_start'), label: 'Mulai', icon: Icons.play_arrow, onPressed: _begin)],
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
          segments: _segments,
          ticketNumber: practiceTicketNumber(levelCodeSeed(_seed, widget.levelIndex)),
          target: _target,
          newBadges: [for (final b in context.read<AuthController?>()?.user?.badges ?? const <String>[]) if (!_badgesBefore.contains(b)) b],
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
  const _Hud({required this.game, required this.segments});
  final MazeGame game;
  final List<String> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final low = game.timeLeft <= 10 && game.status != GameStatus.ready;
    final secs = game.timeLeft.ceil();
    final total = game.maze.stars.length;
    return Column(children: [
      Row(
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
            label: 'Segmen kode ${game.starsCollected} dari $total',
            excludeSemantics: true,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.vpn_key_outlined, color: c.accent),
              const SizedBox(width: Spacing.s4),
              Text('${game.starsCollected}/$total', key: const Key('maze_stars'), style: theme.textTheme.titleMedium),
            ]),
          ),
        ],
      ),
      const SizedBox(height: Spacing.s8),
      Container(
        key: const Key('maze_code'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s12, vertical: Spacing.s8),
        decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: Radii.buttonAll),
        child: CodeDisplay(segments: segments, filled: game.starsCollected, align: CrossAxisAlignment.center),
      ),
    ]);
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
  const _Panel({required this.icon, required this.title, required this.message, required this.actions, this.details});
  final IconData icon;
  final String title, message;
  final List<Widget> actions;
  final Widget? details;

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
        if (details != null) Padding(padding: const EdgeInsets.only(top: Spacing.s12), child: details),
        const SizedBox(height: Spacing.s16),
        for (final a in actions) Padding(padding: const EdgeInsets.only(top: Spacing.s8), child: a),
      ]),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.game,
    required this.segments,
    required this.ticketNumber,
    required this.target,
    required this.newBadges,
    required this.outcome,
    required this.submitting,
    required this.onRetry,
    required this.onAgain,
  });
  final MazeGame game;
  final List<String> segments;
  final String ticketNumber;
  final PracticeTarget? target;
  final List<String> newBadges;
  final GameOutcome? outcome;
  final bool submitting;
  final VoidCallback onRetry, onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final s = game.score;
    final cleared = s.cleared;
    final total = segments.length;
    final data = outcome?.data;
    return SurfaceCard(
      key: const Key('maze_result'),
      raised: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ExcludeSemantics(child: Icon(cleared ? Icons.confirmation_number : Icons.timer_off_outlined, size: 48, color: cleared ? c.accent : c.muted)),
        const SizedBox(height: Spacing.s8),
        Semantics(header: true, liveRegion: true, child: Text(cleared ? 'Tiket Latihan terbit!' : 'Waktu habis', textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
        const SizedBox(height: Spacing.s12),
        if (cleared) ...[
          PracticeTicket(segments: segments, number: ticketNumber, target: target),
          const SizedBox(height: Spacing.s8),
          const InlineMessage(practiceDisclaimer, tone: StatusTone.info),
          if (data != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.s8),
              child: Wrap(alignment: WrapAlignment.center, spacing: Spacing.s8, runSpacing: Spacing.s8, children: [
                StatusChip.custom(label: '+${data.xpEarned} XP', tone: StatusTone.success, icon: Icons.bolt),
                for (final b in newBadges) StatusChip.custom(label: 'Lencana: ${badgeLabel(b)}', tone: StatusTone.success, icon: Icons.military_tech),
              ]),
            ),
        ] else ...[
          // Waktu habis: tampilkan segmen yang sempat terkumpul (slot sisanya kosong).
          Container(
            key: const Key('maze_result_code'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.s12, vertical: Spacing.s8),
            decoration: BoxDecoration(color: c.surfaceVariant, borderRadius: Radii.buttonAll),
            child: CodeDisplay(segments: segments, filled: s.stars, align: CrossAxisAlignment.center),
          ),
          const SizedBox(height: Spacing.s8),
          Text('Kode belum lengkap, jadi Mesin Undian belum menerbitkan Tiket Latihan.', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Spacing.s8),
        Text('${s.stars} dari $total segmen kode', style: theme.textTheme.bodyMedium),
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
    // Mesin Undian (titik akhir): cincin + ikon tiket (bentuk, bukan hanya warna); mulai: titik kecil.
    Offset center(Cell c) => Offset((c.$1 + 0.5) * cell, (c.$2 + 0.5) * cell);
    final exitPaint = Paint()..color = colors.statusSuccess.fg..style = PaintingStyle.stroke..strokeWidth = cell * 0.08;
    canvas.drawCircle(center(m.exit), cell * 0.40, exitPaint);
    const icon = Icons.confirmation_number_outlined;
    final ticket = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: cell * 0.5, color: colors.statusSuccess.fg),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ticket.paint(canvas, center(m.exit) - Offset(ticket.width / 2, ticket.height / 2));
    canvas.drawCircle(center(m.start), cell * 0.08, Paint()..color = colors.muted);
    // Segmen kode yang belum diambil: label membulat dengan empat titik (4 karakter).
    final tagPaint = Paint()..color = colors.accent;
    final dotPaint = Paint()..color = colors.onBackground;
    for (final (_, c) in game.remainingStars) {
      final o = center(c);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: cell * 0.62, height: cell * 0.36), Radius.circular(cell * 0.08)), tagPaint);
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(Offset(o.dx + (i - 1.5) * cell * 0.12, o.dy), cell * 0.035, dotPaint);
      }
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
    // Chip kode (pemain): lingkaran fisika yang sama, dengan persegi chip di dalamnya.
    final b = Offset(game.x * cell, game.y * cell);
    final r = MazeGame.ballRadius * cell;
    canvas.drawCircle(b, r, Paint()..color = colors.primary);
    canvas.drawCircle(b, r, Paint()..color = colors.onPrimary..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: b, width: r * 0.9, height: r * 0.9), Radius.circular(r * 0.15)), Paint()..color = colors.onPrimary..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_MazePainter old) => true;
}
