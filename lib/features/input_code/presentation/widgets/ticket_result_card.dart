import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/models/redeem_result_model.dart';

class TicketResultCard extends StatefulWidget {
  final RedeemTicketInfo ticket;
  final VoidCallback onRedeemAnother;
  final VoidCallback onViewMyTickets;

  const TicketResultCard({
    super.key,
    required this.ticket,
    required this.onRedeemAnother,
    required this.onViewMyTickets,
  });

  @override
  State<TicketResultCard> createState() => _TicketResultCardState();
}

class _TicketResultCardState extends State<TicketResultCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String drawDateText = 'Sesuai Jadwal';
    if (widget.ticket.drawAt != null) {
      try {
        drawDateText = DateFormat('dd MMM yyyy, HH:mm', 'id_ID')
            .format(widget.ticket.drawAt!.toLocal());
      } catch (_) {
        drawDateText = DateFormat('dd MMM yyyy, HH:mm')
            .format(widget.ticket.drawAt!.toLocal());
      }
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Column(
          children: [
            // Ticket container with cutout styling
            ClipPath(
              clipper: const _TicketClipper(notchRadius: 14),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.primaryPurple.withAlpha(40),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    // Header banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 20,
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.successGreen,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Kode Berhasil Diverifikasi!',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tiket digital Anda telah resmi diterbitkan',
                            style: TextStyle(
                              color: Colors.white.withAlpha(220),
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    // Ticket details section
                    Padding(
                      padding: const EdgeInsets.all(22.0),
                      child: Column(
                        children: [
                          // Ticket Number Card
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
                                color: AppColors.primaryPurple.withAlpha(60),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'TICKET NUMBER',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.5,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.ticket.ticketNumber.startsWith('#')
                                      ? widget.ticket.ticketNumber
                                      : '#${widget.ticket.ticketNumber}',
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

                          const SizedBox(height: 18),

                          // Dashed divider
                          Row(
                            children: List.generate(
                              30,
                              (index) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2.0,
                                  ),
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

                          const SizedBox(height: 18),

                          // Giveaway title
                          _buildInfoRow(
                            context: context,
                            icon: Icons.card_giftcard,
                            label: 'Giveaway',
                            value: widget.ticket.giveawayTitle,
                            valueBold: true,
                          ),

                          const SizedBox(height: 14),

                          // Status: Eligible
                          _buildInfoRow(
                            context: context,
                            icon: Icons.verified,
                            label: 'Status Undian',
                            valueWidget: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.successGreen.withAlpha(35),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.successGreen.withAlpha(120),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check,
                                    size: 14,
                                    color: AppColors.successGreen,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Eligible',
                                    style: TextStyle(
                                      color: AppColors.successGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Draw schedule
                          _buildInfoRow(
                            context: context,
                            icon: Icons.schedule,
                            label: 'Waktu Draw',
                            value: drawDateText,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            AppButton(
              text: 'Tukarkan Kode Lain',
              icon: Icons.add_circle_outline,
              onPressed: widget.onRedeemAnother,
            ),
            const SizedBox(height: 12),
            AppButton(
              text: 'Lihat Tiket Saya',
              variant: AppButtonVariant.outline,
              icon: Icons.confirmation_number_outlined,
              onPressed: widget.onViewMyTickets,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    String? value,
    Widget? valueWidget,
    bool valueBold = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: AppColors.accentCyan),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: theme.textTheme.bodyMedium?.color?.withAlpha(180),
            fontSize: 13,
          ),
        ),
        const Spacer(),
        if (valueWidget != null)
          valueWidget
        else if (value != null)
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: TextStyle(
                fontWeight: valueBold ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
      ],
    );
  }
}

/// Custom Clipper that cuts circular notches on the left and right edges
/// to simulate a real lottery/raffle ticket.
class _TicketClipper extends CustomClipper<Path> {
  final double notchRadius;

  const _TicketClipper({this.notchRadius = 14});

  @override
  Path getClip(Size size) {
    final path = Path();
    final notchY = size.height * 0.42;

    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, notchY - notchRadius);

    // Right notch
    path.arcToPoint(
      Offset(size.width, notchY + notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(0, notchY + notchRadius);

    // Left notch
    path.arcToPoint(
      Offset(0, notchY - notchRadius),
      radius: Radius.circular(notchRadius),
      clockwise: false,
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TicketClipper oldClipper) =>
      oldClipper.notchRadius != notchRadius;
}
