import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await context
        .read<AuthController>()
        .login(identifier: _id.text.trim(), password: _pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = r.error;
    }); // bila sukses, router otomatis pindah ke /home
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
                          Text('Masuk', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _id,
                            decoration: const InputDecoration(labelText: 'Username atau email'),
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                          ),
                          const SizedBox(height: Spacing.s16),
                          TextFormField(
                            controller: _pw,
                            obscureText: _hide,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                tooltip: _hide ? 'Tampilkan password' : 'Sembunyikan password',
                                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _hide = !_hide),
                              ),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) => (v == null || v.isEmpty) ? 'Wajib diisi' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: Spacing.s16),
                            InlineMessage(_error!, key: const Key('auth_error')),
                          ],
                          const SizedBox(height: Spacing.s24),
                          PrimaryButton(label: 'Masuk', loading: _busy, onPressed: _submit),
                          if (_busy) const WakingUpNotice(),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.s16),
                    PrimaryButton(
                      label: 'Belum punya akun? Daftar',
                      variant: ButtonVariant.text,
                      onPressed: _busy ? null : () => context.go('/register'),
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
