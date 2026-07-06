import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';

part 'theme_event.dart';
part 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final LocalStorageRepository _storage;
  static const String _themeKey = PrefKeys.themeMode;

  ThemeBloc(this._storage) : super(const ThemeState(ThemeMode.system)) {
    on<ThemeInitialized>(_onThemeInitialized);
    on<ThemeChanged>(_onThemeChanged);

    // 监听 repo 层的主题变更通知（来自 BT Agent 等非 UI 路径）
    _themeListener = () {
      final mode = _storage.themeChangeNotifier.value;
      if (mode == null) return;
      final themeMode = switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      add(ThemeChanged(themeMode));
    };
    _storage.themeChangeNotifier.addListener(_themeListener);
  }

  late final void Function() _themeListener;

  Future<void> _onThemeInitialized(
    ThemeInitialized event,
    Emitter<ThemeState> emit,
  ) async {
    final themeIndex = _storage.getString(_themeKey);
    if (themeIndex != null) {
      final index = int.tryParse(themeIndex);
      if (index != null && index >= 0 && index < ThemeMode.values.length) {
        emit(ThemeState(ThemeMode.values[index]));
      } else {
        await _storage.setString(_themeKey, ThemeMode.system.index.toString());
        emit(const ThemeState(ThemeMode.system));
      }
    }
  }

  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<ThemeState> emit,
  ) async {
    await _storage.setString(_themeKey, event.themeMode.index.toString());
    emit(ThemeState(event.themeMode));
  }
}
