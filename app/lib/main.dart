import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'core/api/api_client.dart';
import 'core/api/authed_api.dart';
import 'core/config.dart';
import 'core/currency/rates_controller.dart';
import 'core/settings/settings_controller.dart';
import 'core/time/zones.dart';
import 'core/db/cache_store.dart';
import 'core/db/local_db.dart';
import 'core/db/rate_cache.dart' show SettingsStore;
import 'core/geocoding/geocoder.dart';
import 'core/location/location_service.dart';
import 'core/notifications/background_check.dart';
import 'core/notifications/notification_service.dart';
import 'core/security/biometric_service.dart';
import 'core/session/session_store.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/admin_controller.dart';
import 'features/assistant/assistant_controller.dart';
import 'features/auth/auth_controller.dart';
import 'features/discover/discover_controller.dart';
import 'features/game/game_controller.dart';
import 'features/giveaways/affinity_controller.dart';
import 'features/giveaways/giveaways_controller.dart';
import 'features/organizer/organizer_contact.dart';
import 'features/notifications/notification_bridge.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/tickets/tickets_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initTimeZones();
  runApp(const Code2TicketApp());
}

class Code2TicketApp extends StatefulWidget {
  /// Parameter hanya untuk tes boot (klien, penyimpanan, database, biometric, poller latar palsu); produksi memakai bawaan.
  const Code2TicketApp({super.key, this.api, this.sessionStore, this.db, this.biometric, this.poller});
  final ApiClient? api;
  final SessionStore? sessionStore;
  final LocalDb? db;
  final BiometricService? biometric;
  final BackgroundPoller? poller;

  @override
  State<Code2TicketApp> createState() => _Code2TicketAppState();
}

class _Code2TicketAppState extends State<Code2TicketApp> with WidgetsBindingObserver {
  late final LocalDb _db = widget.db ?? LocalDb.instance;
  late final ApiClient _api = widget.api ?? ApiClient();
  late final AuthController _auth =
      AuthController(_api, widget.sessionStore ?? SessionStore(), db: _db, biometric: widget.biometric)..restore();
  late final AuthedApi _authed = AuthedApi(_api, _auth);
  late final LocationService _location = LocationService(GeolocatorGateway());
  late final Geocoder _geocoder = Geocoder();
  late final SettingsController _settings = SettingsController(_db)..load();
  late final RatesController _rates = RatesController(_db)..ensureFresh();
  late final NotificationService _notifService = NotificationService(PluginNotificationGateway(), _db);
  late final BackgroundPoller _poller = widget.poller ?? WorkmanagerPoller();
  late final _router = buildRouter(_auth);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifService.init(); // izin tidak diminta di sini: dialog penjelasan dulu (Home / Pengaturan)
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _rates.handleAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _auth.revalidate(); // sesi offline -> cek ulang ke server
  }

  @override
  Widget build(BuildContext context) {
    if (widget.api == null && !AppConfig.isConfigured) {
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
        Provider<LocalDb>.value(value: _db),
        Provider<SettingsStore>.value(value: _db),
        Provider<CacheStore>.value(value: _db),
        ChangeNotifierProvider<AuthController>.value(value: _auth),
        Provider<AuthedApi>.value(value: _authed),
        Provider<LocationService>.value(value: _location),
        Provider<Geocoder>.value(value: _geocoder),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<RatesController>.value(value: _rates),
        ChangeNotifierProvider<NotificationService>.value(value: _notifService),
        ChangeNotifierProvider(create: (_) => OrganizerContactController(_authed, _db)),
        ChangeNotifierProvider(create: (_) => GiveawaysController(_authed, _auth, _db)),
        ChangeNotifierProvider(create: (_) => TicketsController(_authed, _auth, _db)),
        ChangeNotifierProvider(create: (_) => NotificationsController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => AdminController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => GameController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => AffinityController(_authed, _auth)),
        ChangeNotifierProvider(create: (_) => AssistantController(_authed, _auth, _db)),
        ChangeNotifierProvider(create: (_) => DiscoverController(_authed, _auth, _db, _location)),
      ],
      child: NotificationBridge(
        router: _router,
        poller: _poller,
        child: ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => MaterialApp.router(
            title: 'Code2Ticket',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _settings.themeMode,
            // "Kurangi animasi" sistem: pindah layar tanpa transisi. Status/nav bar sistem mengikuti tema aktif
            // (AppBar menimpanya sendiri di layar yang punya AppBar).
            builder: (context, child) {
              final theme = MediaQuery.disableAnimationsOf(context)
                  ? AppTheme.withoutPageTransitions(Theme.of(context))
                  : Theme.of(context);
              final dark = theme.brightness == Brightness.dark;
              return Theme(
                data: theme,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: theme.scaffoldBackgroundColor,
                    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                  ),
                  child: child!,
                ),
              );
            },
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
