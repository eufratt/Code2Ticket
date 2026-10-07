import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/home_summary_model.dart';

class HomeGiveawayHorizontalList extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<HomeGiveawayItem> items;
  final VoidCallback? onSeeAll;
  final String seeAllText;

  const HomeGiveawayHorizontalList({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
    this.onSeeAll,
    this.seeAllText = 'Lihat Semua',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.primaryPurple),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Text(
                    seeAllText,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Horizontal Carousel
        SizedBox(
          height: 205,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildItemCard(context, item, isDark);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    HomeGiveawayItem item,
    bool isDark,
  ) {
    final theme = Theme.of(context);

    String drawDateFormatted = 'Segera';
    if (item.drawAt != null) {
      try {
        drawDateFormatted =
            DateFormat('dd MMM yyyy', 'id_ID').format(item.drawAt!.toLocal());
      } catch (_) {
        drawDateFormatted =
            DateFormat('dd MMM yyyy').format(item.drawAt!.toLocal());
      }
    }

    return InkWell(
      onTap: () => context.push(item.id.isNotEmpty ? '/draw/${item.id}' : '/draw'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 245,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primaryPurple.withAlpha(35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Category + Distance / Prize Value
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.category.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                ),
                if (item.distanceKm != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.isWithinRadius
                          ? AppColors.successGreen.withValues(alpha: 0.15)
                          : AppColors.ticketGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 11,
                          color: item.isWithinRadius
                              ? AppColors.successGreen
                              : AppColors.ticketGold,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${item.distanceKm!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: item.isWithinRadius
                                ? AppColors.successGreen
                                : AppColors.ticketGold,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (item.prizeValueUsd > 0)
                  Text(
                    '\$${item.prizeValueUsd.toStringAsFixed(0)} USD',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.ticketGold,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Title
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
            ),

            const SizedBox(height: 4),

            // Prize description
            Text(
              item.prize,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),

            const Spacer(),

            // Location & Date Footer
            Divider(height: 12, color: Colors.grey.withAlpha(30)),

            Row(
              children: [
                Icon(
                  item.isGeoRestricted
                      ? Icons.location_on_rounded
                      : Icons.public_rounded,
                  size: 13,
                  color: item.isGeoRestricted
                      ? AppColors.accentCyan
                      : Colors.grey,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.isGeoRestricted && item.radiusKm != null
                        ? 'Radius ${item.radiusKm!.toStringAsFixed(0)} km'
                        : item.locationName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
                Text(
                  drawDateFormatted,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryPurple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
