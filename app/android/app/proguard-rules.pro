# flutter_local_notifications menyimpan notifikasi terjadwal sebagai JSON (Gson) dan membacanya lagi saat alarm berbunyi
# atau setelah reboot. Tanpa kelas model ini, R8 mengacak nama field/tipe dan notifikasi terjadwal tidak bisa dibangun ulang.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver { *; }
-keepattributes Signature
-keepattributes *Annotation*
