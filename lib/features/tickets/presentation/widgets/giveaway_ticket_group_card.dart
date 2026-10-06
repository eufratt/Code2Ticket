import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/ticket_model.dart';

class GiveawayTicketGroupCard extends StatelessWidget {
  final GiveawayTicketsGroup group;

  const GiveawayTicketGroupCard({
    super.key,
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String drawDateFormatted = 'Sesuai Jadwal';
    if (group.drawAt != null) {
      try {
        drawDateFormatted = DateFormat('dd MMM yyyy, HH:mm', 'id_ID')
            .format(group.drawAt!.toLocal());
      } catch (_) {
        drawDateFormatted = DateFormat('dd MMM yyyy, HH:mm')
            .format(group.drawAt!.toLocal());
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: group.hasWinner
              ? AppColors.ticketGold.withAlpha(120)
              : AppColors.primaryPurple.withAlpha(40),
          width: group.hasWinner ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Giveaway Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: group.hasWinner
                  ? AppColors.ticketGold.withAlpha(20)
                  : AppColors.primaryPurple.withAlpha(15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple.withAlpha(40),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              group.giveawayCategory.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryPurple,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            drawDateFormatted,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        group.giveawayTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (group.prizeDescription.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          group.prizeDescription,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${group.ticketCount} Tiket',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.withAlpha(30),
          ),

          // Tickets List under this giveaway
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Column(
              children: group.tickets.map((ticket) {
                return _buildTicketRow(context, ticket, isDark);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketRow(BuildContext context, TicketModel ticket, bool isDark) {
    return InkWell(
      onTap: () {
        context.push('/tickets/${ticket.id}', extra: ticket);
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            // Ticket icon
            Icon(
              Icons.confirmation_number_rounded,
              size: 20,
              color: ticket.isWinner
                  ? AppColors.ticketGold
                  : AppColors.primaryPurple,
            ),
            const SizedBox(width: 10),

            // Ticket Number
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.ticketNumber.startsWith('#')
                        ? ticket.ticketNumber
                        : '#${ticket.ticketNumber}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (ticket.code != null && ticket.code!.isNotEmpty)
                    Text(
                      'Kode: ${ticket.code}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                ],
              ),
            ),

            // Status Badge
            _buildStatusBadge(ticket.status),

            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status.toLowerCase()) {
      case 'winner':
        color = AppColors.ticketGold;
        label = 'Winner';
        icon = Icons.emoji_events_rounded;
        break;
      case 'not_selected':
        color = Colors.grey;
        label = 'Not Selected';
        icon = Icons.cancel_outlined;
        break;
      case 'waiting_for_draw':
        color = AppColors.primaryBlue;
        label = 'Waiting Draw';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'eligible':
      default:
        color = AppColors.successGreen;
        label = 'Eligible';
        icon = Icons.check_circle_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
