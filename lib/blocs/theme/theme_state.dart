part of 'theme_bloc.dart';

class ThemeState extends Equatable {
  final ThemeMode themeMode;
  final VisualStyle visualStyle;

  const ThemeState(this.themeMode, [this.visualStyle = VisualStyle.classic]);

  bool get isWeChat => visualStyle == VisualStyle.wechat;

  @override
  List<Object?> get props => [themeMode, visualStyle];
}
