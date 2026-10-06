import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum TargetTimezone {
  wib('WIB', 'Asia/Jakarta', 'Waktu Indonesia Barat (UTC+7)', Duration(hours: 7)),
  jst('JST', 'Asia/Tokyo', 'Japan Standard Time (UTC+9)', Duration(hours: 9)),
  utc('UTC', 'UTC', 'Coordinated Universal Time (UTC+0)', Duration.zero),
  local('Lokal', 'LOCAL', 'Waktu Perangkat Pengguna', null);

  final String code;
  final String locationId;
  final String description;
  final Duration? fallbackOffset;

  const TargetTimezone(this.code, this.locationId, this.description, this.fallbackOffset);
}

class TimezoneService {
  static bool _isInitialized = false;

  /// Initialize timezone database safely
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      tz_data.initializeTimeZones();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Warning: Timezone database initialization error: $e');
      _isInitialized = false;
    }
  }

  /// Convert a given DateTime into target timezone DateTime
  DateTime convertToTimezone(DateTime dateTimeUtc, TargetTimezone target) {
    final utcDate = dateTimeUtc.isUtc ? dateTimeUtc : dateTimeUtc.toUtc();

    if (target == TargetTimezone.utc) {
      return utcDate;
    }

    if (target == TargetTimezone.local) {
      return utcDate.toLocal();
    }

    if (_isInitialized) {
      try {
        final location = tz.getLocation(target.locationId);
        final tzDateTime = tz.TZDateTime.from(utcDate, location);
        return tzDateTime;
      } catch (e) {
        debugPrint('Fallback to offset for ${target.code}: $e');
      }
    }

    // Fallback using fixed duration offset if timezone db fails
    if (target.fallbackOffset != null) {
      return utcDate.add(target.fallbackOffset!);
    }

    return utcDate.toLocal();
  }

  /// Format datetime into readable string with timezone abbreviation
  String formatWithTimezone(
    DateTime? dateTime,
    TargetTimezone target, {
    String pattern = 'd MMM yyyy, HH:mm',
  }) {
    if (dateTime == null) return '-';

    final converted = convertToTimezone(dateTime, target);
    final formatter = DateFormat(pattern, 'id_ID');
    final formattedDate = formatter.format(converted);

    String tzAbbreviation = target.code;
    if (target == TargetTimezone.local) {
      final offsetHours = converted.timeZoneOffset.inHours;
      final offsetSign = offsetHours >= 0 ? '+' : '';
      tzAbbreviation = 'UTC$offsetSign$offsetHours (${converted.timeZoneName})';
    }

    return '$formattedDate $tzAbbreviation';
  }
}

// -----------------------------------------------------------------------------
// RIVERPOD PROVIDERS
// -----------------------------------------------------------------------------

final timezoneServiceProvider = Provider<TimezoneService>((ref) {
  return TimezoneService();
});

class SelectedTimezoneNotifier extends Notifier<TargetTimezone> {
  @override
  TargetTimezone build() => TargetTimezone.wib;

  void setTimezone(TargetTimezone timezone) {
    state = timezone;
  }
}

final selectedTimezoneProvider =
    NotifierProvider<SelectedTimezoneNotifier, TargetTimezone>(
  SelectedTimezoneNotifier.new,
);
