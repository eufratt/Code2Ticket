import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/auth/auth_controller.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (auth.isWakingUp) ...[
              const SizedBox(height: 16),
              const Text('Server sedang bangun, tunggu sebentar...'),
            ],
          ],
        ),
      ),
    );
  }
}
