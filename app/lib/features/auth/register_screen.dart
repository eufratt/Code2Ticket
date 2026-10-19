import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'auth_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _user, _email, _pw, _pw2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await context.read<AuthController>().register(
          username: _user.text,
          email: _email.text,
          fullName: _name.text,
          password: _pw.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.error;
    }); // sukses -> otomatis login -> router pindah ke /home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandHeader(),
                    const SizedBox(height: Spacing.s32),
                    SurfaceCard(
                      raised: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Daftar', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(labelText: 'Nama lengkap'),
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              return (t.isEmpty || t.length > 100) ? 'Wajib diisi (maks. 100 karakter)' : null;
                            },
                          ),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _user,
                            decoration: const InputDecoration(labelText: 'Username'),
                            textInputAction: TextInputAction.next,
                            validator: (v) => RegExp(r'^[A-Za-z0-9_]{4,20}$').hasMatch(v?.trim() ?? '')
                                ? null
                                : '4-20 karakter: huruf, angka, underscore',
                          ),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                            textInputAction: TextInputAction.next,
                            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                                ? null
                                : 'Format email tidak valid',
                          ),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _pw,
                            obscureText: _hide,
                            decoration: InputDecoration(
                              labelText: 'Password (min. 8 karakter)',
                              suffixIcon: IconButton(
                                tooltip: _hide ? 'Tampilkan password' : 'Sembunyikan password',
                                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _hide = !_hide),
                              ),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.length < 8) ? 'Minimal 8 karakter' : null,
                          ),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _pw2,
                            obscureText: _hide,
                            decoration: const InputDecoration(labelText: 'Ulangi password'),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) => v != _pw.text ? 'Password tidak sama' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: Spacing.s16),
                            InlineMessage(_error!, key: const Key('auth_error')),
                          ],
                          const SizedBox(height: Spacing.s24),
                          PrimaryButton(label: 'Daftar', loading: _busy, onPressed: _submit),
                          if (_busy) const WakingUpNotice(),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.s16),
                    PrimaryButton(
                      label: 'Sudah punya akun? Masuk',
                      variant: ButtonVariant.text,
                      onPressed: _busy ? null : () => context.go('/login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
