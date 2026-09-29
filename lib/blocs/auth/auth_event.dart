part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthLoginRequested extends AuthEvent {
  final String qqNumber;
  final String password;

  const AuthLoginRequested({required this.qqNumber, required this.password});

  @override
  List<Object?> get props => [qqNumber, password];
}

class AuthRegisterRequested extends AuthEvent {
  final String qqNumber;
  final String password;

  const AuthRegisterRequested({required this.qqNumber, required this.password});

  @override
  List<Object?> get props => [qqNumber, password];
}

class AuthPasswordResetRequested extends AuthEvent {
  final String qqNumber;
  final String newPassword;

  const AuthPasswordResetRequested({required this.qqNumber, required this.newPassword});

  @override
  List<Object?> get props => [qqNumber, newPassword];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthUserUpdated extends AuthEvent {
  final User user;

  const AuthUserUpdated(this.user);

  @override
  List<Object?> get props => [user];
}
