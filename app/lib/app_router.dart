import 'package:go_router/go_router.dart';

import 'features/admin/admin_giveaway_screen.dart';
import 'features/admin/admin_giveaways_screen.dart';
import 'features/admin/codes_list_screen.dart';
import 'features/admin/create_giveaway_screen.dart';
import 'features/admin/generate_codes_screen.dart';
import 'features/assistant/assistant_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/biometric_lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/converter/converter_screen.dart';
import 'features/discover/discover_screen.dart';
import 'features/draw/draw_result_screen.dart';
import 'features/draw/draw_verify_screen.dart';
import 'features/discover/map_screen.dart';
import 'features/feedback/feedback_screen.dart';
import 'features/game/game_hub_screen.dart';
import 'features/game/leaderboard_screen.dart';
import 'features/game/maze_play_screen.dart';
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
        // Layar fitur penuh (tanpa bottom navigation, tombol kembali di AppBar): dibuka dengan push dari Home.
        GoRoute(path: '/discover', builder: (_, _) => const DiscoverScreen()),
        GoRoute(path: '/tickets', builder: (_, _) => const TicketsScreen()),
        GoRoute(path: '/assistant', builder: (_, _) => const AssistantScreen()),
        GoRoute(path: '/code', builder: (_, _) => const InputCodeScreen()),
        GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
        GoRoute(path: '/converter', builder: (_, _) => const ConverterScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
        GoRoute(path: '/game', builder: (_, _) => const GameHubScreen()),
        GoRoute(path: '/game/play', builder: (_, state) => MazePlayScreen(levelIndex: state.extra is int ? state.extra as int : 0)),
        GoRoute(path: '/leaderboard', builder: (_, _) => const LeaderboardScreen()),
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
        GoRoute(path: '/giveaway/:id/result', builder: (_, state) => DrawResultScreen(giveawayId: state.pathParameters['id']!)),
        GoRoute(path: '/giveaway/:id/verify', builder: (_, state) => DrawVerifyScreen(giveawayId: state.pathParameters['id']!)),
        // 3 tab (Home, Profil, Saran & Kesan); item ke-4 bottom nav (Logout) hanya aksi, bukan rute.
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/feedback', builder: (_, _) => const FeedbackScreen()),
            ]),
          ],
        ),
      ],
    );
