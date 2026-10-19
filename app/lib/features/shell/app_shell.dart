import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Lokasi kustom FAB melayang di tengah horizontal, tepat di atas bottom navigation bar.
class AboveNavCenterFloatLocation extends FloatingActionButtonLocation {
  const AboveNavCenterFloatLocation({this.margin = 10.0});
  final double margin;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double fabX = (scaffoldGeometry.scaffoldSize.width -
            scaffoldGeometry.floatingActionButtonSize.width) /
        2.0;
    final double fabY = scaffoldGeometry.contentBottom -
        scaffoldGeometry.floatingActionButtonSize.height -
        margin;
    return Offset(fabX, fabY);
  }
}

/// Kerangka navigasi: 5 tab simetris sama lebar (Home, Discover, My Tickets, Asisten, Profil)
/// dan 1 FAB melayang di tengah tepat di atas bar tanpa notch.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.explore_outlined, Icons.explore, 'Discover'),
    (Icons.confirmation_number_outlined, Icons.confirmation_number, 'My Tickets'),
    (Icons.smart_toy_outlined, Icons.smart_toy, 'Asisten'),
    (Icons.person_outline, Icons.person, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    final c = context.colors;
    final labelStyle = Theme.of(context).textTheme.labelMedium!;

    Widget item(int index, (IconData, IconData, String) d) {
      final selected = index == current;
      final color = selected ? c.primary : c.muted;
      return Expanded(
        child: Semantics(
          selected: selected,
          child: InkWell(
            onTap: () => navigationShell.goBranch(index, initialLocation: index == current),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.s4, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Indikator tab aktif: pil lembut di belakang ikon.
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.fast),
                    curve: Motion.curve,
                    width: 56,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected ? c.primaryContainer : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.full),
                    ),
                    child: Icon(selected ? d.$2 : d.$1, size: 24, color: selected ? c.onPrimaryContainer : color),
                  ),
                  const SizedBox(height: 2),
                  // Label bar dibatasi 1,15x: lima tab selebar 72 dp tidak muat lebih besar; isi layar tetap memakai skala penuh.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.15,
                    child: Text(
                      d.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: labelStyle.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: const AboveNavCenterFloatLocation(margin: 10.0),
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: AppShadows.fab(c)),
        child: FloatingActionButton(
          tooltip: 'Input Code',
          heroTag: null,
          onPressed: () => context.push('/code'),
          child: const Icon(Icons.qr_code_2, size: 28),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        height: 64,
        color: c.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outline))),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++) item(i, _tabs[i]),
            ],
          ),
        ),
      ),
    );
  }
}
