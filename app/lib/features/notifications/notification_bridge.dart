import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/notifications/background_check.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_planner.dart';
import '../auth/auth_controller.dart';
import '../tickets/tickets_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'notifications_controller.dart';

/// Menghubungkan [NotificationService] dengan keadaan aplikasi (tanpa UI):
/// - daftar tiket dimuat -> pengingat draw diselaraskan;
/// - daftar notifikasi server dimuat (Home dibuka / kembali ke foreground) -> yang baru jadi notifikasi sistem;
/// - logout -> semua jadwal dibatalkan;
/// - notifikasi diketuk (juga saat aplikasi tertutup) -> rute terkait dibuka lewat router, setelah masuk dan lolos kunci biometric.
class NotificationBridge extends StatefulWidget {
  const NotificationBridge({super.key, required this.router, required this.child, this.poller});
  final GoRouter router;

  /// Pemeriksaan latar belakang (Fase B); null = tidak dipakai (mis. di tes).
  final BackgroundPoller? poller;
  final Widget child;

  @override
  State<NotificationBridge> createState() => _NotificationBridgeState();
}

class _NotificationBridgeState extends State<NotificationBridge> with WidgetsBindingObserver {
  late final NotificationService? _svc = context.read<NotificationService?>();
  late final AuthController _auth = context.read<AuthController>();
  late final TicketsController? _tickets = context.read<TicketsController?>();
  late final NotificationsController? _notifs = context.read<NotificationsController?>();
  AuthStatus? _lastStatus;
  String? _registeredUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuth);
    _tickets?.addListener(_onTickets);
    _notifs?.addListener(_onNotifs);
    _svc?.onPending = _tryDispatch;
    _onAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuth);
    _tickets?.removeListener(_onTickets);
    _notifs?.removeListener(_onNotifs);
    if (_svc?.onPending == _tryDispatch) _svc?.onPending = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _svc?.refreshPermission(); // mis. setelah dari pengaturan sistem
  }

  void _onAuth() {
    final svc = _svc;
    if (svc == null) return;
    final status = _auth.status;
    if (status != _lastStatus) {
      _lastStatus = status;
      if (status == AuthStatus.signedOut) {
        _registeredUser = null;
        svc.onLogout();
        widget.poller?.stop();
      }
    }
    final uid = _auth.user?.id;
    if (status == AuthStatus.signedIn && uid != null && uid != _registeredUser) {
      _registeredUser = uid;
      svc.onSignedIn(uid);
      widget.poller?.start();
    }
    _tryDispatch();
  }

  void _onTickets() {
    final t = _tickets;
    if (_auth.status == AuthStatus.signedIn && t != null && t.state == LoadState.loaded) _svc?.syncReminders(t.items);
  }

  void _onNotifs() {
    final n = _notifs, uid = _auth.user?.id;
    if (_auth.status == AuthStatus.signedIn && uid != null && n != null && n.state == LoadState.loaded) {
      _svc?.showServerNotifications(uid, n.items);
    }
  }

  bool _dispatching = false;

  /// Membuka rute muatan yang tertunda begitu pengguna masuk (bukan di Splash/Lock/Login).
  Future<void> _tryDispatch() async {
    final svc = _svc;
    if (svc == null || svc.pendingPayload == null || _auth.status != AuthStatus.signedIn || _dispatching) return;
    _dispatching = true;
    try {
      final route = routeForPayload(svc.pendingPayload);
      svc.pendingPayload = null;
      if (route == null) return;
      // Beri router waktu mengalihkan dari Splash ke Home (maks. ~1 detik) supaya Home berada di bawah layar tujuan.
      for (var i = 0; i < 60 && mounted; i++) {
        await WidgetsBinding.instance.endOfFrame;
        final path = widget.router.routerDelegate.currentConfiguration.uri.path;
        if (path != '/splash' && path != '/lock' && path != '/login') break;
      }
      if (mounted) widget.router.push(route);
    } finally {
      _dispatching = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
