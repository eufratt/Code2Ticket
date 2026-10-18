import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../widgets/state_views.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'ticket_models.dart';
import 'tickets_controller.dart';

String ticketResultLabel(TicketResult r) => switch (r) {
      TicketResult.eligible => 'Eligible',
      TicketResult.waitingForDraw => 'Menunggu draw',
      TicketResult.winner => 'Menang',
      TicketResult.notSelected => 'Tidak terpilih',
    };

/// S-TIX: tiket dikelompokkan per giveaway. Detail tiket + shake to reveal menyusul (M6).
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});
  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  @override
  void initState() {
    super.initState();
    // Selalu segarkan saat tab dibuka (hasil draw bisa berubah di server).
    Future.microtask(context.read<TicketsController>().load);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TicketsController>();
    final groups = c.grouped.entries.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('My Tickets')),
      body: switch (c.state) {
        LoadState.idle || LoadState.loading when c.items.isEmpty => const LoadingView(),
        LoadState.error when c.items.isEmpty =>
          ErrorRetryView(message: c.error ?? 'Gagal memuat.', onRetry: c.load),
        _ => RefreshIndicator(
            onRefresh: c.load,
            child: groups.isEmpty
                ? ListView(children: const [
                    SizedBox(
                      height: 360,
                      child: EmptyView(
                        icon: Icons.confirmation_number_outlined,
                        message: 'Belum ada tiket.\nMasukkan kode lewat tombol di tengah.',
                      ),
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.only(top: 8, bottom: 140),
                    children: [
                      for (final g in groups) _Group(giveawayId: g.key, tickets: g.value),
                    ],
                  ),
          ),
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.giveawayId, required this.tickets});
  final String giveawayId;
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final first = tickets.first;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(first.giveawayTitle, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(
              '${first.prizeName}${first.drawAt == null ? '' : ' · Draw ${formatWib(first.drawAt!)}'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/giveaway/$giveawayId'),
          ),
          for (final t in tickets)
            ListTile(
              dense: true,
              leading: const Icon(Icons.confirmation_number_outlined),
              title: Text(formatTicketNumber(t.ticketNumber)),
              subtitle: Text('Kode ${t.codeMasked}'),
              trailing: Chip(
                label: Text(ticketResultLabel(t.result)),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
