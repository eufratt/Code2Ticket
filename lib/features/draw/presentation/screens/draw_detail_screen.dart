import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:code2ticket/core/services/currency_service.dart';
import 'package:code2ticket/core/services/timezone_service.dart';
import 'package:code2ticket/core/theme/app_colors.dart';
import 'package:code2ticket/core/widgets/app_button.dart';
import 'package:code2ticket/features/draw/presentation/controllers/draw_detail_controller.dart';
import 'package:code2ticket/features/draw/domain/models/draw_detail_model.dart';
import 'package:code2ticket/features/draw/domain/models/winner_model.dart';
import '../widgets/realtime_countdown_widget.dart';

class DrawDetailScreen extends ConsumerWidget {
  final String giveawayId;

  const DrawDetailScreen({
    super.key,
    required this.giveawayId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(drawDetailProvider(giveawayId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Undian'),
        actions: [
          IconButton(
            tooltip: 'Segarkan Data',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(drawDetailProvider(giveawayId));
            },
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.errorRed),
                const SizedBox(height: 12),
                Text(
                  'Gagal memuat detail undian: $err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(drawDetailProvider(giveawayId)),
                  child: const Text('Coba Lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (detail) => _buildDetailContent(context, ref, detail),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : Colors.grey.shade200,
            ),
          ),
        ),
        child: SafeArea(
          child: AppButton(
            text: 'Tukarkan Kode Tiket Campaign Ini',
            icon: Icons.confirmation_number_outlined,
            onPressed: () {
              context.push('/input-code');
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDetailContent(
    BuildContext context,
    WidgetRef ref,
    DrawDetailModel detail,
  ) {
    final giveaway = detail.giveaway;
    final selectedCurrency = ref.watch(selectedCurrencyProvider);
    final currencyService = ref.watch(currencyServiceProvider);
    final ratesAsync = ref.watch(currencyRatesProvider);

    final selectedTz = ref.watch(selectedTimezoneProvider);
    final tzService = ref.watch(timezoneServiceProvider);

    final rates = ratesAsync.value;
    final formattedPrize = currencyService.format(
      giveaway.prizeValueUsd,
      selectedCurrency,
      rates,
    );

    final formattedDrawTime = tzService.formatWithTimezone(
      giveaway.drawAt,
      selectedTz,
      pattern: 'EEEE, d MMMM yyyy - HH:mm',
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Category, Status, and Title
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
              if (giveaway.isGeoRestricted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.ticketGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, size: 12, color: AppColors.ticketGold),
                      const SizedBox(width: 4),
                      Text(
                        giveaway.radiusKm != null
                            ? 'Radius ${giveaway.radiusKm!.toInt()} km'
                            : 'DIY Only',
                        style: const TextStyle(
                          color: AppColors.ticketGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              _buildStatusBadge(giveaway.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            giveaway.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          if (giveaway.description != null && giveaway.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              giveaway.description!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 20),

          // 2. Realtime Countdown Timer
          RealtimeCountdownWidget(
            targetDate: giveaway.drawAt,
          ),
          const SizedBox(height: 20),

          // 3. Prize Section & Live Currency Switcher
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: AppColors.ticketGold, size: 22),
                    const SizedBox(width: 8),
                    const Text(
                      'Hadiah & Nilai',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (rates?.isOfflineFallback == true)
                      const Tooltip(
                        message: 'Kurs Frankfurter offline (menggunakan kurs cadangan)',
                        child: Icon(Icons.cloud_off, size: 16, color: Colors.grey),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  giveaway.prizeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Estimasi Nilai Hadiah: $formattedPrize',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Konversi Mata Uang (Frankfurter API):',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: SupportedCurrency.values.map((c) {
                    final isSelected = selectedCurrency == c;
                    return ChoiceChip(
                      label: Text('${c.code} (${c.symbol})'),
                      selected: isSelected,
                      selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected ? AppColors.primaryPurple : null,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (sel) {
                        if (sel) {
                          ref.read(selectedCurrencyProvider.notifier).setCurrency(c);
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Draw Schedule & Timezone Switcher
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: AppColors.primaryBlue, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Waktu Pengundian',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  formattedDrawTime,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedTz.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pilih Zona Waktu:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: TargetTimezone.values.map((tz) {
                    final isSelected = selectedTz == tz;
                    return ChoiceChip(
                      label: Text(tz.code),
                      selected: isSelected,
                      selectedColor: AppColors.primaryBlue.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected ? AppColors.primaryBlue : null,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (sel) {
                        if (sel) {
                          ref.read(selectedTimezoneProvider.notifier).setTimezone(tz);
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Campaign Stats / Metrics
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Statistik & Periode',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Periode Campaign',
                  value:
                      '${DateFormat('d MMM yyyy').format(giveaway.startAt)} - ${DateFormat('d MMM yyyy').format(giveaway.endAt)}',
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Total Tiket Terkumpul',
                  value: '${giveaway.ticketCount} Tiket',
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  icon: Icons.people_alt_outlined,
                  label: 'Kuota Pemenang',
                  value: '${giveaway.winnerCount} Pemenang',
                ),
                const Divider(height: 20),
                _buildInfoRow(
                  icon: Icons.place_outlined,
                  label: 'Cakupan Lokasi',
                  value: giveaway.isGeoRestricted
                      ? 'Daerah Istimewa Yogyakarta (Radius ${giveaway.radiusKm?.toInt() ?? 10} km)'
                      : 'Seluruh Indonesia (Nasional)',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 6. Syarat & Ketentuan
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.gavel_rounded, size: 20, color: AppColors.primaryPurple),
                    SizedBox(width: 8),
                    Text(
                      'Syarat & Ketentuan Undian',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTermItem('1. Setiap pengguna hanya berhak memiliki 1 tiket undian per campaign.'),
                _buildTermItem('2. Tiket didapatkan dari kode partisipasi resmi campaign eksternal.'),
                _buildTermItem('3. Pengundian berjalan otomatis & acak transparan menggunakan komitmen seed.'),
                _buildTermItem('4. Hasil pemenang diverifikasi di smart contract blockchain lokal.'),
                if (giveaway.isGeoRestricted)
                  _buildTermItem('5. Penukaran kode membutuhkan verifikasi GPS di radius wilayah campaign.'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 7. Hasil Draw & Pemenang
          _buildDrawResultSection(context, detail, isDark),
        ],
      ),
    );
  }

  Widget _buildDrawResultSection(
    BuildContext context,
    DrawDetailModel detail,
    bool isDark,
  ) {
    if (detail.isDrawn) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.successGreen.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.successGreen, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Hasil Pengundian (Selesai)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (detail.isVerifiedOnchain)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.successGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'On-Chain Verified',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.successGreen,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (detail.winners.isEmpty)
              const Text('Pemenang belum dirilis atau sedang diverifikasi.')
            else
              ...detail.winners.map((winner) => _buildWinnerTile(winner)),
            if (detail.txHash != null && detail.txHash!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Bukti Blockchain (Transaction Hash):',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: detail.txHash!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hash transaksi disalin ke clipboard')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          detail.txHash!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.copy, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primaryBlue, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hasil Pengundian',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Pengundian belum dimulai. Pemenang akan dipilih secara transparan & otomatis saat waktu undian tiba.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinnerTile(WinnerModel winner) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: AppColors.ticketGold, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  winner.username,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  'Tiket: ${winner.ticketNumber}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildTermItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.3),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;

    switch (status) {
      case 'completed':
        color = AppColors.successGreen;
        label = 'Selesai';
        break;
      case 'drawing':
        color = AppColors.ticketGold;
        label = 'Sedang Diundi';
        break;
      case 'upcoming':
        color = AppColors.primaryBlue;
        label = 'Akan Datang';
        break;
      case 'active':
      default:
        color = AppColors.successGreen;
        label = 'Aktif';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
