part of 'map_bloc.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();
  @override
  List<Object?> get props => [];
}

class MapInitialize extends MapEvent {
  final String userId;
  final String aiId;
  final double baseLatitude;
  final double baseLongitude;
  const MapInitialize({required this.userId, required this.aiId, required this.baseLatitude, required this.baseLongitude});
  @override
  List<Object?> get props => [userId, aiId, baseLatitude, baseLongitude];
}

class MapRefreshAILocation extends MapEvent {
  final String aiId;
  const MapRefreshAILocation(this.aiId);
  @override
  List<Object?> get props => [aiId];
}

class MapUpdateUserLocation extends MapEvent {
  final String userId;
  const MapUpdateUserLocation(this.userId);
  @override
  List<Object?> get props => [userId];
}

class MapSetUserLocationManually extends MapEvent {
  final String userId;
  final double latitude;
  final double longitude;
  final String? placeName;
  const MapSetUserLocationManually({required this.userId, required this.latitude, required this.longitude, this.placeName});
  @override
  List<Object?> get props => [userId, latitude, longitude, placeName];
}

class MapSetAILocationManually extends MapEvent {
  final String placeName;
  final String placeType;
  final String activity;
  const MapSetAILocationManually({required this.placeName, required this.placeType, required this.activity});
  @override
  List<Object?> get props => [placeName, placeType, activity];
}

class MapLoadTrajectory extends MapEvent {
  const MapLoadTrajectory();
}

class MapToggleTrajectory extends MapEvent {
  final bool forAI;
  const MapToggleTrajectory(this.forAI);
  @override
  List<Object?> get props => [forAI];
}

class MapStartUserTracking extends MapEvent {
  final String userId;
  const MapStartUserTracking(this.userId);
  @override
  List<Object?> get props => [userId];
}

class MapStopUserTracking extends MapEvent {
  const MapStopUserTracking();
}
