import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'core/api/rpc_client.dart';
import 'core/config.dart';
import 'core/session/session_store.dart';
import 'features/auth/auth_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Code2TicketApp());
}

class Code2TicketApp extends StatefulWidget {
  const Code2TicketApp({super.key});
  @override
  State<Code2TicketApp> createState() => _Code2TicketAppState();
}

class _Code2TicketAppState extends State<Code2TicketApp> {
  late final RpcClient _rpc = RpcClient();
  late final AuthController _auth =
      AuthController(_rpc, SessionStore())..restore();
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
                'SUPABASE_URL / SUPABASE_ANON_KEY belum diisi.\n'
                'Jalankan dengan --dart-define (lihat README_M2.md).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    return MultiProvider(
      providers: [
        Provider<RpcClient>.value(value: _rpc),
        ChangeNotifierProvider<AuthController>.value(value: _auth),
      ],
      child: MaterialApp.router(
        title: 'Code2Ticket',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        routerConfig: _router,
      ),
    );
  }
}
