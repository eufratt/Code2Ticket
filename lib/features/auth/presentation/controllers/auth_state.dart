import '../../domain/models/user_model.dart';

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  final String? message;
  const AuthLoading([this.message]);
}

class Authenticated extends AuthState {
  final UserModel user;
  final bool isBiometricRequired;

  const Authenticated({
    required this.user,
    this.isBiometricRequired = false,
  });

  Authenticated copyWith({
    UserModel? user,
    bool? isBiometricRequired,
  }) {
    return Authenticated(
      user: user ?? this.user,
      isBiometricRequired: isBiometricRequired ?? this.isBiometricRequired,
    );
  }
}

class Unauthenticated extends AuthState {
  final String? message;
  const Unauthenticated([this.message]);
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}
