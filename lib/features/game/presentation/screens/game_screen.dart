import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini Game Sensor'),
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
                  color: AppColors.accentCyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sports_esports_rounded,
                  size: 40,
                  color: AppColors.accentCyan,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Mini Game Hiburan',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Game sensor gyroscope untuk hiburan saat menunggu draw.\nCatatan: Skor game TIDAK memengaruhi peluang menang undian.',
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
