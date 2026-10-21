import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/activity.dart';
import '../../core/api/authed_api.dart';
import '../../core/display.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/time/zones.dart';
import '../../core/widgets/widgets.dart';
import '../tickets/tickets_controller.dart';
import 'giveaway_card.dart';
import 'giveaway_models.dart';
import 'giveaways_controller.dart';

/// S-GW-DETAIL: banner, judul + status, nilai hadiah (mata uang pilihan), hitung mundur, info, jadwal draw di zona
/// pilihan (+ tiga zona lain), cara ikut, tombol Input Code menempel di bawah.
/// Data dari GET /giveaways/:id; offline -> dari cache. Hasil/verifikasi menyusul (M6).
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

  /// Tembak-dan-lupa: gagal mencatat aktivitas tidak boleh mengganggu layar (lihat ActivityLogger).
  void _logView(Giveaway g) => ActivityLogger(context.read<AuthedApi>()).viewGiveaway(giveawayId: g.id, category: g.category);

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Giveaway')),
      body: g != null
          ? Column(children: [
              if (_offline) OfflineBanner(cachedAt: _cachedAt),
              Expanded(child: _Body(giveaway: g)),
            ])
          : _loading
              ? const SkeletonLoader(count: 1)
              : _notFound
                  ? const EmptyState(icon: Icons.search_off, title: 'Giveaway tidak ditemukan', message: 'Giveaway ini mungkin sudah dihapus.')
                  : ErrorState(message: _error ?? 'Gagal memuat giveaway.', onRetry: _fetch),
      // Satu aksi utama, selalu terlihat.
      bottomNavigationBar: g == null
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.outlineSoft)),
                boxShadow: AppShadows.raised(c),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.s16),
                  child: g.phaseAt(DateTime.now()) == GiveawayPhase.drawn
                      // Sudah diundi: kode tidak bisa dipakai lagi; tawarkan hasil dan verifikasi.
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          PrimaryButton(key: const Key('open_result'), label: 'Lihat hasil', icon: Icons.emoji_events_outlined, onPressed: () => context.push('/giveaway/${g.id}/result')),
                          const SizedBox(height: Spacing.s8),
                          PrimaryButton(key: const Key('open_verify_detail'), label: 'Cek Keaslian', icon: Icons.verified_outlined, variant: ButtonVariant.secondary, onPressed: () => context.push('/giveaway/${g.id}/verify')),
                        ])
                      : PrimaryButton(label: 'Input Code', icon: Icons.qr_code_2, onPressed: () => context.push('/code')),
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
    final c = context.colors;
    final mine = context.watch<TicketsController>().countFor(g.id);
    final phase = g.phaseAt(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
      children: [
        CategoryBanner(category: g.category, height: 180),
        const SizedBox(height: Spacing.s16),
        Text(g.title, style: theme.textTheme.titleLarge),
        if (g.organizer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.s4),
            child: Text('oleh ${g.organizer}', style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
          ),
        const SizedBox(height: Spacing.s12),
        Wrap(spacing: Spacing.s8, runSpacing: Spacing.s8, children: [
          CategoryTag(g.category),
          StatusChip(statusOfPhase(phase)),
        ]),
        const SizedBox(height: Spacing.s16),
        _PrizeBlock(giveaway: g),
        if (g.drawAt != null && phase != GiveawayPhase.drawn) ...[
          const SizedBox(height: Spacing.s16),
          CountdownCard(target: g.drawAt!),
        ],
        if (g.description.isNotEmpty) ...[
          const SizedBox(height: Spacing.s16),
          Text(g.description, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Spacing.sectionGap),
        const SectionHeader('Informasi'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s8),
          child: Column(children: [
            if (g.organizer.isNotEmpty) _InfoRow('Penyelenggara', g.organizer),
            _InfoRow('Pemenang', '${g.winnerCount}'),
            _InfoRow('Tiket terbit', '${g.ticketCount}'),
            _InfoRow('Tiket saya', '$mine'),
            _InfoRow('Mulai', g.startAt == null ? '-' : context.when(g.startAt!)),
            _InfoRow('Berakhir', g.endAt == null ? '-' : context.when(g.endAt!)),
            _InfoRow('Draw', g.drawAt == null ? '-' : context.when(g.drawAt!)),
            if (g.address != null && g.address!.isNotEmpty) _InfoRow('Lokasi', g.address!),
          ]),
        ),
        if (g.drawAt != null) _OtherZones(drawAt: g.drawAt!),
        const SizedBox(height: Spacing.sectionGap),
        const SectionHeader('Cara ikut'),
        const _HowToJoin(),
      ],
    );
  }
}

/// Nilai hadiah besar (mata uang pilihan) + keterangan kurs.
class _PrizeBlock extends StatelessWidget {
  const _PrizeBlock({required this.giveaway});
  final Giveaway giveaway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
              child: SizedBox(width: 48, height: 48, child: Icon(Icons.card_giftcard, color: c.onAccent, size: 28)),
            ),
          ),
          const SizedBox(width: Spacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nilai hadiah', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                Text(
                  context.money(giveaway.prizeValueUsd),
                  key: const Key('prize_value'),
                  style: AppTypography.tabular(theme.textTheme.displaySmall!.copyWith(color: c.accentText)),
                ),
                if (giveaway.prizeName.isNotEmpty) Text(giveaway.prizeName, style: theme.textTheme.bodyMedium),
                const SizedBox(height: Spacing.s4),
                const RateNote(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted))),
          const SizedBox(width: Spacing.s12),
          Expanded(flex: 6, child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Jadwal draw di tiga zona selain zona pilihan; dibuka dengan mengetuk.
class _OtherZones extends StatelessWidget {
  const _OtherZones({required this.drawAt});
  final DateTime drawAt;

  @override
  Widget build(BuildContext context) {
    final chosen = context.watch<SettingsController>().zone;
    final others = [for (final z in AppZone.values) if (z != chosen) z];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.cardGap),
      child: SurfaceCard(
        key: const Key('draw_zones'),
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: Spacing.s16),
          childrenPadding: const EdgeInsets.fromLTRB(Spacing.s16, 0, Spacing.s16, Spacing.s12),
          title: Text('Jadwal draw di zona lain', style: theme.textTheme.titleSmall),
          subtitle: Text(others.map((z) => z.title).join(', '), style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final z in others)
              KeyedSubtree(key: Key('zone_${z.name}'), child: _InfoRow(z.title, formatInZone(drawAt, z))),
          ],
        ),
      ),
    );
  }
}

class _HowToJoin extends StatelessWidget {
  const _HowToJoin();

  static const _steps = [
    'Dapatkan kode dari penyelenggara giveaway.',
    'Ketuk Input Code, lalu masukkan kode dengan format XXXX-XXXX-XXXX.',
    'Tiketmu terbit. Tunggu draw pada jadwal di atas.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return SurfaceCard(
      child: Column(
        children: [
          for (final (i, s) in _steps.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : Spacing.s12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(child: Text('${i + 1}', style: theme.textTheme.labelMedium?.copyWith(color: c.onPrimaryContainer))),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.s12),
                  Expanded(child: Text(s, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
