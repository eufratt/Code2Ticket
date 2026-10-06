import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:code2ticket/features/discover/domain/models/giveaway_model.dart';
import '../controllers/draw_controller.dart';
import '../widgets/realtime_countdown_widget.dart';

class DrawScreen extends ConsumerStatefulWidget {
  const DrawScreen({super.key});

  @override
  ConsumerState<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends ConsumerState<DrawScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(drawListControllerProvider);
    final selectedCurrency = ref.watch(selectedCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Draw & Pemenang'),
        actions: [
          PopupMenuButton<SupportedCurrency>(
            initialValue: selectedCurrency,
            tooltip: 'Pilih Mata Uang',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedCurrency.code,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.primaryPurple),
                ],
              ),
            ),
            onSelected: (currency) {
              ref.read(selectedCurrencyProvider.notifier).setCurrency(currency);
            },
            itemBuilder: (context) => SupportedCurrency.values.map((c) {
              return PopupMenuItem<SupportedCurrency>(
                value: c,
                child: Text('${c.symbol} (${c.code}) - ${c.displayName}'),
              );
            }).toList(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryPurple,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Draw Aktif'),
                  if (state.activeDraws.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Badge.count(
                      count: state.activeDraws.length,
                      backgroundColor: AppColors.primaryPurple,
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Selesai & Pemenang'),
          ],
        ),
      ),
      body: state.isLoading && state.activeDraws.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null && state.activeDraws.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.errorRed),
                        const SizedBox(height: 12),
                        Text(
                          state.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.lightTextSecondary),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () {
                            ref.read(drawListControllerProvider.notifier).fetchDraws();
                          },
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Active Draws
                    _buildActiveDrawsList(context, state.activeDraws),
                    // Tab 2: Completed Draws
                    _buildCompletedDrawsList(context, state.completedDraws),
                  ],
                ),
    );
  }

  Widget _buildActiveDrawsList(BuildContext context, List<GiveawayModel> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Tidak Ada Draw Aktif Saat Ini',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(drawListControllerProvider.notifier).fetchDraws();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final giveaway = items[index];
          return _buildDrawItemCard(context, giveaway, isActive: true);
        },
      ),
    );
  }

  Widget _buildCompletedDrawsList(BuildContext context, List<GiveawayModel> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Belum Ada Pengundian Selesai',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Hasil pemenang akan muncul di sini setelah pengundian.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(drawListControllerProvider.notifier).fetchDraws();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final giveaway = items[index];
          return _buildDrawItemCard(context, giveaway, isActive: false);
        },
      ),
    );
  }

  Widget _buildDrawItemCard(
    BuildContext context,
    GiveawayModel giveaway, {
    required bool isActive,
  }) {
    final selectedCurrency = ref.watch(selectedCurrencyProvider);
    final currencyService = ref.watch(currencyServiceProvider);
    final ratesAsync = ref.watch(currencyRatesProvider);

    final rates = ratesAsync.value;
    final formattedPrize = currencyService.format(
      giveaway.prizeValueUsd,
      selectedCurrency,
      rates,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: () {
          context.push('/draw/${giveaway.id}');
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      giveaway.category,
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${giveaway.winnerCount} Pemenang',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                giveaway.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.card_giftcard, size: 16, color: AppColors.ticketGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${giveaway.prizeName} ($formattedPrize)',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryPurple,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (isActive)
                RealtimeCountdownWidget(targetDate: giveaway.drawAt)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: AppColors.successGreen),
                      SizedBox(width: 8),
                      Text(
                        'Pengundian Selesai • Hasil Terverifikasi On-Chain',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.successGreen,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
