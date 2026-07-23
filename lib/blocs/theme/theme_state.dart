part of 'theme_bloc.dart';

class ThemeState extends Equatable {
  final ThemeMode themeMode;
  final VisualStyle visualStyle;

  const ThemeState(this.themeMode, [this.visualStyle = VisualStyle.classic]);

  bool get isModernist => visualStyle == VisualStyle.modernist;

  @override
  List<Object?> get props => [themeMode, visualStyle];
}
