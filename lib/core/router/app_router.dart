import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../widgets/main_scaffold.dart';
import '../../features/auth/presentation/controllers/auth_controller.dart';
import '../../features/auth/presentation/controllers/auth_state.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/discover/presentation/screens/discover_screen.dart';
import '../../features/tickets/presentation/screens/tickets_screen.dart';
import '../../features/tickets/presentation/screens/ticket_detail_screen.dart';
import '../../features/tickets/domain/models/ticket_model.dart';
import '../../features/game/presentation/screens/game_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/input_code/presentation/screens/input_code_screen.dart';
import '../../features/ai_assistant/presentation/screens/ai_assistant_screen.dart';
import '../../features/draw/presentation/screens/draw_screen.dart';
import '../../features/draw/presentation/screens/draw_detail_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen<AuthState>(authControllerProvider, (_, next) {
    authNotifier.value = next;
  });
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isSplash = location == '/splash';
      final isLogin = location == '/login';
      final isRegister = location == '/register';
      final isAuthRoute = isLogin || isRegister;

      // 1. Initial & loading states stay on splash
      if (auth is AuthInitial || auth is AuthLoading) {
        return isSplash ? null : '/splash';
      }

      // 2. Unauthenticated: only allow auth routes, redirect protected routes to login
      if (auth is Unauthenticated || auth is AuthError) {
        return isAuthRoute ? null : '/login';
      }

      // 3. Authenticated
      if (auth is Authenticated) {
        // If biometric re-lock is required, lock at splash
        if (auth.isBiometricRequired) {
          return isSplash ? null : '/splash';
        }
        // If logged in, redirect away from splash, login, and register to /home
        if (isAuthRoute || isSplash) {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      // Splash Screen
      GoRoute(
        path: '/splash',
        name: 'splash',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth Routes
      GoRoute(
        path: '/login',
        name: 'login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterScreen(),
      ),

      // Bottom Navigation Tabs
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

      GoRoute(
        path: '/tickets/:id',
        name: 'ticket-detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final ticketId = state.pathParameters['id'] ?? '';
          final extraTicket = state.extra as TicketModel?;
          return TicketDetailScreen(
            ticketId: ticketId,
            initialTicket: extraTicket,
          );
        },
      ),
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
      GoRoute(
        path: '/draw/:id',
        name: 'draw-detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final giveawayId = state.pathParameters['id'] ?? '';
          return DrawDetailScreen(giveawayId: giveawayId);
        },
      ),
    ],
  );
});
