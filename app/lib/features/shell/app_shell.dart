import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../auth/auth_controller.dart';
import '../notifications/notifications_controller.dart';
import '../profile/user_avatar.dart';

/// Kerangka navigasi: 4 item sama lebar (Home, Profil dengan foto, Saran & Kesan, Logout).
/// Tiga item pertama adalah cabang (tab); Logout hanya aksi (dialog konfirmasi) dan tidak pernah terpilih.
/// Fitur lain (Discover, My Tickets, Asisten, Input Code, Game, ...) dibuka dari Home sebagai layar penuh.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (null, null, 'Profil'), // ikon = foto profil
    (Icons.rate_review_outlined, Icons.rate_review, 'Saran & Kesan'),
    (Icons.logout, Icons.logout, 'Logout'),
  ];
  static const _logoutIndex = 3;

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Kamu perlu masuk lagi untuk melihat tiketmu.'),
        actions: [
          TextButton(key: const Key('logout_cancel'), onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(key: const Key('logout_confirm'), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Keluar')),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    final c = context.colors;
    final labelStyle = Theme.of(context).textTheme.labelMedium!;
    final user = context.watch<AuthController>().user;

    Widget item(int index) {
      final (outlined, filled, label) = _items[index];
      final isLogout = index == _logoutIndex;
      final selected = !isLogout && index == current;
      final color = selected ? c.primary : c.muted;
      final Widget icon = index == 1
          // Foto profil dalam lingkaran kecil; terpilih = cincin `primary` tebal (selain pil dan label tebal).
          ? ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? c.primary : Colors.transparent, width: 2)),
                child: Padding(padding: const EdgeInsets.all(1), child: UserAvatar(user: user, radius: 11)),
              ),
            )
          : Icon(selected ? filled : outlined, size: 24, color: selected ? c.onPrimaryContainer : color);
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            key: Key('nav_${const ['home', 'profile', 'feedback', 'logout'][index]}'),
            onTap: () {
              if (isLogout) {
                _confirmLogout(context);
                return;
              }
              if (index == 0 && current != 0) context.read<NotificationsController?>()?.refreshUnread();
              navigationShell.goBranch(index, initialLocation: index == current);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.s4, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Indikator item aktif: pil lembut di belakang ikon.
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.fast),
                    curve: Motion.curve,
                    width: 56,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? c.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                    child: icon,
                  ),
                  const SizedBox(height: 2),
                  // Label bar dibatasi 1,15x dan, bila masih lebih lebar dari item (1/4 lebar layar), diperkecil seperlunya (bukan dipotong).
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.15,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: labelStyle.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      // Tombol kembali sistem dari Profil / Saran & Kesan kembali ke Home dulu; dari Home keluar aplikasi.
      canPop: current == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: BottomAppBar(
          padding: EdgeInsets.zero,
          height: kNavBarHeight,
          color: c.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outline))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < _items.length; i++) item(i)]),
          ),
        ),
      ),
    );
  }
}
