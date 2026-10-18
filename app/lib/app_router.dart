import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/biometric_lock_screen.dart';
import 'features/auth/home_placeholder.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
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
        GoRoute(path: '/home', builder: (_, _) => const HomePlaceholder()),
      ],
    );
