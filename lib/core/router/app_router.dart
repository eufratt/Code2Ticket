import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../widgets/main_scaffold.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/discover/presentation/screens/discover_screen.dart';
import '../../features/tickets/presentation/screens/tickets_screen.dart';
import '../../features/game/presentation/screens/game_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/input_code/presentation/screens/input_code_screen.dart';
import '../../features/ai_assistant/presentation/screens/ai_assistant_screen.dart';
import '../../features/draw/presentation/screens/draw_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          // Branch 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Branch 1: Discover
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                name: 'discover',
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          // Branch 2: My Tickets
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tickets',
                name: 'tickets',
                builder: (context, state) => const TicketsScreen(),
              ),
            ],
          ),
          // Branch 3: Game
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/game',
                name: 'game',
                builder: (context, state) => const GameScreen(),
              ),
            ],
          ),
          // Branch 4: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // Standalone Routes
      GoRoute(
        path: '/input-code',
        name: 'input-code',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const InputCodeScreen(),
      ),
      GoRoute(
        path: '/ai-assistant',
        name: 'ai-assistant',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: '/draw',
        name: 'draw',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DrawScreen(),
      ),
    ],
  );
});
