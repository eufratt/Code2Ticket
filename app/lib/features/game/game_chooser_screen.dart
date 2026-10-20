import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'chain_levels_screen.dart' show chainStoreOf;
import 'chain_puzzle.dart';
import 'code_hunt_record.dart';
import 'maze.dart';

/// "Pilih game": pintu ke Code Hunt dan Rakit Rantai (Home > Menu fitur > Game). Layar penuh, tanpa tab/FAB.
/// Rekor Code Hunt dan progres Rakit Rantai dibaca dari app_settings (tanpa jaringan).
class GameChooserScreen extends StatefulWidget {
  const GameChooserScreen({super.key});
  @override
  State<GameChooserScreen> createState() => _GameChooserScreenState();
}

class _GameChooserScreenState extends State<GameChooserScreen> {
  CodeHuntRecord _record = const CodeHuntRecord();
  ChainProgress _chain = const ChainProgress();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final hunt = CodeHuntRecordStore.of(context), chain = chainStoreOf(context);
    final r = await hunt.load();
    final p = await chain.load();
    if (mounted) {
      setState(() {
        _record = r;
        _chain = p;
      });
    }
  }

  Future<void> _open(String route) async {
    await context.push(route);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final done = _chain.best.keys.where((l) => l >= 1 && l <= ChainLevel.all.length).length;
    final total = ChainLevel.all.length;
    final recordText = _record.isEmpty ? 'Belum ada rekor' : 'Rekor ${_record.bestScore} · level ${MazeLevel.all[_record.bestLevel.clamp(0, MazeLevel.all.length - 1)].name} selesai';
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih game')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          _GameCard(
            key: const Key('choose_codehunt'),
            icon: Icons.explore_outlined,
            title: 'Code Hunt',
            description: 'Miringkan ponsel, kumpulkan segmen kode, dan antar chip kode ke Mesin Undian sebelum waktu habis.',
            chips: [
              const StatusChip.custom(label: 'Sensor: gyroscope + accelerometer', tone: StatusTone.info, icon: Icons.screen_rotation),
              StatusChip.custom(label: recordText, tone: _record.isEmpty ? StatusTone.neutral : StatusTone.success, icon: Icons.emoji_events_outlined),
            ],
            semantic: 'Code Hunt. Miringkan ponsel, kumpulkan segmen kode, dan antar chip kode ke Mesin Undian. Sensor gyroscope dan accelerometer. $recordText.',
            onTap: () => _open('/game/codehunt'),
          ),
          const SizedBox(height: Spacing.s16),
          _GameCard(
            key: const Key('choose_chain'),
            icon: Icons.link,
            title: 'Rakit Rantai',
            description: 'Susun dan periksa block hash-chain seperti pada verifikasi undian asli.',
            chips: [
              const StatusChip.custom(label: 'Puzzle hash-chain', tone: StatusTone.info, icon: Icons.extension_outlined),
              StatusChip.custom(label: '$done/$total level selesai', tone: done == 0 ? StatusTone.neutral : StatusTone.success, icon: Icons.check_circle_outline),
            ],
            semantic: 'Rakit Rantai. Susun dan periksa block hash-chain seperti pada verifikasi undian asli. Puzzle hash-chain. $done dari $total level selesai.',
            onTap: () => _open('/game/chain'),
          ),
          const SizedBox(height: Spacing.s8),
          Center(
            child: PrimaryButton(
              key: const Key('chooser_leaderboard'),
              label: 'Papan peringkat Code Hunt',
              icon: Icons.leaderboard_outlined,
              variant: ButtonVariant.text,
              expand: false,
              onPressed: () => context.push('/leaderboard'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({super.key, required this.icon, required this.title, required this.description, required this.chips, required this.semantic, required this.onTap});
  final IconData icon;
  final String title, description, semantic;
  final List<Widget> chips;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return SurfaceCard(
      raised: true,
      onTap: onTap,
      semanticLabel: semantic,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
              child: SizedBox(width: 48, height: 48, child: Icon(icon, color: c.onPrimaryContainer)),
            ),
          ),
          const SizedBox(width: Spacing.s12),
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          Icon(Icons.chevron_right, color: c.muted),
        ]),
        const SizedBox(height: Spacing.s12),
        Text(description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Spacing.s12),
        Wrap(spacing: Spacing.s8, runSpacing: Spacing.s8, children: chips),
      ]),
    );
  }
}
