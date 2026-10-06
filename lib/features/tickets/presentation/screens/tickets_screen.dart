import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../controllers/tickets_controller.dart';
import '../controllers/tickets_state.dart';
import '../widgets/giveaway_ticket_group_card.dart';

class TicketsScreen extends ConsumerWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ticketsControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tiket Saya'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Muat Ulang',
              onPressed: () {
                ref.read(ticketsControllerProvider.notifier).fetchTickets();
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.confirmation_number_rounded, size: 20),
                text: 'Tiket Aktif',
              ),
              Tab(
                icon: Icon(Icons.history_rounded, size: 20),
                text: 'Riwayat',
              ),
            ],
          ),
        ),
        body: switch (state) {
          TicketsLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          TicketsError(:final message) => _buildErrorView(
              context,
              ref,
              message,
              isDark,
            ),
          TicketsEmpty() => _buildEmptyGlobalView(context, isDark),
          TicketsLoaded(:final activeGroups, :final historyGroups) => TabBarView(
              children: [
                _buildActiveTab(context, ref, activeGroups, isDark),
                _buildHistoryTab(context, ref, historyGroups, isDark),
              ],
            ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _buildActiveTab(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> activeGroups,
    bool isDark,
  ) {
    if (activeGroups.isEmpty) {
      return _buildEmptyTabView(
        context,
        icon: Icons.confirmation_number_outlined,
        title: 'Tidak Ada Tiket Aktif',
        description:
            'Anda belum memiliki tiket undian yang sedang menunggu draw.',
        actionText: 'Tukarkan Kode Baru',
        onAction: () => context.push('/input-code'),
        isDark: isDark,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(ticketsControllerProvider.notifier).fetchTickets(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: activeGroups.length,
        itemBuilder: (context, index) {
          final group = activeGroups[index];
          return GiveawayTicketGroupCard(group: group);
        },
      ),
    );
  }

  Widget _buildHistoryTab(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> historyGroups,
    bool isDark,
  ) {
    if (historyGroups.isEmpty) {
      return _buildEmptyTabView(
        context,
        icon: Icons.history_rounded,
        title: 'Belum Ada Riwayat Undian',
        description:
            'Tiket dari undian yang telah selesai atau diumumkan pemenangnya akan tercatat di sini.',
        isDark: isDark,
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(ticketsControllerProvider.notifier).fetchTickets(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: historyGroups.length,
        itemBuilder: (context, index) {
          final group = historyGroups[index];
          return GiveawayTicketGroupCard(group: group);
        },
      ),
    );
  }

  Widget _buildEmptyGlobalView(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.ticketGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.confirmation_number_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum Memiliki Tiket',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan kode promosi dari campaign mitra untuk mendapatkan tiket undian digital pertamamu!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Klaim Kode Partisipasi',
              icon: Icons.add_rounded,
              onPressed: () => context.push('/input-code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTabView(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    String? actionText,
    VoidCallback? onAction,
    required bool isDark,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 56,
              color: AppColors.primaryPurple.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 20),
              AppButton(
                text: actionText,
                icon: Icons.qr_code_rounded,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    WidgetRef ref,
    String message,
    bool isDark,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: AppColors.errorRed,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gagal Memuat Tiket',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              text: 'Coba Lagi',
              icon: Icons.refresh_rounded,
              onPressed: () {
                ref.read(ticketsControllerProvider.notifier).fetchTickets();
              },
            ),
          ],
        ),
      ),
    );
  }
}
