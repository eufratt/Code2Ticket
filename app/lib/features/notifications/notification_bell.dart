import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import 'notifications_controller.dart';

/// Teks lencana: "9+" bila lebih dari 9.
String badgeText(int n) => n > 9 ? '9+' : '$n';

/// Ikon lonceng di header Home + lencana jumlah belum dibaca (ketuk -> Notifikasi).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final n = context.watch<NotificationsController?>()?.unreadCount ?? 0;
    final c = context.colors;
    return Semantics(
      button: true,
      label: n == 0 ? 'Notifikasi' : 'Notifikasi, $n belum dibaca',
      excludeSemantics: true,
      child: InkResponse(
        key: const Key('notification_bell'),
        onTap: () => context.push('/notifications'),
        radius: kMinTap / 2,
        child: SizedBox(
          width: kMinTap,
          height: kMinTap,
          child: Center(
            child: Badge(
              isLabelVisible: n > 0,
              label: Text(badgeText(n), key: const Key('notification_badge')),
              backgroundColor: c.error,
              textColor: c.onError,
              child: Icon(Icons.notifications_none, color: c.onBackground),
            ),
          ),
        ),
      ),
    );
  }
}
