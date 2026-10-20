import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/db/rate_cache.dart' show SettingsStore;
import '../auth/auth_controller.dart';

/// Rekor lokal Code Hunt untuk kartu di pemilih game: skor tertinggi dan tingkat tertinggi yang diselesaikan (indeks 0..2).
/// Hanya tampilan; skor resmi/papan peringkat tetap milik server. Disimpan di app_settings `codehunt_best` per pengguna.
class CodeHuntRecord {
  const CodeHuntRecord({this.bestScore = 0, this.bestLevel = -1});
  final int bestScore, bestLevel;

  bool get isEmpty => bestLevel < 0;

  CodeHuntRecord merge(int levelIndex, int score) =>
      CodeHuntRecord(bestScore: score > bestScore ? score : bestScore, bestLevel: levelIndex > bestLevel ? levelIndex : bestLevel);

  String encode() => jsonEncode({'score': bestScore, 'level': bestLevel});

  static CodeHuntRecord decode(String? raw) {
    if (raw == null) return const CodeHuntRecord();
    try {
      final j = jsonDecode(raw);
      if (j is Map && j['score'] is int && j['level'] is int && (j['score'] as int) >= 0 && (j['level'] as int) >= -1) {
        return CodeHuntRecord(bestScore: j['score'] as int, bestLevel: j['level'] as int);
      }
    } catch (_) {}
    return const CodeHuntRecord();
  }
}

class CodeHuntRecordStore {
  CodeHuntRecordStore(this._store, this._userId);
  final SettingsStore? _store;
  final String _userId;

  static const key = 'codehunt_best';

  factory CodeHuntRecordStore.of(BuildContext context) =>
      CodeHuntRecordStore(context.read<SettingsStore?>(), context.read<AuthController?>()?.user?.id ?? '');

  Future<CodeHuntRecord> load() async {
    try {
      return CodeHuntRecord.decode(await _store?.getSetting(key, userId: _userId));
    } catch (_) {
      return const CodeHuntRecord();
    }
  }

  Future<void> record(int levelIndex, int score) async {
    final r = (await load()).merge(levelIndex, score);
    try {
      await _store?.setSetting(key, r.encode(), userId: _userId);
    } catch (_) {}
  }
}
