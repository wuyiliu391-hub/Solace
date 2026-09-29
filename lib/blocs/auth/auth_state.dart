part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;

  /// 本次登录/启动发放的每日登录奖励（0 表示今日已领或未发）
  final int loginBonusGranted;

  const AuthAuthenticated(this.user, {this.loginBonusGranted = 0});

  @override
  List<Object?> get props => [user, loginBonusGranted];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}
