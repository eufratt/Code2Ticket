import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service to display device-level notifications for ticket creations,
/// winner announcements, and draw updates.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(
        settings: initSettings,
      );

      // Request Android 13+ notification runtime permission
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('NotificationService initialization error: $e');
    }
  }

  Future<void> showTicketCreatedNotification({
    required String ticketNumber,
    required String giveawayTitle,
  }) async {
    try {
      if (!_isInitialized) {
        await init();
      }

      const androidDetails = AndroidNotificationDetails(
        'code2ticket_tickets',
        'Tiket Undian',
        channelDescription: 'Pemberitahuan klaim tiket undian berhasil',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      final notificationId =
          DateTime.now().millisecondsSinceEpoch.remainder(100000);

      await _notificationsPlugin.show(
        id: notificationId,
        title: 'Tiket Berhasil Dibuat!',
        body:
            'Tiket #$ticketNumber Anda aktif untuk undian "$giveawayTitle". Semoga beruntung!',
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('Notification display error: $e');
    }
  }
}
