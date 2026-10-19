import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaway_card.dart' show statusOfPhase;
import '../giveaways/giveaway_models.dart';
import '../../core/format.dart' show formatTicketNumber;
import 'admin_controller.dart';

/// Tindakan untuk satu giveaway: Generate Code, Daftar Kode, Draw manual.
class AdminGiveawayScreen extends StatefulWidget {
  const AdminGiveawayScreen({super.key, required this.giveawayId, this.initial});
  final String giveawayId;
  final Giveaway? initial;

  @override
  State<AdminGiveawayScreen> createState() => _AdminGiveawayScreenState();
}

class _AdminGiveawayScreenState extends State<AdminGiveawayScreen> {
  String? _drawError;
  String? _drawResult;

  Giveaway? _giveaway(AdminController c) => c.giveaways.where((g) => g.id == widget.giveawayId).firstOrNull ?? widget.initial;

  Future<void> _draw(Giveaway g) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jalankan draw sekarang?'),
        content: Text(
          'Pemenang "${g.title}" dipilih saat ini juga dan hasilnya dicatat di hash-chain. '
          'Tindakan ini tidak bisa dibatalkan dan tidak bisa diulang.',
        ),
        actions: [
          PrimaryButton(key: const Key('draw_cancel'), label: 'Batal', variant: ButtonVariant.text, expand: false, onPressed: () => Navigator.pop(ctx, false)),
          PrimaryButton(key: const Key('draw_confirm'), label: 'Jalankan draw', expand: false, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _drawError = null;
      _drawResult = null;
    });
    final r = await context.read<AdminController>().runDraw(g.id);
    if (r == null || !mounted) return;
    setState(() {
      if (r.isOk) {
        final o = r.data!;
        _drawResult = o.status == 'no_participants'
            ? 'Draw selesai, tetapi tidak ada peserta (0 tiket).'
            : 'Draw selesai. ${o.totalTickets} tiket ikut; pemenang: ${o.winningTickets.map(formatTicketNumber).join(', ')}.';
      } else {
        _drawError = r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AdminController>();
    final g = _giveaway(c);
    final theme = Theme.of(context);
    if (g == null) {
      return Scaffold(appBar: AppBar(title: const Text('Giveaway')), body: const EmptyState(icon: Icons.search_off, title: 'Giveaway tidak ditemukan', message: 'Kembali ke daftar Admin lalu pilih lagi.'));
    }
    final phase = g.phaseAt(DateTime.now());
    final drawn = phase == GiveawayPhase.drawn;
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Giveaway')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.s8),
                Wrap(spacing: Spacing.s8, runSpacing: Spacing.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusChip(statusOfPhase(phase)),
                  Text('${g.ticketCount} tiket', style: theme.textTheme.bodySmall),
                  Text('${g.winnerCount} pemenang', style: theme.textTheme.bodySmall),
                ]),
                if (g.drawAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.s8),
                    child: Text('Draw ${context.when(g.drawAt!)}', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sectionGap),
          const SectionHeader('Kode'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                key: const Key('open_generate_codes'),
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('Generate Code'),
                subtitle: Text(drawn ? 'Giveaway sudah diundi' : 'Buat kode redeem baru'),
                trailing: const Icon(Icons.chevron_right),
                enabled: !drawn,
                onTap: () => context.push('/admin/giveaway/${g.id}/generate', extra: g),
              ),
              const Divider(indent: Spacing.s16, endIndent: Spacing.s16),
              ListTile(
                key: const Key('open_codes_list'),
                leading: const Icon(Icons.list_alt),
                title: const Text('Daftar Kode'),
                subtitle: const Text('Status tiap kode'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/admin/giveaway/${g.id}/codes', extra: g),
              ),
            ]),
          ),
          const SizedBox(height: Spacing.sectionGap),
          const SectionHeader('Draw manual'),
          Text(
            'Menjalankan undian sekarang tanpa menunggu jadwal (mode demo server). Tidak bisa dibatalkan.',
            style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted),
          ),
          const SizedBox(height: Spacing.s12),
          if (_drawError != null) ...[InlineMessage(_drawError!), const SizedBox(height: Spacing.s12)],
          if (_drawResult != null) ...[InlineMessage(_drawResult!, tone: StatusTone.success), const SizedBox(height: Spacing.s12)],
          PrimaryButton(
            key: const Key('run_draw'),
            label: 'Jalankan draw',
            icon: Icons.casino_outlined,
            variant: ButtonVariant.secondary,
            loading: c.busy,
            onPressed: drawn ? null : () => _draw(g),
          ),
        ],
      ),
    );
  }
}
