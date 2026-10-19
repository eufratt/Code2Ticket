import 'package:go_router/go_router.dart';

import 'features/admin/admin_giveaway_screen.dart';
import 'features/admin/admin_giveaways_screen.dart';
import 'features/admin/codes_list_screen.dart';
import 'features/admin/create_giveaway_screen.dart';
import 'features/admin/generate_codes_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/biometric_lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/converter/converter_screen.dart';
import 'features/discover/discover_screen.dart';
import 'features/discover/map_screen.dart';
import 'features/feedback/feedback_screen.dart';
import 'features/giveaways/giveaway_detail_screen.dart';
import 'features/giveaways/giveaway_models.dart';
import 'features/giveaways/home_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/tickets/input_code_screen.dart';
import 'features/tickets/tickets_screen.dart';
import 'splash_screen.dart';
import 'features/shell/coming_soon_screen.dart';

/// Route guard: belum login -> /login; terkunci -> /lock; login -> /home.
GoRouter buildRouter(AuthController auth) => GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        final isAuthPage = loc == '/login' || loc == '/register';
        switch (auth.status) {
          case AuthStatus.unknown:
            return loc == '/splash' ? null : '/splash';
          case AuthStatus.signedOut:
            return isAuthPage ? null : '/login';
          case AuthStatus.biometricRequired:
            return loc == '/lock' ? null : '/lock';
          case AuthStatus.signedIn:
            // Layar Admin hanya untuk role admin (server tetap penentu: 403 pada tiap permintaan admin).
            if (loc.startsWith('/admin') && auth.user?.isAdmin != true) return '/profile';
            return (isAuthPage || loc == '/splash' || loc == '/lock')
                ? '/home'
                : null;
        }
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(path: '/lock', builder: (_, _) => const BiometricLockScreen()),
        // Layar di luar tab (tanpa bottom navigation): dibuka dengan push dari tab mana pun.
        GoRoute(path: '/code', builder: (_, _) => const InputCodeScreen()),
        GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
        GoRoute(path: '/converter', builder: (_, _) => const ConverterScreen()),
        GoRoute(path: '/feedback', builder: (_, _) => const FeedbackScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
        GoRoute(path: '/admin', builder: (_, _) => const AdminGiveawaysScreen()),
        GoRoute(path: '/admin/create', builder: (_, _) => const CreateGiveawayScreen()),
        GoRoute(
          path: '/admin/giveaway/:id',
          builder: (_, state) => AdminGiveawayScreen(giveawayId: state.pathParameters['id']!, initial: state.extra is Giveaway ? state.extra as Giveaway : null),
        ),
        GoRoute(
          path: '/admin/giveaway/:id/generate',
          builder: (_, state) => GenerateCodesScreen(giveawayId: state.pathParameters['id']!, giveaway: state.extra is Giveaway ? state.extra as Giveaway : null),
        ),
        GoRoute(
          path: '/admin/giveaway/:id/codes',
          builder: (_, state) => CodesListScreen(giveawayId: state.pathParameters['id']!, giveaway: state.extra is Giveaway ? state.extra as Giveaway : null),
        ),
        GoRoute(
          path: '/giveaway/:id',
          builder: (_, state) => GiveawayDetailScreen(
            giveawayId: state.pathParameters['id']!,
            initial: state.extra is Giveaway ? state.extra as Giveaway : null,
          ),
        ),
        // 5 tab; FAB tengah (Input Code) ada di AppShell.
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/discover', builder: (_, _) => const DiscoverScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/tickets', builder: (_, _) => const TicketsScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/assistant',
                builder: (_, _) => const ComingSoonScreen(
                    title: 'AI Assistant', note: 'Asisten chat dikerjakan di M7.'),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
            ]),
          ],
        ),
      ],
    );
