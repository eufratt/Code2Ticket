import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../auth/presentation/controllers/auth_state.dart';
import '../controllers/home_controller.dart';
import '../controllers/home_state.dart';
import '../widgets/home_ai_assistant_banner.dart';
import '../widgets/home_countdown_card.dart';
import '../widgets/home_giveaway_horizontal_list.dart';
import '../widgets/home_ticket_summary_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeState = ref.watch(homeControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final username = switch (authState) {
      Authenticated(:final user) => user.username,
      _ => 'Pengguna',
    };

    String todayFormatted = 'Hari ini';
    try {
      todayFormatted =
          DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(DateTime.now());
    } catch (_) {
      todayFormatted = DateFormat('dd MMM yyyy').format(DateTime.now());
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Halo, $username! 👋',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              todayFormatted,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Klaim Kode',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/input-code'),
          ),
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () => context.go('/profile'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(homeControllerProvider.notifier).fetchSummary(),
        child: switch (homeState) {
          HomeLoading() => const Center(
              child: CircularProgressIndicator(),
            ),
          HomeError(:final message) => _buildErrorView(
              context,
              ref,
              message,
              isDark,
            ),
          HomeLoaded(:final summary) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Ticket Summary Card (Wallet Overview)
                  HomeTicketSummaryCard(
                    totalTickets: summary.totalTickets,
                    activeTickets: summary.activeTickets,
                  ),

                  const SizedBox(height: 18),

                  // 2. AI Assistant Shortcut Banner
                  const HomeAiAssistantBanner(),

                  const SizedBox(height: 20),

                  // 3. Nearest Live Draw with realtime ticking countdown
                  if (summary.nearestDraw != null) ...[
                    HomeCountdownCard(nearestDraw: summary.nearestDraw!),
                    const SizedBox(height: 24),
                  ],

                  // 4. Recommended Draws Section
                  HomeGiveawayHorizontalList(
                    title: 'Recommended Draws',
                    subtitle: 'Undian pilihan dengan hadiah paling bernilai',
                    icon: Icons.star_rounded,
                    items: summary.recommendedDraws,
                    onSeeAll: () => context.go('/discover'),
                  ),

                  const SizedBox(height: 24),

                  // 5. Nearby Draws Section
                  HomeGiveawayHorizontalList(
                    title: 'Nearby Draws',
                    subtitle: 'Campaign merchant terdekat di sekitarmu',
                    icon: Icons.near_me_rounded,
                    items: summary.nearbyDraws,
                    onSeeAll: () => context.go('/discover'),
                  ),

                  const SizedBox(height: 28),
                ],
              ),
            ),
          _ => const SizedBox.shrink(),
        },
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
              Icons.signal_cellular_connected_no_internet_4_bar_rounded,
              size: 48,
              color: AppColors.errorRed,
            ),
            const SizedBox(height: 16),
            const Text(
              'Gagal Memuat Beranda',
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
                ref.read(homeControllerProvider.notifier).fetchSummary();
              },
            ),
          ],
        ),
      ),
    );
  }
}
