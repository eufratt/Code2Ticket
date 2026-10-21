import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/currency/currency.dart';
import '../../core/open_link.dart';
import '../../core/rupiah_input.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time/zones.dart';
import '../../core/widgets/widgets.dart';
import '../discover/discover_filters.dart' show categoryLabel;
import 'admin_controller.dart';
import 'admin_models.dart';

/// Memilih tanggal + jam (waktu dinding WIB) -> instan; null = dibatalkan. Bisa diganti di tes.
typedef DateTimePicker = Future<DateTime?> Function(BuildContext context, DateTime initial);

Future<DateTime?> _defaultPicker(BuildContext context, DateTime initial) async {
  final wall = inZone(initial, AppZone.wib);
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime(wall.year, wall.month, wall.day),
    firstDate: DateTime(wall.year - 1),
    lastDate: DateTime(wall.year + 5),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: wall.hour, minute: wall.minute));
  if (time == null) return null;
  return instantFromWallClock(AppZone.wib, date.year, date.month, date.day, time.hour, time.minute);
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String? _required(String? v, {int max = 200, String label = 'Kolom ini'}) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return '$label wajib diisi';
  if (t.runes.length > max) return '$label maksimal $max karakter';
  return null;
}

/// Buat Giveaway (POST /admin/giveaways). Jadwal dalam WIB; draw harus di masa depan.
class CreateGiveawayScreen extends StatefulWidget {
  const CreateGiveawayScreen({super.key, this.pickDateTime = _defaultPicker});
  final DateTimePicker pickDateTime;

  @override
  State<CreateGiveawayScreen> createState() => _CreateGiveawayScreenState();
}

