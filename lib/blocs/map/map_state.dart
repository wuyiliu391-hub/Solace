part of 'map_bloc.dart';

abstract class MapState extends Equatable {
  const MapState();
  @override
  List<Object?> get props => [];
}

class MapInitial extends MapState {}

class MapLoading extends MapState {}

class MapLoaded extends MapState {
  final LocationRecord aiLocation;
  final LocationRecord? userLocation;
  final List<LocationRecord> aiTrajectory;
  final List<LocationRecord> userTrajectory;
  final bool showAITrajectory;
  final bool showUserTrajectory;

  const MapLoaded({
    required this.aiLocation,
    this.userLocation,
    this.aiTrajectory = const [],
    this.userTrajectory = const [],
    this.showAITrajectory = true,
    this.showUserTrajectory = false,
  });

  MapLoaded copyWith({
    LocationRecord? aiLocation,
    LocationRecord? userLocation,
    List<LocationRecord>? aiTrajectory,
    List<LocationRecord>? userTrajectory,
    bool? showAITrajectory,
    bool? showUserTrajectory,
  }) {
    return MapLoaded(
      aiLocation: aiLocation ?? this.aiLocation,
      userLocation: userLocation ?? this.userLocation,
      aiTrajectory: aiTrajectory ?? this.aiTrajectory,
      userTrajectory: userTrajectory ?? this.userTrajectory,
      showAITrajectory: showAITrajectory ?? this.showAITrajectory,
      showUserTrajectory: showUserTrajectory ?? this.showUserTrajectory,
    );
  }

  @override
  List<Object?> get props => [aiLocation, userLocation, aiTrajectory, userTrajectory, showAITrajectory, showUserTrajectory];
}

class MapError extends MapState {
  final String message;
  const MapError(this.message);
  @override
  List<Object?> get props => [message];
}
