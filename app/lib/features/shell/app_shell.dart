import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    Widget item(int index, (IconData, IconData, String) d) {
      final selected = index == current;
      final color = selected ? Theme.of(context).colorScheme.primary : null;
      return Expanded(
        child: InkWell(
          onTap: () => navigationShell.goBranch(index, initialLocation: index == current),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? d.$2 : d.$1,
                    size: 24,
                    color: color),
                const SizedBox(height: 2),
                Text(
                  d.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: const AboveNavCenterFloatLocation(margin: 10.0),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Input Code',
        onPressed: () => context.push('/code'),
        child: const Icon(Icons.qr_code_2),
      ),
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) item(i, _tabs[i]),
          ],
        ),
      ),
    );
  }
}
