import 'dart:math';

import 'package:code2ticket/features/game/maze.dart';
import 'package:code2ticket/features/game/maze_game.dart';
import 'package:flutter_test/flutter_test.dart';

String render(Maze m) {
  final b = StringBuffer();
  for (var r = 0; r < m.rows; r++) {
    for (var c = 0; c < m.cols; c++) {
      b.write('${m.canMove(c, r, Dir.n) ? 1 : 0}${m.canMove(c, r, Dir.e) ? 1 : 0}${m.canMove(c, r, Dir.s) ? 1 : 0}${m.canMove(c, r, Dir.w) ? 1 : 0},');
    }
    b.writeln();
  }
  return b.toString();
}

void main() {
  group('generator labirin', () {
    test('selalu bisa diselesaikan, sempurna (tanpa siklus), semua sel terjangkau: 300 seed x 3 tingkat', () {
      for (final level in MazeLevel.all) {
        for (var seed = 0; seed < 100; seed++) {
          final m = Maze.generate(level.cols, level.rows, Random(seed), stars: level.stars);
          final cells = level.cols * level.rows;
          expect(m.passageCount, cells - 1, reason: '${level.name} seed $seed: pohon rentang');
          expect(m.distancesFromStart().every((d) => d >= 0), isTrue, reason: '${level.name} seed $seed: semua terjangkau');
          final path = m.solve();
          expect(path, isNotNull, reason: '${level.name} seed $seed');
          expect(path!.first, m.start);
          expect(path.last, m.exit);
          for (var i = 1; i < path.length; i++) {
            final (pc, pr) = path[i - 1];
            final (c, r) = path[i];
            final d = Dir.values.firstWhere((d) => pc + d.dx == c && pr + d.dy == r);
            expect(m.canMove(pc, pr, d), isTrue, reason: 'langkah $i bukan lorong');
          }
        }
      }
    });

    test('deterministik: seed sama = labirin sama; seed beda = (hampir pasti) beda', () {
      final a = Maze.generate(8, 8, Random(42), stars: 8);
      final b = Maze.generate(8, 8, Random(42), stars: 8);
      final c = Maze.generate(8, 8, Random(43), stars: 8);
      expect(render(a), render(b));
      expect(a.stars, b.stars);
      expect(a.exit, b.exit);
      expect(render(a) == render(c), isFalse);
    });

    test('pintu keluar = sel terjauh dari mulai', () {
      final m = Maze.generate(10, 10, Random(7));
      final d = m.distancesFromStart();
      expect(d[m.exit.$2 * m.cols + m.exit.$1], d.reduce(max));
      expect(m.exit, isNot(m.start));
    });

    test('bintang: jumlah sesuai, sel berbeda, bukan mulai atau keluar; dibatasi jumlah sel', () {
      for (final level in MazeLevel.all) {
        final m = Maze.generate(level.cols, level.rows, Random(3), stars: level.stars);
        expect(m.stars.length, level.stars);
        expect(m.stars.toSet().length, level.stars);
        expect(m.stars.contains(m.start), isFalse);
        expect(m.stars.contains(m.exit), isFalse);
      }
      expect(Maze.generate(2, 2, Random(1), stars: 99).stars.length, 2);
    });

    test('tingkat sesuai batas server: bintang <= 30, waktu <= 60 detik', () {
      expect(MazeLevel.all.length, 3);
      for (final l in MazeLevel.all) {
        expect(l.stars, lessThanOrEqualTo(30));
        expect(l.seconds, lessThanOrEqualTo(60));
        expect(l.stars, lessThan(l.cols * l.rows - 1));
      }
    });

    test('di luar grid selalu tertutup', () {
      final m = Maze.generate(4, 4, Random(1));
      expect(m.canMove(0, 0, Dir.n), isFalse);
      expect(m.canMove(0, 0, Dir.w), isFalse);
      expect(m.canMove(3, 3, Dir.s), isFalse);
      expect(m.canMove(3, 3, Dir.e), isFalse);
      expect(m.canMove(-1, 0, Dir.e), isFalse);
    });
  });

  group('skor (rumus sama dengan server)', () {
    test('selesai: bintang*100 + sisa*10; XP mentah bintang*10 + sisa', () {
      const s = GameScore(stars: 5, secondsLeft: 23, cleared: true, durationSec: 37);
      expect(s.score, 730);
      expect(s.xpRaw, 73);
      expect(s.toJson(), {'stars': 5, 'seconds_left': 23, 'cleared': true, 'duration_sec': 37});
    });

    test('tidak selesai: sisa waktu tidak dihitung', () {
      const s = GameScore(stars: 3, secondsLeft: 12, cleared: false, durationSec: 60);
      expect(s.countedSecondsLeft, 0);
      expect(s.score, 300);
      expect(s.xpRaw, 30);
    });

    test('skor 0 (tanpa bintang dan tidak selesai) tidak layak dikirim', () {
      expect(const GameScore(stars: 0, secondsLeft: 0, cleared: false, durationSec: 60).worthSubmitting, isFalse);
      expect(const GameScore(stars: 0, secondsLeft: 1, cleared: true, durationSec: 59).worthSubmitting, isTrue);
    });
  });

  group('permainan', () {
    Maze maze([int seed = 5]) => Maze.generate(6, 6, Random(seed), stars: 5);
    MazeGame newGame([int seed = 5]) => MazeGame(MazeLevel.easy, maze(seed))..start();

    test('belum mulai: tick tidak mengubah apa pun; mulai -> bermain', () {
      final g = MazeGame(MazeLevel.easy, maze());
      g.tick(1, ax: 5);
      expect(g.elapsed, 0);
      expect(g.status, GameStatus.ready);
      g.start();
      expect(g.status, GameStatus.playing);
    });

    test('jeda menghentikan waktu dan gerak; lanjut meneruskan', () {
      final g = newGame();
      g.tick(0.05);
      final t = g.timeLeft;
      g.pause();
      g.tick(1, ax: 9);
      expect(g.timeLeft, t);
      expect(g.nudge(Dir.e), isFalse);
      g.resume();
      g.tick(0.05);
      expect(g.timeLeft, lessThan(t));
    });

    test('menyusuri jalur terpendek dengan tombol panah menyelesaikan labirin (semua seed uji)', () {
      for (var seed = 0; seed < 50; seed++) {
        final g = newGame(seed);
        final path = g.maze.solve()!;
        for (var i = 1; i < path.length; i++) {
          final d = Dir.values.firstWhere((d) => path[i - 1].$1 + d.dx == path[i].$1 && path[i - 1].$2 + d.dy == path[i].$2);
          expect(g.nudge(d), isTrue);
        }
        expect(g.status, GameStatus.cleared, reason: 'seed $seed');
        expect(g.score.cleared, isTrue);
      }
    });

    test('panah ke arah dinding ditolak; posisi tidak berubah', () {
      final g = newGame();
      // Sel mulai (0,0): utara dan barat adalah batas luar.
      expect(g.nudge(Dir.n), isFalse);
      expect(g.nudge(Dir.w), isFalse);
      expect((g.x, g.y), (0.5, 0.5));
    });

    test('fisika: mendorong ke dinding tidak pernah menembusnya (bola tetap di dalam grid dan tidak melewati dinding tertutup)', () {
      for (var seed = 0; seed < 20; seed++) {
        final g = newGame(seed);
        final rnd = Random(seed);
        for (var i = 0; i < 1500 && g.status == GameStatus.playing; i++) {
          g.tick(1 / 60, ax: (rnd.nextDouble() - 0.5) * 30, ay: (rnd.nextDouble() - 0.5) * 30);
          expect(g.x, inInclusiveRange(MazeGame.ballRadius, g.maze.cols - MazeGame.ballRadius), reason: 'seed $seed langkah $i');
          expect(g.y, inInclusiveRange(MazeGame.ballRadius, g.maze.rows - MazeGame.ballRadius), reason: 'seed $seed langkah $i');
        }
      }
    });

    test('fisika: dengan percepatan sepanjang jalur, bola mencapai pintu keluar tanpa menembus dinding', () {
      final g = newGame(11);
      final path = g.maze.solve()!;
      var wp = 1;
      for (var i = 0; i < 60 * 60 && g.status == GameStatus.playing; i++) {
        // Pengendali sederhana: tarik bola ke titik tengah sel berikutnya pada jalur.
        final target = path[min(wp, path.length - 1)];
        final tx = target.$1 + 0.5, ty = target.$2 + 0.5;
        if ((g.x - tx).abs() < 0.12 && (g.y - ty).abs() < 0.12 && wp < path.length - 1) wp++;
        final tt = path[min(wp, path.length - 1)];
        g.tick(1 / 60, ax: ((tt.$1 + 0.5) - g.x) * 40 - g.vx * 6, ay: ((tt.$2 + 0.5) - g.y) * 40 - g.vy * 6);
      }
      expect(g.status, GameStatus.cleared);
    });

    test('mengambil bintang: sel bintang dilewati = terkumpul sekali; semua bintang di jalur terkumpul', () {
      final g = newGame(2);
      for (final (i, cell) in g.remainingStars.toList()) {
        g.x = cell.$1 + 0.5;
        g.y = cell.$2 + 0.5;
        g.tick(0.001);
        expect(g.collected.contains(i), isTrue);
      }
      expect(g.starsCollected, 5);
      g.tick(0.001);
      expect(g.starsCollected, 5);
    });

    test('waktu habis: status timeUp, skor tanpa bonus waktu, tick berikutnya diabaikan', () {
      final g = newGame();
      for (var i = 0; i < 60 * 70; i++) {
        g.tick(1 / 60);
      }
      expect(g.status, GameStatus.timeUp);
      expect(g.timeLeft, 0);
      expect(g.finished, isTrue);
      expect(g.score.cleared, isFalse);
      expect(g.score.countedSecondsLeft, 0);
      expect(g.score.durationSec, inInclusiveRange(59, 61));
      final e = g.elapsed;
      g.tick(1);
      expect(g.elapsed, e);
    });

    test('skor akhir selalu dalam rentang yang diterima server', () {
      final g = newGame();
      final path = g.maze.solve()!;
      for (var i = 1; i < path.length; i++) {
        g.tick(0.5);
        final d = Dir.values.firstWhere((d) => path[i - 1].$1 + d.dx == path[i].$1 && path[i - 1].$2 + d.dy == path[i].$2);
        g.x = path[i - 1].$1 + 0.5;
        g.y = path[i - 1].$2 + 0.5;
        g.nudge(d);
      }
      final s = g.score;
      expect(s.stars, inInclusiveRange(0, 30));
      expect(s.secondsLeft, inInclusiveRange(0, 60));
      expect(s.durationSec, inInclusiveRange(0, 600));
    });
  });
}
