import 'package:flutter/foundation.dart';

import 'api/authed_api.dart';

/// Mencatat aktivitas ringan (POST /activity) sebagai masukan rekomendasi. Tembak-dan-lupa: tidak pernah memblokir UI,
/// tidak di-retry, dan kegagalan hanya dicatat lewat debugPrint tanpa data sensitif (hanya jenis aktivitas dan kode galat).
/// Jenis yang diterima server: view_giveaway, search, game_played, chat. Tiket dibuat server sendiri (ticket_created) dan
/// skor game mencatat game_played di server, jadi klien tidak mengirim keduanya.
class ActivityLogger {
  const ActivityLogger(this._api);
  final AuthedApi _api;

  void viewGiveaway({required String giveawayId, required String category}) =>
      log('view_giveaway', body: {'giveaway_id': giveawayId, 'category': category});

  void log(String type, {Map<String, dynamic> body = const {}}) {
    try {
      _api.post('/activity', body: {'type': type, ...body}, retry: false).catchError((Object e) {
        debugPrint('activity $type gagal: ${e.runtimeType}');
        return <String, dynamic>{};
      });
    } catch (e) {
      debugPrint('activity $type gagal: ${e.runtimeType}');
    }
  }
}
