import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({
    super.key,
    required this.navigationShell,
  });

  void _onItemTapped(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Scaffold(
      body: navigationShell,
      floatingActionButton: Container(
        height: 60,
        width: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.ticketGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPurple.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          child: FloatingActionButton(
            heroTag: 'input_code_fab',
            elevation: 0,
            hoverElevation: 0,
            focusElevation: 0,
            highlightElevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            tooltip: 'Input Kode',
            onPressed: () => context.push('/input-code'),
            child: const Icon(Icons.qr_code_scanner_rounded, size: 28),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(top: BorderSide(color: borderColor, width: 1)),
        ),
        child: BottomAppBar(
          padding: EdgeInsets.zero,
          height: 68,
          color: backgroundColor,
          surfaceTintColor: Colors.transparent,
          notchMargin: 8,
          shape: const CircularNotchedRectangle(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Tab 0: Home
              _NavBarItem(
                icon: Icons.home_rounded,
                label: 'Home',
                isSelected: navigationShell.currentIndex == 0,
                onTap: () => _onItemTapped(0),
              ),
              // Tab 1: Discover
              _NavBarItem(
                icon: Icons.explore_rounded,
                label: 'Jelajah',
                isSelected: navigationShell.currentIndex == 1,
                onTap: () => _onItemTapped(1),
              ),
              // Spacer for center FAB
              const SizedBox(width: 56),
              // Tab 2: My Tickets
              _NavBarItem(
                icon: Icons.confirmation_num_rounded,
                label: 'Tiket',
                isSelected: navigationShell.currentIndex == 2,
                onTap: () => _onItemTapped(2),
              ),
              // Tab 3: Game
              _NavBarItem(
                icon: Icons.sports_esports_rounded,
                label: 'Game',
                isSelected: navigationShell.currentIndex == 3,
                onTap: () => _onItemTapped(3),
              ),
              // Tab 4: Profile
              _NavBarItem(
                icon: Icons.person_rounded,
                label: 'Profil',
                isSelected: navigationShell.currentIndex == 4,
                onTap: () => _onItemTapped(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primaryPurple;
    final inactiveColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
