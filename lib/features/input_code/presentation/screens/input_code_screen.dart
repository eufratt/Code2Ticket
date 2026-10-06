import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';

class InputCodeScreen extends StatefulWidget {
  const InputCodeScreen({super.key});

  @override
  State<InputCodeScreen> createState() => _InputCodeScreenState();
}

class _InputCodeScreenState extends State<InputCodeScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap masukkan kode partisipasi terlebih dahulu')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Memvalidasi kode: $code')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masukkan Kode'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: AppColors.ticketGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.confirmation_number_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Tukarkan Kode Campaign',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan kode unik dari merchant atau campaign partner untuk mendapatkan tiket undian digital.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.lightTextSecondary,
                  ),
            ),
            const SizedBox(height: 32),
            AppTextField(
              controller: _codeController,
              label: 'Kode Partisipasi',
              hintText: 'Contoh: C2T-PROMO-2026',
              prefixIcon: const Icon(Icons.qr_code, color: AppColors.primaryPurple),
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Klaim Tiket Sekarang',
              icon: Icons.check_circle_outline,
              onPressed: _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
