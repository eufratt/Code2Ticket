import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/db/rate_cache.dart' show SettingsStore;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import 'chain_puzzle.dart';

ChainProgressStore chainStoreOf(BuildContext context) =>
    ChainProgressStore(context.read<SettingsStore?>(), context.read<AuthController?>()?.user?.id ?? '');

/// Pilih level Rakit Rantai; progres (selesai + langkah terbaik) dibaca dari app_settings pengguna.
class ChainLevelsScreen extends StatefulWidget {
  const ChainLevelsScreen({super.key});
  @override
  State<ChainLevelsScreen> createState() => _ChainLevelsScreenState();
}

class _ChainLevelsScreenState extends State<ChainLevelsScreen> {
  ChainProgress _progress = const ChainProgress();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final p = await chainStoreOf(context).load();
    if (mounted) setState(() => _progress = p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Rakit Rantai')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          SurfaceCard(
            color: c.primaryContainer,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(child: Icon(Icons.link, size: 40, color: c.onPrimaryContainer)),
              const SizedBox(width: Spacing.s12),
              Expanded(
                child: Text(
                  'Tiap block menyimpan hash block sebelumnya. Susun block sampai rantainya bersambung, atau periksa rantai dan temukan sambungan yang putus. '
                  'Ini hanya latihan: tanpa XP, lencana, atau skor.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer),
                ),
              ),
            ]),
          ),
          const SectionHeader('Pilih level', padding: EdgeInsets.only(top: Spacing.s16)),
          for (final l in ChainLevel.all)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.cardGap),
              child: SurfaceCard(
                key: Key('chain_level_${l.number}'),
                onTap: () async {
                  await context.push('/game/chain/play', extra: l.number);
                  _reload();
                },
                semanticLabel:
                    '${l.title}, mode ${l.modeLabel}, ${l.blockCount} block, ${_progress.isDone(l.number) ? 'selesai, langkah terbaik ${_progress.best[l.number]}' : 'belum selesai'}',
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${l.title} · ${l.modeLabel}', style: theme.textTheme.titleMedium),
                      const SizedBox(height: Spacing.s4),
                      Text('${l.blockCount} block', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                      const SizedBox(height: Spacing.s8),
                      _progress.isDone(l.number)
                          ? StatusChip.custom(label: 'Selesai · terbaik ${_progress.best[l.number]} langkah', tone: StatusTone.success, icon: Icons.check_circle_outline)
                          : const StatusChip.custom(label: 'Belum selesai', tone: StatusTone.neutral, icon: Icons.radio_button_unchecked),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: c.muted),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
