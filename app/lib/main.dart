import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'core/api/api_client.dart';
import 'core/api/authed_api.dart';
import 'core/config.dart';
import 'core/currency/rates_controller.dart';
import 'core/settings/settings_controller.dart';
import 'core/time/zones.dart';
import 'core/db/local_db.dart';
import 'core/db/rate_cache.dart' show SettingsStore;
import 'core/geocoding/geocoder.dart';
import 'core/location/location_service.dart';
import 'core/session/session_store.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/admin_controller.dart';
import 'features/assistant/assistant_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/discover/discover_controller.dart';
import 'features/game/game_controller.dart';
import 'features/giveaways/affinity_controller.dart';
import 'features/giveaways/giveaways_controller.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/tickets/tickets_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initTimeZones();
  runApp(const Code2TicketApp());
}

class Code2TicketApp extends StatefulWidget {
  const Code2TicketApp({super.key});
  @override
  State<Code2TicketApp> createState() => _Code2TicketAppState();
}

class _Code2TicketAppState extends State<Code2TicketApp> with WidgetsBindingObserver {
  late final ApiClient _api = ApiClient();
  late final AuthController _auth =
      AuthController(_api, SessionStore())..restore();
  late final AuthedApi _authed = AuthedApi(_api, _auth);
  late final LocationService _location = LocationService(GeolocatorGateway());
  late final Geocoder _geocoder = Geocoder();
  late final SettingsController _settings = SettingsController(LocalDb.instance)..load();
  late final RatesController _rates = RatesController(LocalDb.instance)..ensureFresh();
  late final _router = buildRouter(_auth);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _rates.handleAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'API_BASE_URL belum diisi.\n'
                'Jalankan dengan:\n'
                'flutter run --dart-define=API_BASE_URL=https://code2ticket.onrender.com',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api),
        Provider<LocalDb>.value(value: LocalDb.instance),
        Provider<SettingsStore>.value(value: LocalDb.instance),
        ChangeNotifierProvider<AuthController>.value(value: _auth),
        Provider<AuthedApi>.value(value: _authed),
        Provider<LocationService>.value(value: _location),
        Provider<Geocoder>.value(value: _geocoder),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<RatesController>.value(value: _rates),
        ChangeNotifierProvider(create: (_) => GiveawaysController(_authed, _auth, LocalDb.instance)),
        ChangeNotifierProvider(create: (_) => TicketsController(_authed, _auth, LocalDb.instance)),
        ChangeNotifierProvider(create: (_) => NotificationsController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => AdminController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => GameController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => AffinityController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => AssistantController(_authed, _auth, LocalDb.instance)),
        ChangeNotifierProvider(create: (_) => DiscoverController(_authed, _auth, LocalDb.instance, _location)),
      ],
      child: MaterialApp.router(
        title: 'Code2Ticket',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        // "Kurangi animasi" sistem: pindah layar tanpa transisi.
        builder: (context, child) => Theme(
          data: MediaQuery.disableAnimationsOf(context) ? AppTheme.withoutPageTransitions(Theme.of(context)) : Theme.of(context),
          child: child!,
        ),
        routerConfig: _router,
      ),
    );
  }
}
