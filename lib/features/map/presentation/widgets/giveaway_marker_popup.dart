import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../discover/domain/models/giveaway_model.dart';

class GiveawayMarkerPopup extends ConsumerWidget {
  final GiveawayModel giveaway;
  final VoidCallback onClose;

  const GiveawayMarkerPopup({
    super.key,
    required this.giveaway,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCurrency = ref.watch(selectedCurrencyProvider);
    final currencyService = ref.watch(currencyServiceProvider);
    final rates = ref.watch(currencyRatesProvider).value;

    final formattedPrize = currencyService.format(
      giveaway.prizeValueUsd,
      selectedCurrency,
      rates,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final distance = giveaway.distanceKm;

    bool isWithinRadius = true;
    if (giveaway.isGeoRestricted && giveaway.radiusKm != null && distance != null) {
      isWithinRadius = distance <= giveaway.radiusKm!;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isWithinRadius
              ? AppColors.primaryPurple.withValues(alpha: 0.3)
              : AppColors.errorRed.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Category tag & Close button
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
              const SizedBox(width: 8),
              if (distance != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isWithinRadius
                        ? AppColors.successGreen.withValues(alpha: 0.12)
                        : AppColors.errorRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isWithinRadius ? Icons.check_circle : Icons.warning_rounded,
                        size: 12,
                        color: isWithinRadius ? AppColors.successGreen : AppColors.errorRed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${distance.toStringAsFixed(1)} km dari Anda',
                        style: TextStyle(
                          color: isWithinRadius ? AppColors.successGreen : AppColors.errorRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            giveaway.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),

          // Prize & Value
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
          const SizedBox(height: 8),

          // Radius info note
          if (giveaway.isGeoRestricted)
            Text(
              isWithinRadius
                  ? '✓ Anda berada dalam jangkauan campaign (Maks. ${giveaway.radiusKm?.toInt() ?? 10} km). Kode dapat diklaim!'
                  : '⚠ Di luar radius campaign (Maks. ${giveaway.radiusKm?.toInt() ?? 10} km). Dekati lokasi untuk klaim.',
              style: TextStyle(
                fontSize: 11,
                color: isWithinRadius ? AppColors.successGreen : AppColors.errorRed,
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const Text(
              '✓ Campaign Nasional: Dapat diklaim dari mana saja tanpa batasan lokasi.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.successGreen,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 14),

          // Button to Draw Detail
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: () {
                context.push('/draw/${giveaway.id}');
              },
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('Buka Detail Undian'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
