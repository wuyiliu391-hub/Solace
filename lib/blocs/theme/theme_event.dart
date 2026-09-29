part of 'theme_bloc.dart';

abstract class ThemeEvent extends Equatable {
  const ThemeEvent();

  @override
  List<Object?> get props => [];
}

class ThemeInitialized extends ThemeEvent {
  const ThemeInitialized();
}

class ThemeChanged extends ThemeEvent {
  final ThemeMode themeMode;

  const ThemeChanged(this.themeMode);

  @override
  List<Object?> get props => [themeMode];
}

class VisualStyleChanged extends ThemeEvent {
  final VisualStyle visualStyle;

  const VisualStyleChanged(this.visualStyle);

  @override
  List<Object?> get props => [visualStyle];
}
