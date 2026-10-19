import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/authed_api.dart';
import '../../core/display.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/time/zones.dart';
import '../../widgets/state_views.dart';
import '../tickets/tickets_controller.dart';
import 'giveaway_card.dart';
import 'giveaway_models.dart';
import 'giveaways_controller.dart';

/// S-GW-DETAIL (bagian ini): info, hadiah, jadwal draw (WIB), jumlah tiket saya, tombol Input Code.
/// Data dari GET /giveaways/:id; offline -> dari cache. Countdown, 4 zona, kurs, hasil/verifikasi menyusul.
class GiveawayDetailScreen extends StatefulWidget {
  const GiveawayDetailScreen({super.key, required this.giveawayId, this.initial});
  final String giveawayId;
  final Giveaway? initial;
  @override
  State<GiveawayDetailScreen> createState() => _GiveawayDetailScreenState();
}

class _GiveawayDetailScreenState extends State<GiveawayDetailScreen> {
  Giveaway? _g;
  bool _loading = false, _offline = false, _notFound = false;
  DateTime? _cachedAt;
  String? _error;
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _g = widget.initial; // tampil langsung; dimuat ulang dari server di latar
    final tickets = context.read<TicketsController>();
    if (tickets.state == LoadState.idle) Future.microtask(tickets.load);
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = _g == null;
      _error = null;
    });
    final r = await context.read<GiveawaysController>().fetchOne(widget.giveawayId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notFound = r.notFound;
      _error = r.error;
      _offline = r.offline;
      _cachedAt = r.cachedAt;
      if (r.giveaway != null) _g = r.giveaway;
    });
    if (_g != null && !_logged) {
      _logged = true;
      _logView(_g!);
    }
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
      body: g != null
          ? Column(children: [
              if (_offline) OfflineBanner(cachedAt: _cachedAt),
              Expanded(child: _Body(giveaway: g)),
            ])
          : _loading
              ? const LoadingView()
              : _notFound
                  ? const EmptyView(icon: Icons.search_off, message: 'Giveaway tidak ditemukan.')
                  : ErrorRetryView(message: _error ?? 'Gagal memuat giveaway.', onRetry: _fetch),
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

/// Jadwal draw di keempat zona; zona pilihan pengguna ditandai.
class _DrawZones extends StatelessWidget {
  const _DrawZones({required this.drawAt});
  final DateTime drawAt;

  @override
  Widget build(BuildContext context) {
    final chosen = context.watch<SettingsController>().zone;
    final theme = Theme.of(context);
    return Card(
      key: const Key('draw_zones'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jadwal draw di 4 zona', style: theme.textTheme.titleSmall),
            for (final z in AppZone.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 72, child: Text(z.title, style: TextStyle(fontWeight: z == chosen ? FontWeight.bold : null))),
                  Expanded(
                    child: Text(
                      formatInZone(drawAt, z),
                      key: Key('zone_${z.name}'),
                      style: TextStyle(fontWeight: z == chosen ? FontWeight.bold : null),
                    ),
                  ),
                ]),
              ),
          ],
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
        row('Nilai', context.money(g.prizeValueUsd)),
        const Padding(padding: EdgeInsets.only(left: 120), child: RateNote()),
        row('Pemenang', '${g.winnerCount}'),
        row('Mulai', g.startAt == null ? '-' : context.when(g.startAt!)),
        row('Berakhir', g.endAt == null ? '-' : context.when(g.endAt!)),
        row('Draw', g.drawAt == null ? '-' : context.when(g.drawAt!)),
        if (g.drawAt != null && g.phaseAt(DateTime.now()) != GiveawayPhase.drawn)
          Padding(
            padding: const EdgeInsets.only(left: 120, top: 2, bottom: 4),
            child: Countdown(target: g.drawAt!, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
        if (g.drawAt != null) _DrawZones(drawAt: g.drawAt!),
        if (g.address != null && g.address!.isNotEmpty) row('Lokasi', g.address!),
        const Divider(height: 32),
        row('Tiket terbit', '${g.ticketCount}'),
        row('Tiket saya', '$mine'),
      ],
    );
  }
}
