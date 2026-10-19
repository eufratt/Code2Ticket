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
import 'core/geocoding/geocoder.dart';
import 'core/location/location_service.dart';
import 'core/session/session_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/discover/discover_controller.dart';
import 'features/giveaways/giveaways_controller.dart';
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

class _Code2TicketAppState extends State<Code2TicketApp> {
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
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) {
      return const MaterialApp(
        home: Scaffold(
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
        ChangeNotifierProvider<AuthController>.value(value: _auth),
        Provider<AuthedApi>.value(value: _authed),
        Provider<LocationService>.value(value: _location),
        Provider<Geocoder>.value(value: _geocoder),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<RatesController>.value(value: _rates),
        ChangeNotifierProvider(create: (_) => GiveawaysController(_authed, _auth, LocalDb.instance)),
        ChangeNotifierProvider(create: (_) => TicketsController(_authed, _auth, LocalDb.instance)),
        ChangeNotifierProvider(create: (_) => DiscoverController(_authed, _auth, LocalDb.instance, _location)),
      ],
      child: MaterialApp.router(
        title: 'Code2Ticket',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        routerConfig: _router,
      ),
    );
  }
}
