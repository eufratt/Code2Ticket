import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class DrawScreen extends StatelessWidget {
  const DrawScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Draw & Pemenang'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.ticketGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.casino_rounded,
                  size: 40,
                  color: AppColors.ticketGold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Pengundian & Verifikasi On-Chain',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sistem pengacakan nomor undian transparan yang diverifikasi menggunakan smart contract blockchain lokal.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.lightTextSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
