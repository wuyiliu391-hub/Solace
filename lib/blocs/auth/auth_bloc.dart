import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/user.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LocalStorageRepository _storage;

  AuthBloc(this._storage) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onAuthLoginRequested);
    on<AuthRegisterRequested>(_onAuthRegisterRequested);
    on<AuthPasswordResetRequested>(_onAuthPasswordResetRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
    on<AuthUserUpdated>(_onAuthUserUpdated);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final hasLoggedOut = _storage.getBool(PrefKeys.loggedOut) ?? false;
      final userId = _storage.getString(PrefKeys.currentUserId);
      if (userId != null) {
        final user = await _storage.getUser(userId);
        if (user != null) {
          await _storage.remove(PrefKeys.loggedOut);
          emit(AuthAuthenticated(user));
          return;
        }
      }
      // 如果曾主动登出过，不再自动注册，显示登录页
      if (hasLoggedOut) {
        emit(AuthUnauthenticated());
        return;
      }
      // 首次启动：自动创建本地用户
      final now = DateTime.now();
      final user = User(
        id: 'local_user',
        nickname: 'Solace用户',
        createdAt: now,
        lastLoginAt: now,
      );
      await _storage.saveUser(user);
      await _storage.setString(PrefKeys.currentUserId, 'local_user');
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onAuthLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final qq = event.qqNumber.trim();
      final storedHash = _storage.getString(PrefKeys.pwHash(qq));
      if (storedHash == null) {
        emit(AuthError('该QQ号未注册，请先注册'));
        return;
      }
      final inputHash = sha256.convert(utf8.encode(event.password)).toString();
      if (storedHash != inputHash) {
        emit(AuthError('密码错误'));
        return;
      }
      final now = DateTime.now();
      User? existing;
      try {
        existing = await _storage.getUser(qq);
      } catch (e) {
        debugPrint('Error: $e');
      }
      final user = existing?.copyWith(lastLoginAt: now) ??
          User(
            id: qq,
            nickname: 'QQ用户${qq.substring(qq.length > 4 ? qq.length - 4 : 0)}',
            avatarUrl: 'https://q1.qlogo.cn/g?b=qq&nk=$qq&s=640',
            createdAt: now,
            lastLoginAt: now,
          );
      await _storage.saveUser(user);
      await _storage.setString(PrefKeys.currentUserId, qq);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onAuthRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final qq = event.qqNumber.trim();
      final existingHash = _storage.getString(PrefKeys.pwHash(qq));
      if (existingHash != null) {
        emit(AuthError('该QQ号已注册，请登录'));
        return;
      }
      final hash = sha256.convert(utf8.encode(event.password)).toString();
      await _storage.setString(PrefKeys.pwHash(qq), hash);
      final now = DateTime.now();
      final qqAvatar = 'https://q1.qlogo.cn/g?b=qq&nk=$qq&s=640';
      final nickname = 'QQ用户${qq.substring(qq.length > 4 ? qq.length - 4 : 0)}';
      final user = User(
        id: qq,
        nickname: nickname,
        avatarUrl: qqAvatar,
        createdAt: now,
        lastLoginAt: now,
      );
      await _storage.saveUser(user);
      await _storage.setString(PrefKeys.currentUserId, qq);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onAuthPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final qq = event.qqNumber.trim();
      final hash = sha256.convert(utf8.encode(event.newPassword)).toString();
      await _storage.setString(PrefKeys.pwHash(qq), hash);
      final now = DateTime.now();
      User? existing;
      try {
        existing = await _storage.getUser(qq);
      } catch (e) {
        debugPrint('Error: $e');
      }
      final user = existing?.copyWith(lastLoginAt: now) ??
          User(
            id: qq,
            nickname: 'QQ用户${qq.substring(qq.length > 4 ? qq.length - 4 : 0)}',
            avatarUrl: 'https://q1.qlogo.cn/g?b=qq&nk=$qq&s=640',
            createdAt: now,
            lastLoginAt: now,
          );
      await _storage.saveUser(user);
      await _storage.setString(PrefKeys.currentUserId, qq);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _storage.remove(PrefKeys.currentUserId);
      await _storage.setBool(PrefKeys.loggedOut, true);
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onAuthUserUpdated(
    AuthUserUpdated event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _storage.saveUser(event.user);
      emit(AuthAuthenticated(event.user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }
}
