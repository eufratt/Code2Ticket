import 'dart:collection';
import 'dart:math';

/// Arah gerak di labirin. Nilai [bit] dipakai pada bitmask lorong terbuka tiap sel.
enum Dir {
  n(1, 0, -1),
  e(2, 1, 0),
  s(4, 0, 1),
  w(8, -1, 0);

  const Dir(this.bit, this.dx, this.dy);
  final int bit, dx, dy;

  Dir get opposite => switch (this) { n => s, s => n, e => w, w => e };
}

typedef Cell = (int col, int row);

/// Tingkat kesulitan: ukuran grid, jumlah bintang, dan batas waktu (detik). Batas server: bintang 0..30, sisa waktu 0..60
/// (backend\src\services\features.js, scoreSchema), jadi semua tingkat <= 60 detik dan <= 30 bintang.
class MazeLevel {
  const MazeLevel(this.name, this.cols, this.rows, this.stars, this.seconds);
  final String name;
  final int cols, rows, stars, seconds;

  static const easy = MazeLevel('Mudah', 6, 6, 5, 60);
  static const medium = MazeLevel('Sedang', 8, 8, 8, 55);
  static const hard = MazeLevel('Sulit', 10, 10, 12, 50);
  static const all = [easy, medium, hard];
}

/// Labirin "sempurna" (tanpa siklus, semua sel terhubung) dari recursive backtracker (DFS iteratif), sehingga SELALU bisa
/// diselesaikan. Mulai di pojok kiri-atas; pintu keluar = sel terjauh dari mulai (jarak lorong). Deterministik untuk seed yang sama.
class Maze {
  Maze._(this.cols, this.rows, this._open, this.start, this.exit, this.stars);

  final int cols, rows;
  final List<int> _open;
  final Cell start, exit;

  /// Letak bintang: sel berbeda, bukan sel mulai maupun keluar.
  final List<Cell> stars;

  static Maze generate(int cols, int rows, Random rnd, {int stars = 0}) {
    assert(cols >= 2 && rows >= 2);
    final open = List<int>.filled(cols * rows, 0);
    final visited = List<bool>.filled(cols * rows, false);
    int idx(int c, int r) => r * cols + c;
    final stack = <Cell>[(0, 0)];
    visited[0] = true;
    while (stack.isNotEmpty) {
      final (c, r) = stack.last;
      final options = [
        for (final d in Dir.values)
          if (c + d.dx >= 0 && c + d.dx < cols && r + d.dy >= 0 && r + d.dy < rows && !visited[idx(c + d.dx, r + d.dy)]) d,
      ];
      if (options.isEmpty) {
        stack.removeLast();
        continue;
      }
      final d = options[rnd.nextInt(options.length)];
      final nc = c + d.dx, nr = r + d.dy;
      open[idx(c, r)] |= d.bit;
      open[idx(nc, nr)] |= d.opposite.bit;
      visited[idx(nc, nr)] = true;
      stack.add((nc, nr));
    }
    final dist = _bfs(cols, rows, open, (0, 0));
    var far = (0, 0), best = -1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (dist[idx(c, r)] > best) {
          best = dist[idx(c, r)];
          far = (c, r);
        }
      }
    }
    final candidates = [
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++)
          if ((c, r) != (0, 0) && (c, r) != far) (c, r),
    ]..shuffle(rnd);
    return Maze._(cols, rows, open, (0, 0), far, candidates.take(min(stars, candidates.length)).toList());
  }

  static List<int> _bfs(int cols, int rows, List<int> open, Cell from) {
    final dist = List<int>.filled(cols * rows, -1);
    dist[from.$2 * cols + from.$1] = 0;
    final q = Queue<Cell>()..add(from);
    while (q.isNotEmpty) {
      final (c, r) = q.removeFirst();
      for (final d in Dir.values) {
        if (open[r * cols + c] & d.bit == 0) continue;
        final nc = c + d.dx, nr = r + d.dy;
        if (dist[nr * cols + nc] >= 0) continue;
        dist[nr * cols + nc] = dist[r * cols + c] + 1;
        q.add((nc, nr));
      }
    }
    return dist;
  }

  /// true bila ada lorong dari sel ([c], [r]) ke arah [d]. Di luar grid selalu tertutup.
  bool canMove(int c, int r, Dir d) => c >= 0 && c < cols && r >= 0 && r < rows && _open[r * cols + c] & d.bit != 0;

  /// Jumlah lorong (sisi yang dibuka); labirin sempurna = sel - 1.
  int get passageCount => _open.fold<int>(0, (a, m) => a + (m & 1 != 0 ? 1 : 0) + (m & 2 != 0 ? 1 : 0) + (m & 4 != 0 ? 1 : 0) + (m & 8 != 0 ? 1 : 0)) ~/ 2;

  /// Jarak lorong (jumlah langkah) dari mulai ke tiap sel; -1 bila tak terjangkau (tidak pernah terjadi).
  List<int> distancesFromStart() => _bfs(cols, rows, _open, start);

  /// Jalur terpendek mulai -> keluar (termasuk kedua ujung); null bila tidak ada.
  List<Cell>? solve() {
    final prev = <Cell, Cell>{};
    final q = Queue<Cell>()..add(start);
    final seen = {start};
    while (q.isNotEmpty) {
      final cur = q.removeFirst();
      if (cur == exit) {
        final path = <Cell>[cur];
        while (path.last != start) {
          path.add(prev[path.last]!);
        }
        return path.reversed.toList();
      }
      for (final d in Dir.values) {
        if (!canMove(cur.$1, cur.$2, d)) continue;
        final n = (cur.$1 + d.dx, cur.$2 + d.dy);
        if (seen.add(n)) {
          prev[n] = cur;
          q.add(n);
        }
      }
    }
    return null;
  }
}
