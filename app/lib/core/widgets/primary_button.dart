import 'package:flutter/material.dart';

enum ButtonVariant { primary, secondary, text }

/// Tombol aksi. Tinggi 52, radius 12 (dari tema). Saat [loading]: spinner kecil, tombol nonaktif, sehingga tidak bisa
/// terkirim dua kali. [onPressed] null = nonaktif.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final ButtonVariant variant;

  /// Lebar penuh (default). false untuk tombol di dalam Row/dialog.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final action = loading ? null : onPressed;
    final fg = switch (variant) {
      ButtonVariant.primary => Theme.of(context).colorScheme.onPrimary,
      _ => Theme.of(context).colorScheme.primary,
    };
    final Widget child = loading
        ? Semantics(
            label: '$label, sedang diproses',
            excludeSemantics: true,
            child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
          )
        : Text(label, textAlign: TextAlign.center);
    final withIcon = icon != null && !loading;
    final Widget button = switch (variant) {
      ButtonVariant.primary => withIcon
          ? FilledButton.icon(onPressed: action, icon: Icon(icon), label: child)
          : FilledButton(onPressed: action, child: child),
      ButtonVariant.secondary => withIcon
          ? OutlinedButton.icon(onPressed: action, icon: Icon(icon), label: child)
          : OutlinedButton(onPressed: action, child: child),
      ButtonVariant.text => withIcon
          ? TextButton.icon(onPressed: action, icon: Icon(icon), label: child)
          : TextButton(onPressed: action, child: child),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
