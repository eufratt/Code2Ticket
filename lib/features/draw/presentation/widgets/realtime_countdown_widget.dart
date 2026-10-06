import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class RealtimeCountdownWidget extends StatefulWidget {
  final DateTime targetDate;
  final VoidCallback? onFinished;

  const RealtimeCountdownWidget({
    super.key,
    required this.targetDate,
    this.onFinished,
  });

  @override
  State<RealtimeCountdownWidget> createState() => _RealtimeCountdownWidgetState();
}

class _RealtimeCountdownWidgetState extends State<RealtimeCountdownWidget> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _calculateRemaining();
      }
    });
  }

  void _calculateRemaining() {
    final now = DateTime.now();
    final diff = widget.targetDate.difference(now);
    if (diff.isNegative) {
      if (_remaining != Duration.zero) {
        setState(() {
          _remaining = Duration.zero;
        });
        widget.onFinished?.call();
      }
    } else {
      setState(() {
        _remaining = diff;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.ticketGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ticketGold.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_bottom_rounded, color: AppColors.ticketGold, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Waktu pengundian tiba! Pengacakan nomor tiket sedang/telah diproses.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ticketGold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryPurple.withValues(alpha: 0.08),
            AppColors.primaryBlue.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryPurple.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'HITUNG MUNDUR DRAW REALTIME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: AppColors.primaryPurple,
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.access_time_filled,
                size: 16,
                color: AppColors.primaryPurple,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTimeUnit(context, days.toString().padLeft(2, '0'), 'Hari'),
              _buildColon(),
              _buildTimeUnit(context, hours.toString().padLeft(2, '0'), 'Jam'),
              _buildColon(),
              _buildTimeUnit(context, minutes.toString().padLeft(2, '0'), 'Menit'),
              _buildColon(),
              _buildTimeUnit(context, seconds.toString().padLeft(2, '0'), 'Detik'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColon() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryPurple,
        ),
      ),
    );
  }

  Widget _buildTimeUnit(BuildContext context, String value, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          width: 58,
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.15),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: AppColors.primaryPurple,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
