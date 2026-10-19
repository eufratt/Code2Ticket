import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Judul bagian (subtitle) + aksi opsional di kanan ("Lihat semua").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.padding = EdgeInsets.zero});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTap),
        child: Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ),
            if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}
