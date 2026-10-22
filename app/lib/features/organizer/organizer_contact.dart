import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/db/rate_cache.dart' show SettingsStore;
import '../../core/json.dart';
import '../../core/offline.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;

/// Kontak admin untuk penyelenggara dari GET /app-config/organizer. Server sudah memvalidasi; app memeriksa ulang
/// karena cache atau server lama tidak boleh dipercaya begitu saja. Email tidak valid -> tanpa kontak.
class OrganizerContact {
  const OrganizerContact({required this.email, this.note});
  final String email;
  final String? note;

  static final _emailRe = RegExp(r'^[^\s@\x00-\x1f\x7f]+@[^\s@\x00-\x1f\x7f]+\.[^\s@\x00-\x1f\x7f]+$');

  static OrganizerContact? tryParse(dynamic v) {
    final m = asMap(v);
    final email = asString(m?['email'])?.trim() ?? '';
    if (email.isEmpty || email.length > 254 || !_emailRe.hasMatch(email)) return null;
    final note = asString(m?['note'])?.trim() ?? '';
    return OrganizerContact(email: email, note: note.isEmpty || note.runes.length > 300 ? null : note);
  }

  Map<String, dynamic> toJson() => {'email': email, 'note': note};
}

/// Bidang isian di badan email.
const organizerMailFields = [
  'Nama giveaway',
  'Deskripsi giveaway',
  'Kategori',
  'Nama hadiah',
  'Nilai hadiah (Rp)',
  'Periode mulai',
  'Periode berakhir',
  'Jadwal draw',
  'Jumlah pemenang',
  'Batas tiket per peserta',
  'Jumlah kode yang dibutuhkan',
  'Cara mendapatkan kode',
  'Tautan penyelenggara (opsional)',
  'Lokasi dan radius (bila tukar kode dibatasi area)',
];

const organizerMailSubject = 'Permintaan membuat giveaway di Code2Ticket';

String organizerMailBody() => [
      'Halo admin Code2Ticket,',
      '',
      'Saya ingin membuat giveaway. Berikut datanya:',
      '',
      for (final f in organizerMailFields) '$f:',
      '',
      'Terima kasih.',
    ].join('\r\n');

/// mailto: dengan subjek dan isi ter-encode persen (spasi = %20; `queryParameters` memakai "+" yang tidak dipahami klien email).
Uri organizerMailto(String email) => Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(organizerMailSubject)}&body=${Uri.encodeComponent(organizerMailBody())}',
    );

/// Memuat kontak admin. Online -> disimpan di app_settings `organizer_contact` (per perangkat); jaringan gagal -> pakai
/// simpanan terakhir bila ada. Tanpa kontak (belum diisi, server lama, atau offline tanpa simpanan) = [contact] null.
class OrganizerContactController extends ChangeNotifier {
  OrganizerContactController(this._api, this._store);
  final AuthedApi _api;
  final SettingsStore _store;
  static const cacheKey = 'organizer_contact';

  OrganizerContact? contact;
  LoadState state = LoadState.idle;
  Future<void>? _inflight;

  Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  Future<void> _load() async {
    state = LoadState.loading;
    notifyListeners();
    try {
      final r = await _api.get('/app-config/organizer');
      contact = r['ok'] == false ? null : OrganizerContact.tryParse(r);
      await bestEffort(() async => _store.setSetting(cacheKey, contact == null ? null : jsonEncode(contact!.toJson())));
    } on InvalidSessionException {
      return; // AuthedApi sudah logout; router pindah ke Login
    } on NetworkException {
      contact = await bestEffort(_cached);
    }
    state = LoadState.loaded;
    notifyListeners();
  }

  Future<OrganizerContact?> _cached() async {
    final raw = await _store.getSetting(cacheKey);
    return raw == null ? null : OrganizerContact.tryParse(jsonDecode(raw));
  }
}
