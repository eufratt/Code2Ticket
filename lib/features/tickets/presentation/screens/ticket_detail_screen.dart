import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/models/ticket_model.dart';
import '../controllers/tickets_controller.dart';

class TicketDetailScreen extends ConsumerWidget {
  final String ticketId;
  final TicketModel? initialTicket;

  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    this.initialTicket,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use initialTicket if passed directly, or fetch from repository
    if (initialTicket != null) {
      return _buildContent(context, initialTicket!, isDark);
    }

    return FutureBuilder<TicketModel?>(
      future: ref.read(ticketRepositoryProvider).getTicketDetail(ticketId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detail Tiket')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detail Tiket')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.errorRed,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tiket Tidak Ditemukan',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error?.toString() ??
                          'Informasi tiket tidak tersedia atau telah dihapus.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppButton(
                      text: 'Kembali',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _buildContent(context, snapshot.data!, isDark);
      },
    );
  }

  Widget _buildContent(BuildContext context, TicketModel ticket, bool isDark) {
    final theme = Theme.of(context);

    String drawDateFormatted = 'Sesuai Jadwal';
    if (ticket.drawAt != null) {
      try {
        drawDateFormatted = DateFormat('dd MMMM yyyy, HH:mm', 'id_ID')
            .format(ticket.drawAt!.toLocal());
      } catch (_) {
        drawDateFormatted = DateFormat('dd MMM yyyy, HH:mm')
            .format(ticket.drawAt!.toLocal());
      }
    }

    final createdDateFormatted = DateFormat('dd MMM yyyy, HH:mm')
        .format(ticket.createdAt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Tiket'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Bagikan Nomor Tiket',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ticket.ticketNumber));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Nomor tiket #${ticket.ticketNumber} disalin ke clipboard!',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          children: [
            // Ticket Pass Container
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primaryPurple.withAlpha(40),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gradient Ticket Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 22,
                    ),
                    decoration: const BoxDecoration(
                      gradient: AppColors.ticketGradient,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(19),
                        topRight: Radius.circular(19),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Category Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            ticket.giveawayCategory.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          ticket.giveawayTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ticket.prizeDescription,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withAlpha(220),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Ticket Body
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // Big Monospace Ticket Number
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primaryPurple.withAlpha(50),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'NOMOR TIKET RESMI',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ticket.ticketNumber.startsWith('#')
                                    ? ticket.ticketNumber
                                    : '#${ticket.ticketNumber}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                  color: AppColors.primaryPurple,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Status Badge
                        _buildStatusRow(ticket.status),

                        const SizedBox(height: 20),

                        // Dashed Separator
                        Row(
                          children: List.generate(
                            28,
                            (index) => Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2.0),
                                child: Container(
                                  height: 1.5,
                                  color: (index % 2 == 0)
                                      ? Colors.grey.withAlpha(80)
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Detail Rows
                        _buildDetailRow(
                          context,
                          icon: Icons.calendar_today_rounded,
                          label: 'Waktu Pengundian',
                          value: drawDateFormatted,
                        ),
                        const SizedBox(height: 14),
                        _buildDetailRow(
                          context,
                          icon: Icons.confirmation_number_outlined,
                          label: 'Kode Asal',
                          value: ticket.code ?? '-',
                        ),
                        const SizedBox(height: 14),
                        _buildDetailRow(
                          context,
                          icon: Icons.access_time_rounded,
                          label: 'Waktu Klaim',
                          value: createdDateFormatted,
                        ),
                        if (ticket.prizeValueUsd > 0) ...[
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            context,
                            icon: Icons.attach_money_rounded,
                            label: 'Nilai Hadiah',
                            value: '\$${ticket.prizeValueUsd.toStringAsFixed(0)} USD',
                          ),
                        ],

                        // On-chain verification row if winner or has blockchain proof
                        if (ticket.blockchainProof != null ||
                            ticket.isWinner) ...[
                          const SizedBox(height: 14),
                          _buildDetailRow(
                            context,
                            icon: Icons.security_rounded,
                            label: 'Verifikasi Blockchain',
                            value: 'Terverifikasi On-Chain',
                            valueColor: AppColors.successGreen,
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Fake Barcode visual for ticket aesthetics
                        _buildBarcodeVisual(ticket.ticketNumber, isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Back button
            AppButton(
              text: 'Kembali ke Daftar Tiket',
              variant: AppButtonVariant.outline,
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String status) {
    Color badgeColor;
    String statusText;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'winner':
        badgeColor = AppColors.ticketGold;
        statusText = 'Winner (Pemenang Undian)';
        icon = Icons.emoji_events_rounded;
        break;
      case 'not_selected':
        badgeColor = Colors.grey;
        statusText = 'Not Selected (Belum Beruntung)';
        icon = Icons.sentiment_dissatisfied_rounded;
        break;
      case 'eligible':
      case 'waiting_for_draw':
      default:
        badgeColor = AppColors.successGreen;
        statusText = 'Waiting for Draw (Eligible)';
        icon = Icons.verified_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: badgeColor),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accentCyan),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarcodeVisual(String code, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              32,
              (index) {
                final widths = [2.0, 4.0, 1.0, 3.0, 2.0];
                final width = widths[index % widths.length];
                final isSpace = index % 5 == 0;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: width,
                  height: 38,
                  color: isSpace
                      ? Colors.transparent
                      : (isDark ? Colors.white70 : Colors.black87),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            code.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 3,
              fontFamily: 'monospace',
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
