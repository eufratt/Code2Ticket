import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/format.dart';
import '../../core/location/location_service.dart';
import '../../widgets/state_views.dart';
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
    final outcome = await tickets.redeem(code, lat: fix.ok ? fix.lat : null, lng: fix.ok ? fix.lng : null);
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
        padding: const EdgeInsets.all(24),
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

  Widget _form(bool busy) => ListView(
        children: [
          Text('Masukkan kode dari penyelenggara', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            key: const Key('code_field'),
            controller: _code,
            enabled: !busy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [CodeInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Kode',
              hintText: 'XXXX-XXXX-XXXX',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('submit_code'),
            onPressed: busy ? null : _submit,
            child: busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Tukar kode'),
          ),
          if (busy) const WakingUpNotice(),
          if (_errorCode == 'location_required' || _errorCode == 'out_of_area') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('enable_location'),
              onPressed: busy ? null : _enableLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Aktifkan lokasi'),
            ),
          ],
          if (_locationHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_locationHint!, key: const Key('location_hint')),
            ),
          const SizedBox(height: 24),
          Text(
            'Lokasi hanya dipakai untuk memeriksa area kode berbatas lokasi dan tidak disimpan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}

class _Success extends StatelessWidget {
  const _Success({required this.ticket, required this.onAgain});
  final RedeemedTicket ticket;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Tiket berhasil dibuat', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Text(formatTicketNumber(ticket.ticketNumber),
            key: const Key('ticket_number'),
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(ticket.giveawayTitle, textAlign: TextAlign.center),
        Text(ticket.prizeName, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        const Center(child: Chip(label: Text('Eligible'))),
        if (ticket.drawAt != null)
          Text('Draw: ${context.when(ticket.drawAt!)}', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => context.go('/tickets'), child: const Text('Lihat My Tickets')),
        TextButton(onPressed: onAgain, child: const Text('Input kode lain')),
      ],
    );
  }
}
