import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../controllers/auth_controller.dart';
import '../controllers/auth_state.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).checkSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    // Auto navigate once state changes
    ref.listen(authControllerProvider, (previous, next) {
      if (next is Authenticated && !next.isBiometricRequired) {
        context.go('/home');
      } else if (next is Unauthenticated) {
        context.go('/login');
      }
    });

    final isBiometricLock = authState is Authenticated && authState.isBiometricRequired;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryPurpleDark, AppColors.primaryPurple, AppColors.primaryBlue],
            begin: Alignment.topCenter,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                // App Logo Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.confirmation_num_rounded,
                      size: 56,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Code2Ticket',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Undian Digital Terverifikasi Blockchain',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),

                if (isBiometricLock) ...[
                  // Biometric Prompt Button
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.fingerprint_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Aplikasi Terkunci',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Pindai biometrik untuk membuka sesi Anda',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        AppButton(
                          text: 'Buka dengan Biometrik',
                          icon: Icons.fingerprint,
                          variant: AppButtonVariant.primary,
                          onPressed: () async {
                            final ok = await ref
                                .read(authControllerProvider.notifier)
                                .unlockWithBiometric();
                            if (ok && context.mounted) {
                              context.go('/home');
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text(
                            'Masuk dengan Akun Lain',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ] else ...[
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Memuat sistem...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
