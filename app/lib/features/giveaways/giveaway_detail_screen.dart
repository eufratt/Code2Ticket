import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/format.dart';
import '../../widgets/state_views.dart';
import '../tickets/tickets_controller.dart';
import 'giveaway_card.dart';
import 'giveaway_models.dart';
import 'giveaways_controller.dart';

/// S-GW-DETAIL (bagian M3): info, hadiah, jadwal draw (WIB), jumlah tiket saya, tombol Input Code.
/// Countdown, 4 zona, kurs, dan hasil/verifikasi menyusul.
class GiveawayDetailScreen extends StatefulWidget {
  const GiveawayDetailScreen({super.key, required this.giveawayId, this.initial});
  final String giveawayId;
  final Giveaway? initial;
  @override
  State<GiveawayDetailScreen> createState() => _GiveawayDetailScreenState();
}

class _GiveawayDetailScreenState extends State<GiveawayDetailScreen> {
  Giveaway? _g;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _g = widget.initial;
    final tickets = context.read<TicketsController>();
    if (tickets.state == LoadState.idle) Future.microtask(tickets.load);
    if (_g == null) {
      _find();
    } else {
      _logView(_g!);
    }
  }

  Future<void> _find() async {
    setState(() => _loading = true);
    final g = await context.read<GiveawaysController>().find(widget.giveawayId);
    if (!mounted) return;
    setState(() {
      _g = g;
      _loading = false;
    });
    if (g != null) _logView(g);
  }

  /// Gagal mencatat aktivitas tidak boleh mengganggu layar.
  Future<void> _logView(Giveaway g) async {
    try {
      await context.read<AuthedApi>().post('/activity',
          body: {'type': 'view_giveaway', 'giveaway_id': g.id, 'category': g.category});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Giveaway')),
      body: g == null
          ? (_loading
              ? const LoadingView()
              : ErrorRetryView(message: 'Giveaway tidak ditemukan.', onRetry: _find))
          : _Body(giveaway: g),
      bottomNavigationBar: g == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => context.push('/code'),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Input Code'),
                ),
              ),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.giveaway});
  final Giveaway giveaway;

  @override
  Widget build(BuildContext context) {
    final g = giveaway;
    final theme = Theme.of(context);
    final mine = context.watch<TicketsController>().countFor(g.id);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(k, style: theme.textTheme.bodySmall)),
              Expanded(child: Text(v)),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(g.title, style: theme.textTheme.headlineSmall),
        if (g.organizer.isNotEmpty) Text('oleh ${g.organizer}'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          Chip(label: Text(g.category)),
          Chip(label: Text(phaseLabel(g.phaseAt(DateTime.now())))),
        ]),
        if (g.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(g.description),
        ],
        const Divider(height: 32),
        row('Hadiah', g.prizeName),
        row('Nilai', formatUsd(g.prizeValueUsd)),
        row('Pemenang', '${g.winnerCount}'),
        row('Mulai', g.startAt == null ? '-' : formatWib(g.startAt!)),
        row('Berakhir', g.endAt == null ? '-' : formatWib(g.endAt!)),
        row('Draw', g.drawAt == null ? '-' : formatWib(g.drawAt!)),
        if (g.address != null && g.address!.isNotEmpty) row('Lokasi', g.address!),
        const Divider(height: 32),
        row('Tiket terbit', '${g.ticketCount}'),
        row('Tiket saya', '$mine'),
      ],
    );
  }
}
