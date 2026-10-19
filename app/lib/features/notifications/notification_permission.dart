import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/notifications/notification_service.dart';

/// Dialog penjelasan SEBELUM izin sistem diminta. Ditolak/ditunda: aplikasi tetap berjalan lewat pusat notifikasi dalam aplikasi.
Future<void> explainAndRequestNotifications(BuildContext context) async {
  final svc = context.read<NotificationService?>();
  if (svc == null || svc.permissionGranted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: const Text('Aktifkan notifikasi?'),
      content: const Text(
        'Code2Ticket memakai notifikasi untuk memberi tahu saat tiketmu terbit, mengingatkan satu jam sebelum draw, '
        'dan saat hasil draw keluar. Kamu bisa mengubahnya kapan saja di Pengaturan. '
        'Tanpa izin, semuanya tetap tersedia di pusat notifikasi dalam aplikasi.',
      ),
      actions: [
        TextButton(key: const Key('notif_later'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Nanti')),
        FilledButton(key: const Key('notif_allow'), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lanjutkan')),
      ],
    ),
  );
  if (ok == true) await svc.requestPermission();
}

/// Sekali per perangkat (saat Home pertama dibuka): tanya bila izin belum ada dan belum pernah ditanyakan.
Future<void> promptNotificationPermissionOnce(BuildContext context) async {
  final svc = context.read<NotificationService?>();
  if (svc == null || svc.permissionGranted || await svc.wasPermissionAsked()) return;
  await svc.markPermissionAsked();
  if (context.mounted) await explainAndRequestNotifications(context);
}
