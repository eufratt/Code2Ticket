import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/services/notification_service.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../domain/models/redeem_result_model.dart';
import '../../domain/repositories/input_code_repository.dart';
import '../datasources/input_code_remote_data_source.dart';

class InputCodeRepositoryImpl implements InputCodeRepository {
  final InputCodeRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;
  final NotificationService _notificationService;

  InputCodeRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    NotificationService? notificationService,
  }) : _notificationService = notificationService ?? NotificationService();

  @override
  Future<RedeemResultModel> redeemCode(
    String code, {
    double? latitude,
    double? longitude,
  }) async {
    // 1. Retrieve active session token
    final sessionToken = await localDataSource.getSessionToken();
    if (sessionToken == null || sessionToken.isEmpty) {
      return const RedeemResultModel(
        success: false,
        message: 'Sesi Tidak Valid',
        error: 'Sesi login Anda tidak ditemukan atau telah kedaluwarsa. Silakan login kembali.',
      );
    }

    // 2. Fetch GPS coordinates if not already supplied
    double? userLat = latitude;
    double? userLng = longitude;

    if (userLat == null || userLng == null) {
      final loc = await _tryGetCurrentLocation();
      if (loc != null) {
        userLat = loc.latitude;
        userLng = loc.longitude;
      }
    }

    // 3. Call atomic redeem_code RPC function in Supabase
    final result = await remoteDataSource.redeemCode(
      sessionToken: sessionToken,
      code: code.trim(),
      latitude: userLat,
      longitude: userLng,
    );

    // 4. Trigger system push notification upon successful claim
    if (result.success && result.ticket != null) {
      await _notificationService.showTicketCreatedNotification(
        ticketNumber: result.ticket!.ticketNumber,
        giveawayTitle: result.ticket!.giveawayTitle,
      );
    }

    return result;
  }

  Future<Position?> _tryGetCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied.');
        return null;
      }

      // Try quick current position or fallback to last known
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 4),
          ),
        );
      } catch (_) {
        return await Geolocator.getLastKnownPosition();
      }
    } catch (e) {
      debugPrint('Error getting GPS location: $e');
      return null;
    }
  }
}
