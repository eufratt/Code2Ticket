import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../controllers/auth_controller.dart';
import '../controllers/auth_state.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authControllerProvider.notifier).register(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (success && mounted) {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState is AuthLoading;

    ref.listen(authControllerProvider, (previous, next) {
      if (next is AuthError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Akun Baru'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Daftar di Code2Ticket',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dapatkan akses ke undian berhadiah dengan bukti terverifikasi.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.lightTextSecondary,
                        ),
                  ),
                  const SizedBox(height: 28),

                  // Username Input
                  AppTextField(
                    controller: _usernameController,
                    label: 'Username',
                    hintText: 'Minimal 3 karakter (huruf/angka)',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Username wajib diisi.';
                      }
                      if (val.trim().length < 3) {
                        return 'Username minimal 3 karakter.';
                      }
                      if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(val.trim())) {
                        return 'Hanya boleh berisi huruf, angka, titik, dan garis bawah.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Email Input
                  AppTextField(
                    controller: _emailController,
                    label: 'Email',
                    hintText: 'nama@domain.com',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email_outlined),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Email wajib diisi.';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val.trim())) {
                        return 'Format email tidak valid.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password Input
                  AppTextField(
                    controller: _passwordController,
                    label: 'Kata Sandi',
                    hintText: 'Minimal 8 karakter',
                    obscureText: _obscurePassword,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Kata sandi wajib diisi.';
                      }
                      if (val.length < 8) {
                        return 'Kata sandi minimal 8 karakter.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password Input
                  AppTextField(
                    controller: _confirmPasswordController,
                    label: 'Konfirmasi Kata Sandi',
                    hintText: 'Ketik ulang kata sandi',
                    obscureText: _obscureConfirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Konfirmasi kata sandi wajib diisi.';
                      }
                      if (val != _passwordController.text) {
                        return 'Konfirmasi kata sandi tidak cocok.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Register Button
                  AppButton(
                    text: 'Daftar & Buat Akun',
                    isLoading: isLoading,
                    icon: Icons.person_add_rounded,
                    onPressed: isLoading ? null : _handleRegister,
                  ),
                  const SizedBox(height: 24),

                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Sudah memiliki akun? ',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: const Text(
                          'Masuk',
                          style: TextStyle(
                            color: AppColors.primaryPurple,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
