import 'dart:async';

import 'package:flutter/foundation.dart';

/// Saat data berasal dari cache (jaringan gagal), coba muat ulang berkala sampai online lagi.
/// Tidak memakai paket konektivitas: cukup mencoba permintaan yang sama.
mixin OfflineRetry on ChangeNotifier {
  /// null = tanpa muat ulang otomatis (tes).
  Duration? get retryInterval;

  /// Memuat ulang tanpa menampilkan indikator memuat; gagal lagi tidak mengubah apa pun.
  Future<void> reloadSilently();

  Timer? _retryTimer;

  void scheduleRetry() {
    final every = retryInterval;
    if (every == null) return;
    _retryTimer ??= Timer.periodic(every, (_) => reloadSilently());
  }

  void cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  void dispose() {
    cancelRetry();
    super.dispose();
  }
}

/// Menjalankan operasi cache tanpa pernah melempar: cache hanyalah bonus, bukan syarat tampilan.
Future<T?> bestEffort<T>(Future<T?> Function() op) async {
  try {
    return await op();
  } catch (_) {
    return null;
  }
}
