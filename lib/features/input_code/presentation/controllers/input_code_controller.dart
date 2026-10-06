import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/supabase_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/input_code_remote_data_source.dart';
import '../../data/repositories/input_code_repository_impl.dart';
import '../../domain/repositories/input_code_repository.dart';
import 'input_code_state.dart';

final inputCodeRemoteDataSourceProvider =
    Provider<InputCodeRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return InputCodeRemoteDataSource(supabase);
});

final inputCodeRepositoryProvider = Provider<InputCodeRepository>((ref) {
  final remote = ref.watch(inputCodeRemoteDataSourceProvider);
  final local = ref.watch(authLocalDataSourceProvider);
  return InputCodeRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
  );
});

final inputCodeControllerProvider =
    NotifierProvider<InputCodeController, InputCodeState>(
  InputCodeController.new,
);

class InputCodeController extends Notifier<InputCodeState> {
  late final InputCodeRepository _repository;

  @override
  InputCodeState build() {
    _repository = ref.watch(inputCodeRepositoryProvider);
    return const InputCodeInitial();
  }

  /// Submits the promo / participation code for validation and ticket creation.
  Future<bool> redeemCode(
    String code, {
    double? latitude,
    double? longitude,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      state = const InputCodeError('Harap masukkan kode partisipasi terlebih dahulu.');
      return false;
    }

    state = const InputCodeLoading('Memvalidasi kode & memeriksa tiket...');

    try {
      final result = await _repository.redeemCode(
        cleanCode,
        latitude: latitude,
        longitude: longitude,
      );

      if (result.success && result.ticket != null) {
        state = InputCodeSuccess(result);
        return true;
      } else {
        final errorMsg = result.error ?? result.message;
        state = InputCodeError(errorMsg);
        return false;
      }
    } catch (e) {
      state = InputCodeError('Terjadi kesalahan saat memproses kode: $e');
      return false;
    }
  }

  /// Resets state back to initial so the user can redeem another code.
  void reset() {
    state = const InputCodeInitial();
  }

  /// Clears any error state back to initial.
  void clearError() {
    if (state is InputCodeError) {
      state = const InputCodeInitial();
    }
  }
}
