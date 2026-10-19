import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'ticket_models.dart';
import 'tickets_controller.dart';

String ticketResultLabel(TicketResult r) => statusOfResult(r).label;

/// Status tiket untuk chip (tabel DESIGN.md bagian 4).
AppStatus statusOfResult(TicketResult r) => switch (r) {
      TicketResult.eligible => AppStatus.ticketEligible,
      TicketResult.waitingForDraw => AppStatus.ticketWaiting,
      TicketResult.winner => AppStatus.ticketWon,
      TicketResult.notSelected => AppStatus.ticketNotSelected,
    };

/// Filter status di atas daftar tiket.
enum TicketFilter {
  all('Semua'),
  pending('Menunggu'),
  won('Menang'),
  lost('Tidak terpilih');

  const TicketFilter(this.label);
  final String label;

  bool accepts(TicketResult r) => switch (this) {
        all => true,
        pending => r == TicketResult.eligible || r == TicketResult.waitingForDraw,
        won => r == TicketResult.winner,
        lost => r == TicketResult.notSelected,
      };
}

/// S-TIX: tiket dikelompokkan per giveaway, tiap tiket berupa TicketCard. Detail tiket + shake to reveal menyusul (M6).
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});
  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  TicketFilter _filter = TicketFilter.all;

  @override
  void initState() {
    super.initState();
    // Selalu segarkan saat tab dibuka (hasil draw bisa berubah di server).
    Future.microtask(context.read<TicketsController>().load);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<TicketsController>();
    final groups = <MapEntry<String, List<Ticket>>>[
      for (final e in c.grouped.entries)
        if (e.value.any((t) => _filter.accepts(t.result))) MapEntry(e.key, [for (final t in e.value) if (_filter.accepts(t.result)) t]),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('My Tickets')),
      body: switch (c.state) {
        LoadState.idle || LoadState.loading when c.items.isEmpty => const SkeletonLoader(shape: SkeletonShape.ticket, count: 3),
        LoadState.error when c.items.isEmpty => ErrorState(message: c.error ?? 'Gagal memuat.', onRetry: c.load),
        _ => Column(children: [
            if (c.offline) OfflineBanner(cachedAt: c.cachedAt),
            if (c.items.isNotEmpty)
              _FilterBar(selected: _filter, onSelected: (f) => setState(() => _filter = f)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: c.items.isEmpty
                    ? ListView(children: [
                        SizedBox(
                          height: 420,
                          child: EmptyState(
                            icon: Icons.confirmation_number_outlined,
                            title: 'Belum ada tiket',
                            message: 'Masukkan kode lewat tombol di tengah untuk mendapat tiket pertamamu.',
                            actionLabel: 'Masukkan kode',
                            onAction: () => context.push('/code'),
                          ),
                        ),
                      ])
                    : groups.isEmpty
                        ? ListView(children: [
                            SizedBox(
                              height: 360,
                              child: EmptyState(
                                icon: Icons.filter_alt_off_outlined,
                                title: 'Tidak ada tiket "${_filter.label}"',
                                message: 'Pilih status lain untuk melihat tiketmu.',
                                actionLabel: 'Tampilkan semua',
                                onAction: () => setState(() => _filter = TicketFilter.all),
                              ),
                            ),
                          ])
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(Spacing.screen, 0, Spacing.screen, Spacing.listBottom),
                            children: [
                              for (final g in groups) _Group(giveawayId: g.key, tickets: g.value),
                            ],
                          ),
              ),
            ),
          ]),
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});
  final TicketFilter selected;
  final ValueChanged<TicketFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMinTap + Spacing.s8,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.screen, vertical: Spacing.s4),
        children: [
          for (final f in TicketFilter.values) ...[
            if (f != TicketFilter.all) const SizedBox(width: Spacing.s8),
            ChoiceChip(
              key: Key('ticket_filter_${f.name}'),
              label: Text(f.label),
              selected: f == selected,
              onSelected: (_) => onSelected(f),
            ),
          ],
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          first.giveawayTitle,
          padding: const EdgeInsets.only(top: Spacing.s8),
          actionLabel: 'Lihat giveaway',
          onAction: () => context.push('/giveaway/$giveawayId'),
        ),
        for (final t in tickets)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.cardGap),
            child: TicketCard(
              title: t.giveawayTitle,
              category: t.category,
              ticketNumber: formatTicketNumber(t.ticketNumber),
              status: statusOfResult(t.result),
              prizeText: t.prizeName,
              subtitle: [
                if (t.drawAt != null) 'Draw ${context.when(t.drawAt!)}',
                if (t.codeMasked.isNotEmpty) 'Kode ${t.codeMasked}',
              ].join('\n'),
              onTap: () => context.push('/giveaway/$giveawayId'),
            ),
          ),
      ],
    );
  }
}