class _CreateGiveawayScreenState extends State<CreateGiveawayScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(), _organizer = TextEditingController(), _description = TextEditingController();
  final _prize = TextEditingController(), _value = TextEditingController(), _winners = TextEditingController(text: '1');
  final _maxTickets = TextEditingController();
  final _howTo = TextEditingController(), _orgUrl = TextEditingController();
  final _lat = TextEditingController(), _lng = TextEditingController(), _radius = TextEditingController(), _address = TextEditingController();
  String? _category;
  late DateTime _startAt, _endAt, _drawAt;
  bool _submitted = false;
  bool _geoRestricted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    final minute = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    _startAt = minute;
    _drawAt = minute.add(const Duration(minutes: 10));
    _endAt = _drawAt;
  }

  @override
  void dispose() {
    for (final c in [_title, _organizer, _description, _prize, _value, _winners, _maxTickets, _howTo, _orgUrl, _lat, _lng, _radius, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- validasi antar-kolom (lokasi dan jadwal)
  String? _coordError(TextEditingController c, {required double min, required double max, required TextEditingController other}) {
    final t = c.text.trim();
    if (t.isEmpty) return other.text.trim().isEmpty ? null : 'Isi lintang dan bujur bersamaan';
    final v = _num(t);
    if (v == null || v < min || v > max) return 'Harus antara ${min.toInt()} dan ${max.toInt()}';
    return null;
  }

  String? _radiusError() {
    final t = _radius.text.trim();
    if (t.isEmpty) return null;
    final v = _num(t);
    if (v == null || v <= 0 || v > 99999) return 'Radius harus lebih dari 0 km';
    if (_lat.text.trim().isEmpty || _lng.text.trim().isEmpty) return 'Isi koordinat dulu';
    return null;
  }

  /// Saklar batas lokasi butuh lintang, bujur, dan radius yang valid (server juga memeriksa).
  String? _geoSwitchError() {
    if (!_geoRestricted) return null;
    final radius = _num(_radius.text);
    if (_num(_lat.text) == null || _num(_lng.text) == null || radius == null || radius <= 0) {
      return 'Isi lintang, bujur, dan radius dulu untuk membatasi lokasi tukar kode.';
    }
    return null;
  }

  String? _dateError(String which) {
    final now = DateTime.now();
    return switch (which) {
      'draw' when !_drawAt.isAfter(now) => 'Jadwal draw harus di masa depan',
      'end' when !_endAt.isAfter(_startAt) => 'Berakhir harus setelah mulai',
      'end' when _endAt.isAfter(_drawAt) => 'Berakhir tidak boleh setelah jadwal draw',
      _ => null,
    };
  }

  Future<void> _pick(String which) async {
    final initial = switch (which) { 'start' => _startAt, 'end' => _endAt, _ => _drawAt };
    final picked = await widget.pickDateTime(context, initial);
    if (picked == null || !mounted) return;
    setState(() {
      switch (which) {
        case 'start':
          _startAt = picked;
        case 'end':
          _endAt = picked;
        default:
          // Berakhir ikut bergeser bila sama dengan draw lama atau melewati draw baru (undian umumnya ditutup saat draw).
          final follow = _endAt == _drawAt || _endAt.isAfter(picked);
          _drawAt = picked;
          if (follow) _endAt = picked;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final formOk = _form.currentState!.validate();
    final dateOk = _dateError('draw') == null && _dateError('end') == null;
    if (!formOk || !dateOk || _category == null || _geoSwitchError() != null) return;
    final c = context.read<AdminController>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _error = null);
    final lat = _num(_lat.text), lng = _num(_lng.text);
    final r = await c.createGiveaway(GiveawayDraft(
      title: _title.text.trim(),
      organizer: _organizer.text.trim(),
      description: _description.text.trim(),
      category: _category!,
      prizeName: _prize.text.trim(),
      prizeValueIdr: parseRupiah(_value.text)!,
      howToParticipate: _howTo.text.trim(),
      organizerUrl: _orgUrl.text.trim(),
      winnerCount: int.parse(_winners.text.trim()),
      maxTicketsPerUser: int.tryParse(_maxTickets.text.trim()),
      startAt: _startAt,
      endAt: _endAt,
      drawAt: _drawAt,
      latitude: lat,
      longitude: lng,
      radiusKm: _num(_radius.text),
      address: _address.text.trim(),
      redeemGeoRestricted: _geoRestricted,
    ));
    if (r == null || !mounted) return;
    if (!r.isOk) {
      setState(() => _error = r.error);
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Giveaway dibuat.')));
    router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AdminController>().busy;
    final theme = Theme.of(context);
    final auto = _submitted ? AutovalidateMode.always : AutovalidateMode.disabled;
    const gap = SizedBox(height: Spacing.s12);
    InputDecoration deco(String label, {String? hint, String? helper}) => InputDecoration(labelText: label, hintText: hint, helperText: helper, helperMaxLines: 3);

    return Scaffold(
      appBar: AppBar(title: const Text('Buat Giveaway')),
      body: Form(
        key: _form,
        autovalidateMode: auto,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
          children: [
            const SectionHeader('Informasi'),
            TextFormField(key: const Key('giveaway_title'), controller: _title, decoration: deco('Judul'), textCapitalization: TextCapitalization.sentences, validator: (v) => _required(v, max: 120, label: 'Judul')),
            gap,
            TextFormField(key: const Key('giveaway_organizer'), controller: _organizer, decoration: deco('Penyelenggara'), validator: (v) => _required(v, label: 'Penyelenggara')),
            gap,
            DropdownButtonFormField<String>(
              key: const Key('giveaway_category'),
              initialValue: _category,
              isExpanded: true,
              decoration: deco('Kategori'),
              items: [for (final c in giveawayCategories) DropdownMenuItem(value: c, child: Text(categoryLabel(c)))],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Pilih kategori' : null,
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_description'),
              controller: _description,
              decoration: deco('Deskripsi (opsional)'),
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v?.runes.length ?? 0) > 5000 ? 'Deskripsi maksimal 5000 karakter' : null,
            ),
            const SizedBox(height: Spacing.sectionGap),
            const SectionHeader('Hadiah'),
            TextFormField(key: const Key('giveaway_prize'), controller: _prize, decoration: deco('Nama hadiah'), validator: (v) => _required(v, label: 'Nama hadiah')),
            gap,
            TextFormField(
              key: const Key('giveaway_value'),
              controller: _value,
              decoration: deco('Nilai hadiah (Rp)', hint: '5.000.000', helper: 'Dalam rupiah, bilangan bulat. Aplikasi mengonversi ke mata uang pilihan pengguna.'),
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              validator: (v) {
                final n = parseRupiah(v ?? '');
                if (n == null || n <= 0) return 'Nilai hadiah harus berupa angka positif.';
                if (n > maxPrizeIdr) return 'Nilai hadiah maksimal ${formatMoney(maxPrizeIdr.toDouble(), 'IDR')}.';
                return null;
              },
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_winners'),
              controller: _winners,
              decoration: deco('Jumlah pemenang'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return n == null || n < 1 || n > 100 ? 'Isi bilangan 1 sampai 100' : null;
              },
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_max_tickets'),
              controller: _maxTickets,
              decoration: deco('Batas tiket per pengguna (opsional)', helper: 'Kosongkan untuk memakai bawaan server (10).'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                return n == null || n < 1 ? 'Minimal 1' : null;
              },
            ),
            const SizedBox(height: Spacing.sectionGap),
            const SectionHeader('Cara ikut'),
            TextFormField(
              key: const Key('giveaway_how_to'),
              controller: _howTo,
              decoration: deco('Cara mendapatkan kode', helper: 'Jelaskan di mana peserta mendapat kode dari penyelenggara.'),
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                final n = (v ?? '').trim().runes.length;
                if (n == 0) return 'Cara mendapatkan kode wajib diisi';
                if (n < 10) return 'Cara mendapatkan kode minimal 10 karakter';
                if (n > 2000) return 'Cara mendapatkan kode maksimal 2000 karakter';
                return null;
              },
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_org_url'),
              controller: _orgUrl,
              decoration: deco('Tautan penyelenggara (opsional)', hint: 'https://'),
              keyboardType: TextInputType.url,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                if (!t.toLowerCase().startsWith('https://')) return 'Tautan harus diawali https://';
                return isHttpsUrl(t) ? null : 'Tautan tidak valid';
              },
            ),
            const SizedBox(height: Spacing.sectionGap),
            const SectionHeader('Jadwal (WIB)'),
            _DateTimeField(fieldKey: const Key('pick_start_at'), label: 'Mulai', value: _startAt, onTap: () => _pick('start'), error: _submitted ? _dateError('start') : null),
            gap,
            _DateTimeField(fieldKey: const Key('pick_end_at'), label: 'Berakhir', value: _endAt, onTap: () => _pick('end'), error: _submitted ? _dateError('end') : null),
            gap,
            _DateTimeField(fieldKey: const Key('pick_draw_at'), label: 'Jadwal draw', value: _drawAt, onTap: () => _pick('draw'), error: _submitted ? _dateError('draw') : null),
            const SizedBox(height: Spacing.sectionGap),
            const SectionHeader('Batas lokasi (opsional)'),
            Text('Isi lintang, bujur, dan radius untuk lokasi giveaway. Nyalakan saklar di bawah bila penukaran kode harus dibatasi ke area itu.', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
            gap,
            TextFormField(
              key: const Key('giveaway_lat'),
              controller: _lat,
              decoration: deco('Lintang (latitude)', hint: '-6.2'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (_) => _coordError(_lat, min: -90, max: 90, other: _lng),
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_lng'),
              controller: _lng,
              decoration: deco('Bujur (longitude)', hint: '106.8'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (_) => _coordError(_lng, min: -180, max: 180, other: _lat),
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_radius'),
              controller: _radius,
              decoration: deco('Radius (km)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (_) => _radiusError(),
            ),
            gap,
            TextFormField(
              key: const Key('giveaway_address'),
              controller: _address,
              decoration: deco('Alamat (opsional)'),
              validator: (v) => (v?.runes.length ?? 0) > 500 ? 'Alamat maksimal 500 karakter' : null,
            ),
            gap,
            SwitchListTile(
              key: const Key('giveaway_geo_restricted'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Batasi tukar kode ke area giveaway ini'),
              subtitle: Text('Peserta harus berada dalam radius dari lokasi giveaway saat menukar kode.', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
              value: _geoRestricted,
              onChanged: (v) => setState(() => _geoRestricted = v),
            ),
            if (_submitted && _geoSwitchError() != null)
              Text(_geoSwitchError()!, key: const Key('geo_switch_error'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            const SizedBox(height: Spacing.sectionGap),
            if (_error != null) ...[
              InlineMessage(_error!),
              const SizedBox(height: Spacing.s12),
            ],
            PrimaryButton(key: const Key('submit_giveaway'), label: 'Buat giveaway', icon: Icons.add, loading: busy, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

/// Kolom tanggal+jam (ketuk -> pemilih). Menampilkan "19 Okt 2026, 03.42 WIB".
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.fieldKey, required this.label, required this.value, required this.onTap, this.error});
  final Key fieldKey;
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, ${formatInZone(value, AppZone.wib)}',
      excludeSemantics: true,
      child: InkWell(
        key: fieldKey,
        onTap: onTap,
        borderRadius: Radii.inputAll,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, errorText: error, suffixIcon: const Icon(Icons.edit_calendar_outlined)),
          child: Text(formatInZone(value, AppZone.wib)),
        ),
      ),
    );
  }
}
