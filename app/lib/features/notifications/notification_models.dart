import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/widgets/status_chip.dart' show StatusTone;

/// Satu notifikasi dari GET /notifications (kolom tabel notifications).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body = '',
    this.giveawayId,
    this.isRead = false,
    this.createdAt,
  });

  final int id;
  final String type, title, body;
  final String? giveawayId;
  final bool isRead;
  final DateTime? createdAt;

  /// null bila id/judul tidak ada (elemen rusak dilewati oleh parseList).
  static AppNotification? tryParse(dynamic raw) {
    final j = asMap(raw);
    final id = j?['id'];
    final title = asString(j?['title']);
    final idInt = id is num ? id.toInt() : (id is String ? int.tryParse(id) : null);
    if (j == null || idInt == null || title == null) return null;
    final gid = asString(j['giveaway_id']);
    return AppNotification(
      id: idInt,
      type: asString(j['type']) ?? 'info',
      title: title,
      body: asString(j['body']) ?? '',
      giveawayId: gid == null || gid.isEmpty ? null : gid,
      isRead: j['is_read'] == true,
      createdAt: asDate(j['created_at']),
    );
  }

  AppNotification asRead() => AppNotification(
        id: id, type: type, title: title, body: body, giveawayId: giveawayId, isRead: true, createdAt: createdAt,
      );
}

/// Tampilan satu jenis notifikasi: ikon, label Indonesia, nada chip. Jenis di luar daftar (CHECK di
/// backend\db\01_schema.sql: ticket_created, draw_result, winner, reminder, info) memakai tampilan umum.
class NotificationKind {
  const NotificationKind(this.icon, this.label, this.tone);
  final IconData icon;
  final String label;
  final StatusTone tone;

  static NotificationKind of(String type) => switch (type) {
        'winner' => const NotificationKind(Icons.emoji_events, 'Menang', StatusTone.success),
        'draw_result' => const NotificationKind(Icons.event_available, 'Draw selesai', StatusTone.neutral),
        'ticket_created' => const NotificationKind(Icons.confirmation_number_outlined, 'Tiket baru', StatusTone.info),
        'reminder' => const NotificationKind(Icons.alarm, 'Pengingat', StatusTone.warning),
        _ => const NotificationKind(Icons.notifications_none, 'Info', StatusTone.neutral),
      };
}
