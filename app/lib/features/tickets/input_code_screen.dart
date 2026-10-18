import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
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

/// S-CODE dan S-CODE-RESULT. Lokasi dikirim null dulu (LBS di M4).
class InputCodeScreen extends StatefulWidget {
  const InputCodeScreen({super.key});
  @override
  State<InputCodeScreen> createState() => _InputCodeScreenState();
}

class _InputCodeScreenState extends State<InputCodeScreen> {
  final _code = TextEditingController();
  String? _error;
  RedeemedTicket? _ticket;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tickets = context.read<TicketsController>();
    if (tickets.redeeming) return; // cegah kirim ganda
    final code = _code.text.trim();
    if (!_codeRe.hasMatch(code)) {
      setState(() => _error = 'Format kode harus XXXX-XXXX-XXXX.');
      return;
    }
    setState(() => _error = null);
    final outcome = await tickets.redeem(code);
    if (!mounted || outcome == null) return;
    setState(() {
      _ticket = outcome.ticket;
      _error = outcome.isSuccess ? null : outcomeMessage(outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<TicketsController>().redeeming;
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
          Text('Draw: ${formatWib(ticket.drawAt!)}', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => context.go('/tickets'), child: const Text('Lihat My Tickets')),
        TextButton(onPressed: onAgain, child: const Text('Input kode lain')),
      ],
    );
  }
}
