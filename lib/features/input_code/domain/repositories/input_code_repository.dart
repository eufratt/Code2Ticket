import '../models/redeem_result_model.dart';

abstract class InputCodeRepository {
  /// Validates and redeems a promotional or participation code.
  /// Calls the atomic database RPC `redeem_code` with current user session
  /// and optional GPS coordinates.
  Future<RedeemResultModel> redeemCode(
    String code, {
    double? latitude,
    double? longitude,
  });
}
