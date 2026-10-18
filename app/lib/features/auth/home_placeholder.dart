import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth_controller.dart';

/// Sementara (M2). Diganti bottom navigation 5 tab di M3.
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final u = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Code2Ticket')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Halo, ${u?.fullName ?? '-'}',
                style: Theme.of(context).textTheme.titleLarge),
            Text('@${u?.username} · ${u?.role} · Level ${u?.level}'),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: auth.logout, child: const Text('Keluar')),
          ],
        ),
      ),
    );
  }
}
