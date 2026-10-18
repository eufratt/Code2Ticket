import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Kerangka navigasi sesuai PRD bagian 8: Home, Discover | FAB Input Code | My Tickets, AI Assistant, Profile.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _left = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.explore_outlined, Icons.explore, 'Discover'),
  ];
  static const _right = [
    (Icons.confirmation_number_outlined, Icons.confirmation_number, 'My Tickets'),
    (Icons.smart_toy_outlined, Icons.smart_toy, 'Asisten'),
    (Icons.person_outline, Icons.person, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;
    Widget item(int index, (IconData, IconData, String) d) {
      final selected = index == current;
      return Expanded(
        child: InkWell(
          onTap: () => navigationShell.goBranch(index, initialLocation: index == current),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? d.$2 : d.$1,
                    color: selected ? Theme.of(context).colorScheme.primary : null),
                Text(d.$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? Theme.of(context).colorScheme.primary : null)),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Input Code',
        onPressed: () => context.push('/code'),
        child: const Icon(Icons.qr_code_2),
      ),
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        notchMargin: 6,
        shape: const CircularNotchedRectangle(),
        child: Row(
          children: [
            for (var i = 0; i < _left.length; i++) item(i, _left[i]),
            const SizedBox(width: 72), // ruang untuk FAB
            for (var i = 0; i < _right.length; i++) item(_left.length + i, _right[i]),
          ],
        ),
      ),
    );
  }
}
