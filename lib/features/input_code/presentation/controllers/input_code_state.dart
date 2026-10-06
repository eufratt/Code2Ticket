import '../../domain/models/redeem_result_model.dart';

sealed class InputCodeState {
  const InputCodeState();
}

class InputCodeInitial extends InputCodeState {
  const InputCodeInitial();
}

class InputCodeLoading extends InputCodeState {
  final String message;
  const InputCodeLoading([this.message = 'Memvalidasi kode...']);
}

class InputCodeSuccess extends InputCodeState {
  final RedeemResultModel result;
  const InputCodeSuccess(this.result);
}

class InputCodeError extends InputCodeState {
  final String message;
  const InputCodeError(this.message);
}
