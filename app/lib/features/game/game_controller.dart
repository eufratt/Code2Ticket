import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'maze_game.dart';

/// Satu baris GET /game/leaderboard (skor total 7 hari terakhir). Hanya field yang dikirim server.
class LeaderboardEntry {
  const LeaderboardEntry({required this.rank, required this.username, required this.level, required this.totalScore});
  final int rank, level, totalScore;
  final String username;

  static LeaderboardEntry? tryParse(dynamic raw) {
    final j = asMap(raw);
    final name = asString(j?['username']);
    if (j == null || name == null) return null;
    return LeaderboardEntry(rank: asInt(j['rank']), username: name, level: asInt(j['level'], 1), totalScore: asInt(j['total_score']));
  }
}

/// Hasil POST /game/scores yang sukses.
class GameSubmitResult {
  const GameSubmitResult({required this.score, required this.xpEarned, required this.dailyXpTotal, required this.dailyCapReached});
  final int score, xpEarned, dailyXpTotal;
  final bool dailyCapReached;
}

/// Hasil pengiriman: [data] atau [error] (pesan Indonesia siap tampil).
class GameOutcome {
  const GameOutcome.ok(GameSubmitResult this.data) : error = null;
  const GameOutcome.fail(String this.error) : data = null;
  final GameSubmitResult? data;
  final String? error;
  bool get isOk => error == null;
}

String gameErrorMessage(String? code) => switch (code) {
      'invalid_input' => 'Skor ditolak server: data permainan tidak valid.',
      'invalid_score' => 'Skor ditolak server: hasil permainan tidak wajar.',
      'too_many_requests' => 'Terlalu banyak permintaan. Tunggu sebentar lalu kirim ulang.',
      _ => 'Gagal mengirim skor ($code).',
    };

/// Kirim skor game (POST /game/scores, tanpa retry otomatis, satu per satu) dan papan peringkat (GET /game/leaderboard).
/// Server penentu skor/XP/lencana: respons `user` dipasang ke AuthController supaya Profil menampilkan level, XP, dan
/// lencana versi server.
class GameController extends ChangeNotifier {
  GameController(this._api, this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;

  bool submitting = false;

  List<LeaderboardEntry> entries = const [];
  LoadState state = LoadState.idle;
  String? error;
  Future<void>? _inflight;

  /// null = sedang mengirim atau sesi berakhir.
  Future<GameOutcome?> submitScore(GameScore s) async {
    if (submitting) return null;
    submitting = true;
    notifyListeners();
    try {
      final r = await _api.post('/game/scores', body: s.toJson(), retry: false);
      if (r['ok'] == false) return GameOutcome.fail(gameErrorMessage(asString(r['error'])));
      final u = asMap(r['user']);
      if (u != null) {
        try {
          _auth.updateUser(AppUser.fromJson(u));
        } catch (_) {/* bentuk user tak terduga: skor tetap tercatat */}
      }
      return GameOutcome.ok(GameSubmitResult(
        score: asInt(r['score']),
        xpEarned: asInt(r['xp_earned']),
        dailyXpTotal: asInt(r['daily_xp_total']),
        dailyCapReached: r['daily_cap_reached'] == true,
      ));
    } on InvalidSessionException {
      return null;
    } on ForbiddenException {
      return const GameOutcome.fail('Akses ditolak.');
    } on NetworkException catch (e) {
      return GameOutcome.fail(e.message);
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> loadLeaderboard() => _inflight ??= _loadLeaderboard().whenComplete(() => _inflight = null);

  Future<void> _loadLeaderboard() async {
    state = LoadState.loading;
    error = null;
    notifyListeners();
    try {
      final r = await _api.get('/game/leaderboard?limit=50');
      if (r['ok'] == false) throw NetworkException('Gagal memuat papan peringkat (${r['error']}).');
      entries = parseList(r['data'], LeaderboardEntry.tryParse);
      state = LoadState.loaded;
    } on InvalidSessionException {
      return;
    } on NetworkException catch (e) {
      error = e.message;
      state = LoadState.error;
    } on ForbiddenException {
      error = 'Akses ditolak.';
      state = LoadState.error;
    }
    notifyListeners();
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (entries.isNotEmpty || state != LoadState.idle)) {
      entries = const [];
      state = LoadState.idle;
      error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
