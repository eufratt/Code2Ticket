import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'redeem_messages.dart';
import 'ticket_models.dart';

/// Tiket milik pengguna + penukaran kode. Dikosongkan saat logout.
class TicketsController extends ChangeNotifier {
  TicketsController(this._api, this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;

  List<Ticket> items = const [];
  LoadState state = LoadState.idle;
  String? error;
  bool redeeming = false;
  Future<void>? _inflight;

  /// Jumlah tiket saya pada satu giveaway.
  int countFor(String giveawayId) => items.where((t) => t.giveawayId == giveawayId).length;

  /// Tiket dikelompokkan per giveaway (urutan kemunculan = tiket terbaru dulu, sesuai server).
  Map<String, List<Ticket>> get grouped {
    final out = <String, List<Ticket>>{};
    for (final t in items) {
      (out[t.giveawayId] ??= []).add(t);
    }
    return out;
  }

  Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  Future<void> _load() async {
    state = LoadState.loading;
    error = null;
    notifyListeners();
    try {
      final r = await _api.get('/tickets');
      if (r['ok'] == false) {
        throw NetworkException('Gagal memuat tiket (${r['error']}).');
      }
      items = parseList(r['data'], Ticket.tryParse);
      state = LoadState.loaded;
    } on InvalidSessionException {
      return; // AuthedApi sudah logout; router pindah ke Login
    } on NetworkException catch (e) {
      error = e.message;
      state = LoadState.error;
    }
    notifyListeners();
  }

  /// Menukar kode dengan tiket. Satu permintaan pada satu waktu, tanpa retry otomatis.
  /// Mengembalikan null bila sedang berjalan atau sesi berakhir.
  Future<RedeemOutcome?> redeem(String code, {double? lat, double? lng}) async {
    if (redeeming) return null;
    redeeming = true;
    notifyListeners();
    try {
      final r = await _api.post(
        '/codes/redeem',
        body: {'code': code, 'lat': lat, 'lng': lng},
        retry: false,
      );
      final outcome = RedeemOutcome.fromJson(r);
      if (outcome.isSuccess) unawaited(load());
      return outcome;
    } on InvalidSessionException {
      return null;
    } on NetworkException {
      return const RedeemOutcome.failure('network');
    } finally {
      redeeming = false;
      notifyListeners();
    }
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (items.isNotEmpty || state != LoadState.idle)) {
      items = const [];
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

/// Pesan siap tampil untuk hasil gagal.
String outcomeMessage(RedeemOutcome o) => o.error == 'network'
    ? redeemNetworkMessage
    : redeemErrorMessage(o.error ?? 'unknown', retryAfterSeconds: o.retryAfterSeconds);
