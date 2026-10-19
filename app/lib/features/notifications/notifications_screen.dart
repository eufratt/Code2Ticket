import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'notification_models.dart';
import 'notifications_controller.dart';

/// S-NOTIF: daftar notifikasi. Belum dibaca = chip "Belum dibaca" + judul tebal + ikon berwarna (bukan hanya warna).
/// Ketuk -> tandai dibaca; bila ada giveaway_id, buka Detail Giveaway.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(context.read<NotificationsController>().load);
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _markAll() async {
    final err = await context.read<NotificationsController>().markAllRead();
    if (err != null && mounted) _toast(err);
  }

  Future<void> _open(AppNotification n) async {
    final c = context.read<NotificationsController>();
    final router = GoRouter.of(context);
    final err = await c.markRead(n.id);
    if (err != null && mounted) _toast(err);
    if (n.giveawayId != null) router.push('/giveaway/${n.giveawayId}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NotificationsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi')),
      body: switch (c.state) {
        LoadState.idle || LoadState.loading when c.items.isEmpty => const SkeletonLoader(shape: SkeletonShape.ticket, count: 4),
        LoadState.error when c.items.isEmpty => ErrorState(message: c.error ?? 'Gagal memuat.', onRetry: c.load),
        _ => Column(children: [
            if (c.unreadCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.s8, 0),
                // Wrap: di font besar tombol turun ke baris berikutnya, tidak meluap.
                child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${c.unreadCount} belum dibaca', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
                  TextButton(key: const Key('mark_all_read'), onPressed: c.markingAll ? null : _markAll, child: const Text('Tandai semua dibaca')),
                ]),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.load,
                child: c.items.isEmpty
                    ? ListView(children: const [
                        SizedBox(
                          height: 420,
                          child: EmptyState(
                            icon: Icons.notifications_none,
                            title: 'Belum ada notifikasi',
                            message: 'Hasil undian dan kabar tiketmu akan muncul di sini.',
                          ),
                        ),
                      ])
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s8, Spacing.screen, Spacing.s24),
                        itemCount: c.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: Spacing.cardGap),
                        itemBuilder: (_, i) => _NotificationTile(n: c.items[i], onTap: () => _open(c.items[i])),
                      ),
              ),
            ),
          ]),
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final kind = NotificationKind.of(n.type);
    return SurfaceCard(
      key: Key('notification_${n.id}'),
      onTap: onTap,
      semanticLabel: '${n.isRead ? '' : 'Belum dibaca. '}${kind.label}. ${n.title}. ${n.body}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: n.isRead ? c.surfaceVariant : c.primaryContainer, shape: BoxShape.circle),
            child: SizedBox(width: 44, height: 44, child: Icon(kind.icon, color: n.isRead ? c.muted : c.onPrimaryContainer)),
          ),
          const SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: Spacing.s8, runSpacing: Spacing.s4, children: [
                  StatusChip.custom(label: kind.label, tone: kind.tone, icon: kind.icon),
                  if (!n.isRead) const StatusChip.custom(label: 'Belum dibaca', tone: StatusTone.info, icon: Icons.fiber_manual_record),
                ]),
                const SizedBox(height: Spacing.s8),
                Text(n.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                if (n.body.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: Spacing.s4), child: Text(n.body, style: theme.textTheme.bodyMedium)),
                if (n.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.s4),
                    child: Text(context.when(n.createdAt!), style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                  ),
              ],
            ),
          ),
          if (n.giveawayId != null) Icon(Icons.chevron_right, color: c.muted),
        ],
      ),
    );
  }
}
