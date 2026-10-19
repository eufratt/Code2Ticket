import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'auth_controller.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await context.read<AuthController>().unlockWithBiometric();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final c = context.colors;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: c.primaryContainer, shape: BoxShape.circle),
                        child: SizedBox(width: 112, height: 112, child: Icon(Icons.fingerprint, size: 64, color: c.onPrimaryContainer)),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.s24),
                  Semantics(
                    header: true,
                    child: Text('Aplikasi Terkunci', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: Spacing.s8),
                  Text(
                    'Verifikasi biometric diperlukan untuk membuka Code2Ticket.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: Spacing.s32),
                  PrimaryButton(label: 'Coba lagi', icon: Icons.lock_open, loading: _busy, onPressed: _retry),
                  const SizedBox(height: Spacing.s12),
                  PrimaryButton(label: 'Keluar', variant: ButtonVariant.secondary, onPressed: _busy ? null : auth.logout),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
