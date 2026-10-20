import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'game_controller.dart';

/// Papan peringkat game: skor total 7 hari terakhir (GET /game/leaderboard). Posisi pengguna disorot dengan chip "Kamu"
/// + ikon, bukan hanya warna. Hanya data yang dikirim server (peringkat, username, level, skor).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(context.read<GameController>().loadLeaderboard);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final me = context.watch<AuthController?>()?.user?.username;
    return Scaffold(
      appBar: AppBar(title: const Text('Papan Peringkat')),
      body: switch (c.state) {
        LoadState.idle || LoadState.loading when c.entries.isEmpty => const SkeletonLoader(shape: SkeletonShape.row, count: 6),
        LoadState.error when c.entries.isEmpty => ErrorState(message: c.error ?? 'Gagal memuat.', onRetry: c.loadLeaderboard),
        _ => RefreshIndicator(
            onRefresh: c.loadLeaderboard,
            child: c.entries.isEmpty
                ? ListView(children: const [
                    SizedBox(
                      height: 420,
                      child: EmptyState(icon: Icons.leaderboard_outlined, title: 'Belum ada skor', message: 'Mainkan Buru Kode untuk jadi yang pertama di papan peringkat minggu ini.'),
                    ),
                  ])
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
                    children: [
                      Text('Skor total 7 hari terakhir', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
                      const SizedBox(height: Spacing.s12),
                      if (me != null && !c.entries.any((e) => e.username == me))
                        const Padding(
                          padding: EdgeInsets.only(bottom: Spacing.s12),
                          child: InlineMessage('Kamu belum masuk daftar minggu ini. Mainkan Buru Kode untuk naik ke papan peringkat.', tone: StatusTone.info),
                        ),
                      for (final e in c.entries)
                        Padding(padding: const EdgeInsets.only(bottom: Spacing.s8), child: _Row(entry: e, isMe: e.username == me)),
                    ],
                  ),
          ),
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.isMe});
  final LeaderboardEntry entry;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final top = entry.rank <= 3;
    return SurfaceCard(
      key: Key('rank_${entry.rank}'),
      color: isMe ? c.primaryContainer : null,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s12),
      semanticLabel: '${isMe ? 'Kamu, ' : ''}peringkat ${entry.rank}, ${entry.username}, level ${entry.level}, ${entry.totalScore} poin',
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: top
                ? Icon(Icons.emoji_events, color: c.accent, size: 28)
                : Text('${entry.rank}', style: theme.textTheme.titleMedium?.copyWith(color: c.muted), textAlign: TextAlign.center),
          ),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (top) Padding(padding: const EdgeInsets.only(right: Spacing.s8), child: Text('#${entry.rank}', style: theme.textTheme.titleMedium)),
                  Flexible(child: Text(entry.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium)),
                ]),
                Wrap(spacing: Spacing.s8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Level ${entry.level}', style: theme.textTheme.bodySmall?.copyWith(color: isMe ? c.onPrimaryContainer : c.muted)),
                  if (isMe) const StatusChip.custom(label: 'Kamu', tone: StatusTone.info, icon: Icons.person),
                ]),
              ],
            ),
          ),
          const SizedBox(width: Spacing.s8),
          Text('${entry.totalScore}', key: Key('rank_score_${entry.rank}'), style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}
