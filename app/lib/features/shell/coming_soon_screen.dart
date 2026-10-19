import 'package:flutter/material.dart';

import '../../core/widgets/widgets.dart';

/// Layar sementara untuk fitur yang dikerjakan di milestone berikutnya.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.note});
  final String title, note;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(icon: Icons.construction, title: 'Segera hadir', message: note),
      );
}
