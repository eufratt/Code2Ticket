import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/discover_filter_model.dart';
import '../controllers/discover_controller.dart';
import '../widgets/discover_filter_modal.dart';
import '../widgets/discover_giveaway_card.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openFilterModal(BuildContext context) {
    final currentFilter = ref.read(discoverControllerProvider).filter;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DiscoverFilterModal(
        initialFilter: currentFilter,
        onApply: (newFilter) {
          ref.read(discoverControllerProvider.notifier).applyFilter(newFilter);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverControllerProvider);
    final selectedCurrency = ref.watch(selectedCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jelajahi Undian'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Lihat Peta Undian',
            onPressed: () {
              context.push('/map');
            },
          ),
          // Currency switcher popup in AppBar
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
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: AppColors.primaryPurple,
                  ),
                ],
              ),
            ),
            onSelected: (currency) {
              ref.read(selectedCurrencyProvider.notifier).setCurrency(currency);
            },
            itemBuilder: (context) => SupportedCurrency.values.map((c) {
              return PopupMenuItem<SupportedCurrency>(
                value: c,
                child: Row(
                  children: [
                    Text(
                      '${c.symbol} (${c.code})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      c.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filter Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      ref.read(discoverControllerProvider.notifier).onSearchChanged(val);
                    },
                    decoration: InputDecoration(
                      hintText: 'Cari giveaway atau hadiah...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(discoverControllerProvider.notifier).onSearchChanged('');
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Badge(
                  isLabelVisible: state.filter.hasActiveFilter,
                  smallSize: 8,
                  backgroundColor: AppColors.primaryPurple,
                  child: IconButton.filledTonal(
                    onPressed: () => _openFilterModal(context),
                    icon: const Icon(Icons.tune_rounded),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Category Chips Bar
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: DiscoverFilterModel.availableCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = DiscoverFilterModel.availableCategories[index];
                final isSelected = state.filter.category == category;
                return ChoiceChip(
                  label: Text(category),
                  selected: isSelected,
                  selectedColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isSelected ? AppColors.primaryBlue : null,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(discoverControllerProvider.notifier).setCategory(category);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // 3. Main Content: Giveaways List / Loading / Empty / Error
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref.read(discoverControllerProvider.notifier).fetchGiveaways();
              },
              child: Builder(
                builder: (context) {
                  if (state.isLoading && state.giveaways.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.errorMessage != null && state.giveaways.isEmpty) {
                    return Center(
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
                                ref.read(discoverControllerProvider.notifier).fetchGiveaways();
                              },
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (state.giveaways.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.search_off_rounded,
                                  size: 36,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Tidak Ada Undian yang Cocok',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Coba sesuaikan kata kunci atau filter pencarian Anda.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(discoverControllerProvider.notifier).resetFilter();
                                },
                                child: const Text('Reset Filter'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: state.giveaways.length,
                    itemBuilder: (context, index) {
                      final giveaway = state.giveaways[index];
                      return DiscoverGiveawayCard(giveaway: giveaway);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
