import 'dart:math';

import 'maze.dart';

enum GameStatus { ready, playing, paused, cleared, timeUp }

/// Skor satu permainan, rumus SAMA dengan server (backend\src\services\features.js, submitGameScore):
/// skor = bintang*100 + sisa_waktu*10 (sisa waktu hanya dihitung bila labirin selesai); XP mentah = bintang*10 + sisa_waktu.
/// Server tetap penentu (batas XP harian, validasi rentang); angka di sini hanya pratinjau dan bahan kirim.
class GameScore {
  const GameScore({required this.stars, required this.secondsLeft, required this.cleared, required this.durationSec});

  final int stars, secondsLeft, durationSec;
  final bool cleared;

  /// Sisa waktu yang dihitung (0 bila tidak selesai).
  int get countedSecondsLeft => cleared ? secondsLeft : 0;
  int get score => stars * 100 + countedSecondsLeft * 10;
  int get xpRaw => stars * 10 + countedSecondsLeft;

  /// Tidak ada yang layak dikirim bila tidak selesai dan tanpa bintang (skor 0).
  bool get worthSubmitting => score > 0;

  /// Badan POST /game/scores.
  Map<String, dynamic> toJson() => {'stars': stars, 'seconds_left': secondsLeft, 'cleared': cleared, 'duration_sec': durationSec};
}

/// Keadaan satu permainan labirin; murni logika (tanpa Flutter) sehingga bisa diuji. Satuan posisi = sel (sel (c,r)
/// menempati [c, c+1) x [r, r+1)); bola berupa lingkaran berjari-jari [ballRadius], dinding setebal 2*[wallHalf].
class MazeGame {
  MazeGame(this.level, this.maze)
      : x = maze.start.$1 + 0.5,
        y = maze.start.$2 + 0.5,
        timeLeft = level.seconds.toDouble() {
    _buildWalls();
  }

  static const ballRadius = 0.26, wallHalf = 0.06, maxSpeed = 4.5, damping = 3.0, pickRadius = 0.42;

  final MazeLevel level;
  final Maze maze;
  double x, y, vx = 0, vy = 0;
  double timeLeft, elapsed = 0;
  GameStatus status = GameStatus.ready;
  final Set<int> collected = {};
  final List<(double, double, double, double)> _walls = []; // l, t, r, b

  int get starsCollected => collected.length;
  bool get finished => status == GameStatus.cleared || status == GameStatus.timeUp;

  /// Indeks bintang yang belum diambil beserta sel-nya.
  Iterable<(int, Cell)> get remainingStars sync* {
    for (var i = 0; i < maze.stars.length; i++) {
      if (!collected.contains(i)) yield (i, maze.stars[i]);
    }
  }

  GameScore get score => GameScore(
        stars: starsCollected,
        secondsLeft: timeLeft.floor().clamp(0, 60),
        cleared: status == GameStatus.cleared,
        durationSec: elapsed.round().clamp(0, 600),
      );

  void start() {
    if (status == GameStatus.ready) status = GameStatus.playing;
  }

  void pause() {
    if (status == GameStatus.playing) status = GameStatus.paused;
  }

  void resume() {
    if (status == GameStatus.paused) status = GameStatus.playing;
  }

  void _buildWalls() {
    void add(double l, double t, double r, double b) => _walls.add((l - wallHalf, t - wallHalf, r + wallHalf, b + wallHalf));
    for (var r = 0; r < maze.rows; r++) {
      for (var c = 0; c < maze.cols; c++) {
        if (!maze.canMove(c, r, Dir.n)) add(c.toDouble(), r.toDouble(), c + 1.0, r.toDouble());
        if (!maze.canMove(c, r, Dir.w)) add(c.toDouble(), r.toDouble(), c.toDouble(), r + 1.0);
        if (r == maze.rows - 1 && !maze.canMove(c, r, Dir.s)) add(c.toDouble(), r + 1.0, c + 1.0, r + 1.0);
        if (c == maze.cols - 1 && !maze.canMove(c, r, Dir.e)) add(c + 1.0, r.toDouble(), c + 1.0, r + 1.0);
      }
    }
  }

  bool _hitsWall(double px, double py) {
    for (final (l, t, r, b) in _walls) {
      if (px + ballRadius < l || px - ballRadius > r || py + ballRadius < t || py - ballRadius > b) continue;
      final cx = px.clamp(l, r), cy = py.clamp(t, b);
      final dx = px - cx, dy = py - cy;
      if (dx * dx + dy * dy < ballRadius * ballRadius) return true;
    }
    return false;
  }

  /// Memajukan permainan [dt] detik dengan percepatan ([ax], [ay]) dalam sel/detik^2 (arah layar: x kanan, y bawah).
  void tick(double dt, {double ax = 0, double ay = 0}) {
    if (status != GameStatus.playing) return;
    final h = min(dt, 0.05);
    elapsed += h;
    timeLeft -= h;
    vx += ax * h;
    vy += ay * h;
    final f = max(0.0, 1 - damping * h);
    vx *= f;
    vy *= f;
    final sp = sqrt(vx * vx + vy * vy);
    if (sp > maxSpeed) {
      vx *= maxSpeed / sp;
      vy *= maxSpeed / sp;
    }
    // Sumbu dipisah supaya bola meluncur menyusuri dinding, bukan menempel.
    final nx = x + vx * h;
    if (_hitsWall(nx, y)) {
      vx = 0;
    } else {
      x = nx;
    }
    final ny = y + vy * h;
    if (_hitsWall(x, ny)) {
      vy = 0;
    } else {
      y = ny;
    }
    _afterMove();
    if (status == GameStatus.playing && timeLeft <= 0) {
      timeLeft = 0;
      status = GameStatus.timeUp;
    }
  }

  /// Kontrol alternatif (tombol panah): pindah satu sel dari sel tempat bola berada bila lorongnya terbuka.
  bool nudge(Dir d) {
    if (status != GameStatus.playing) return false;
    final c = x.floor().clamp(0, maze.cols - 1), r = y.floor().clamp(0, maze.rows - 1);
    if (!maze.canMove(c, r, d)) return false;
    x = c + d.dx + 0.5;
    y = r + d.dy + 0.5;
    vx = 0;
    vy = 0;
    _afterMove();
    return true;
  }

  void _afterMove() {
    for (final (i, cell) in remainingStars.toList()) {
      final dx = x - (cell.$1 + 0.5), dy = y - (cell.$2 + 0.5);
      if (dx * dx + dy * dy <= pickRadius * pickRadius) collected.add(i);
    }
    final ex = x - (maze.exit.$1 + 0.5), ey = y - (maze.exit.$2 + 0.5);
    if (ex * ex + ey * ey <= pickRadius * pickRadius) status = GameStatus.cleared;
  }
}
