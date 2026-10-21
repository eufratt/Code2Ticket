import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../core/notifications/notification_service.dart';
import 'ticket_models.dart';
import 'tickets_controller.dart';

final _codeRe = RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');

/// Huruf besar, hanya A-Z/0-9, strip otomatis tiap 4 karakter (XXXX-XXXX-XXXX).
class CodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    final raw = next.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final s = raw.length > 12 ? raw.substring(0, 12) : raw;
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && i % 4 == 0) out.write('-');
      out.write(s[i]);
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// S-CODE dan S-CODE-RESULT. Lokasi (lat/lng) dikirim HANYA bila izin lokasi sudah diberikan (tanpa memunculkan
/// dialog izin); tidak disimpan di server maupun lokal.
class InputCodeScreen extends StatefulWidget {
  const InputCodeScreen({super.key});
  @override
  State<InputCodeScreen> createState() => _InputCodeScreenState();
}

class _InputCodeScreenState extends State<InputCodeScreen> {
  final _code = TextEditingController();
  String? _error;
  String? _errorCode;
  String? _locationHint;
  bool _busy = false;
  RedeemedTicket? _ticket;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tickets = context.read<TicketsController>();
    if (_busy || tickets.redeeming) return; // cegah kirim ganda (termasuk saat menunggu posisi)
    final code = _code.text.trim();
    if (!_codeRe.hasMatch(code)) {
      setState(() {
        _error = 'Format kode harus XXXX-XXXX-XXXX.';
        _errorCode = 'invalid_format';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
      _locationHint = null;
    });
    // Posisi hanya bila izin sudah ada; tanpa dialog izin, dan hanya hidup di variabel lokal ini.
    final fix = await context.read<LocationService>().locate(prompt: false);
    if (!mounted) return;
    final notifier = context.read<NotificationService?>();
    final outcome = await tickets.redeem(code, lat: fix.ok ? fix.lat : null, lng: fix.ok ? fix.lng : null);
    // Notifikasi sistem tetap muncul walau layar sudah ditinggalkan; isinya tanpa kode.
    if (outcome?.ticket != null) notifier?.onTicketCreated(outcome!.ticket!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ticket = outcome?.ticket;
      _error = outcome == null || outcome.isSuccess ? null : outcomeMessage(outcome);
      _errorCode = outcome?.error;
    });
  }

  /// Aksi pengguna: minta izin / buka pengaturan supaya kode berbatas area bisa diperiksa.
  Future<void> _enableLocation() async {
    final svc = context.read<LocationService>();
    final fix = await svc.locate(prompt: true);
    if (!mounted) return;
    if (!fix.ok) await svc.openSettingsFor(fix.status);
    if (!mounted) return;
    setState(() => _locationHint = fix.ok
        ? 'Lokasi aktif. Tekan "Tukar kode" untuk mencoba lagi.'
        : locationStatusMessage(fix.status));
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<TicketsController>().redeeming || _busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Input Code')),
      body: Padding(
        padding: const EdgeInsets.all(Spacing.s24),
        child: _ticket != null ? _Success(ticket: _ticket!, onAgain: _again) : _form(busy),
      ),
    );
  }

  void _again() => setState(() {
        _ticket = null;
        _error = null;
        _errorCode = null;
        _locationHint = null;
        _code.clear();
      });

  Widget _form(bool busy) {
    final theme = Theme.of(context);
    final c = context.colors;
    return ListView(
      children: [
        Text('Masukkan kode dari penyelenggara', style: theme.textTheme.titleMedium),
        const SizedBox(height: Spacing.s4),
        Text('Kode terdiri dari 12 huruf dan angka.', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
        const SizedBox(height: Spacing.s24),
        TextField(
          key: const Key('code_field'),
          controller: _code,
          enabled: !busy,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [CodeInputFormatter()],
          // Kolom besar bermonospace: karakter mirip (0/O, 1/I) mudah dibedakan.
          style: AppTypography.mono(theme.textTheme.headlineSmall!).copyWith(letterSpacing: 2),
          decoration: InputDecoration(
            labelText: 'Kode',
            hintText: 'XXXX-XXXX-XXXX',
            errorText: _error,
            errorMaxLines: 3,
            contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s24),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Spacing.s24),
        PrimaryButton(key: const Key('submit_code'), label: 'Tukar kode', loading: busy, onPressed: busy ? null : _submit),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.s8),
          child: Text('Belum punya kode? Lihat cara mendapatkannya di detail giveaway.', key: const Key('code_help'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
        ),
        if (busy) const WakingUpNotice(),
        if (_errorCode == 'location_required' || _errorCode == 'out_of_area') ...[
          const SizedBox(height: Spacing.s12),
          PrimaryButton(
            key: const Key('enable_location'),
            label: 'Aktifkan lokasi',
            icon: Icons.my_location,
            variant: ButtonVariant.secondary,
            onPressed: busy ? null : _enableLocation,
          ),
        ],
        if (_locationHint != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s12),
            child: Text(_locationHint!, key: const Key('location_hint'), style: theme.textTheme.bodyMedium),
          ),
        const SizedBox(height: Spacing.s24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: c.muted),
            const SizedBox(width: Spacing.s8),
            Expanded(
              child: Text(
                'Lokasi hanya dipakai untuk memeriksa area giveaway berbatas lokasi dan tidak disimpan.',
                style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Hasil sukses: tiket "muncul" (skala + pudar, 250 ms; langsung tampil bila animasi dikurangi), nomor tiket besar.
class _Success extends StatelessWidget {
  const _Success({required this.ticket, required this.onAgain});
  final RedeemedTicket ticket;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return ListView(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context, Motion.slow),
          curve: Motion.curve,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
          ),
          child: Column(
            children: [
              ExcludeSemantics(child: Icon(Icons.check_circle, size: 72, color: c.success)),
              const SizedBox(height: Spacing.s12),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text('Tiket berhasil dibuat', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              ),
              const SizedBox(height: Spacing.s24),
              TicketCard(
                numberKey: const Key('ticket_number'),
                title: ticket.giveawayTitle,
                category: null,
                ticketNumber: formatTicketNumber(ticket.ticketNumber),
                status: AppStatus.ticketEligible,
                prizeText: ticket.prizeName,
                subtitle: ticket.drawAt == null ? null : 'Draw: ${context.when(ticket.drawAt!)}',
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.s24),
        PrimaryButton(label: 'Lihat tiket', onPressed: () => context.pushReplacement('/tickets')),
        const SizedBox(height: Spacing.s8),
        PrimaryButton(label: 'Input kode lain', variant: ButtonVariant.text, onPressed: onAgain),
      ],
    );
  }
}
