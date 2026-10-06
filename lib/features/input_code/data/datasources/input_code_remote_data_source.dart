import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/redeem_result_model.dart';

class InputCodeRemoteDataSource {
  final SupabaseClient _supabase;

  const InputCodeRemoteDataSource(this._supabase);

  Future<RedeemResultModel> redeemCode({
    required String sessionToken,
    required String code,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await _supabase.rpc(
        'redeem_code',
        params: {
          'p_session_token': sessionToken,
          'p_code': code,
          'p_user_lat': latitude,
          'p_user_lng': longitude,
        },
      );

      if (response == null) {
        return const RedeemResultModel(
          success: false,
          message: 'Gagal memproses kode',
          error: 'Respon server kosong.',
        );
      }

      Map<String, dynamic> data;
      if (response is Map) {
        data = Map<String, dynamic>.from(response);
      } else if (response is String) {
        data = jsonDecode(response) as Map<String, dynamic>;
      } else {
        return const RedeemResultModel(
          success: false,
          message: 'Format respon tidak valid',
          error: 'Format data dari server tidak dikenali.',
        );
      }

      return RedeemResultModel.fromJson(data);
    } on PostgrestException catch (e) {
      return RedeemResultModel(
        success: false,
        message: 'Gagal memvalidasi kode',
        error: e.message,
      );
    } catch (e) {
      return RedeemResultModel(
        success: false,
        message: 'Terjadi kesalahan sistem',
        error: e.toString(),
      );
    }
  }
}
