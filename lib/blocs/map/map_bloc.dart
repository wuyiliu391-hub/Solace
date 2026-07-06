import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/location_record.dart';
import '../../services/location_service.dart';
import '../../services/ai_location_engine.dart';

part 'map_event.dart';
part 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  final _uuid = const Uuid();
  Timer? _aiMoveTimer;
  LocationRecord? _aiCurrentLocation;
  LocationRecord? _userCurrentLocation;
  final List<LocationRecord> _aiTrajectory = [];
  final List<LocationRecord> _userTrajectory = [];
  String? _currentAiId;
  StreamSubscription<LocationRecord>? _userLocationSub;

  MapBloc() : super(MapInitial()) {
    on<MapInitialize>(_onInitialize);
    on<MapRefreshAILocation>(_onRefreshAILocation);
    on<MapUpdateUserLocation>(_onUpdateUserLocation);
    on<MapSetUserLocationManually>(_onSetUserLocationManually);
    on<MapSetAILocationManually>(_onSetAILocationManually);
    on<MapLoadTrajectory>(_onLoadTrajectory);
    on<MapToggleTrajectory>(_onToggleTrajectory);
    on<MapStartUserTracking>(_onStartUserTracking);
    on<MapStopUserTracking>(_onStopUserTracking);
  }

  Future<void> _onInitialize(
      MapInitialize event, Emitter<MapState> emit) async {
    try {
      _currentAiId = event.aiId;
      AILocationEngine.setBaseLocation(event.baseLatitude, event.baseLongitude);

      final trajectory = AILocationEngine.generateTodayTrajectory(event.aiId);
      _aiTrajectory.clear();
      _aiTrajectory.addAll(trajectory);

      _aiCurrentLocation = AILocationEngine.generateCurrentLocation(event.aiId);

      _startAIMovement(event.aiId);

      emit(MapLoaded(
        aiLocation: _aiCurrentLocation!,
        userLocation: _userCurrentLocation,
        aiTrajectory: List.from(_aiTrajectory),
        userTrajectory: List.from(_userTrajectory),
        showAITrajectory: true,
        showUserTrajectory: false,
      ));

      try {
        final userLoc = await LocationService.getCurrentLocation(event.userId)
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
        if (userLoc != null) {
          _userCurrentLocation = userLoc;
          _userTrajectory.add(userLoc);
          if (state is MapLoaded) {
            final s = state as MapLoaded;
            emit(s.copyWith(
              userLocation: userLoc,
              userTrajectory: List.from(_userTrajectory),
            ));
          }
        }
      } catch (e) {
        debugPrint('Error: $e');
      }
    } catch (e) {
      emit(MapError('地图初始化失败: $e'));
    }
  }

  void _startAIMovement(String aiId) {
    _aiMoveTimer?.cancel();
    _aiMoveTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      add(MapRefreshAILocation(aiId));
    });
  }

  Future<void> _onRefreshAILocation(
      MapRefreshAILocation event, Emitter<MapState> emit) async {
    _aiCurrentLocation = AILocationEngine.generateCurrentLocation(event.aiId);

    final lastTraj = _aiTrajectory.isNotEmpty ? _aiTrajectory.last : null;
    if (lastTraj == null ||
        _aiCurrentLocation!.placeName != lastTraj.placeName ||
        _aiCurrentLocation!.timestamp.difference(lastTraj.timestamp).inMinutes >
            30) {
      _aiTrajectory.add(_aiCurrentLocation!);
    }

    if (state is MapLoaded) {
      final s = state as MapLoaded;
      emit(s.copyWith(
        aiLocation: _aiCurrentLocation,
        aiTrajectory: List.from(_aiTrajectory),
      ));
    }
  }

  Future<void> _onUpdateUserLocation(
      MapUpdateUserLocation event, Emitter<MapState> emit) async {
    try {
      final userLoc = await LocationService.getCurrentLocation(event.userId)
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (userLoc != null) {
        _userCurrentLocation = userLoc;
        _userTrajectory.add(userLoc);
        if (state is MapLoaded) {
          final s = state as MapLoaded;
          emit(s.copyWith(
            userLocation: userLoc,
            userTrajectory: List.from(_userTrajectory),
          ));
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _onSetUserLocationManually(
      MapSetUserLocationManually event, Emitter<MapState> emit) {
    _userCurrentLocation = LocationService.createManualUserLocation(
      event.userId,
      event.latitude,
      event.longitude,
      event.placeName,
    );
    _userTrajectory.add(_userCurrentLocation!);
    if (state is MapLoaded) {
      final s = state as MapLoaded;
      emit(s.copyWith(
        userLocation: _userCurrentLocation,
        userTrajectory: List.from(_userTrajectory),
      ));
    }
  }

  void _onSetAILocationManually(
      MapSetAILocationManually event, Emitter<MapState> emit) {
    if (_currentAiId == null) return;
    _aiCurrentLocation = AILocationEngine.generateManualLocation(
      _currentAiId!,
      event.placeName,
      event.placeType,
      event.activity,
    );
    _aiTrajectory.add(_aiCurrentLocation!);
    if (state is MapLoaded) {
      final s = state as MapLoaded;
      emit(s.copyWith(
        aiLocation: _aiCurrentLocation,
        aiTrajectory: List.from(_aiTrajectory),
      ));
    }
  }

  void _onLoadTrajectory(MapLoadTrajectory event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      final s = state as MapLoaded;
      emit(s.copyWith(
        aiTrajectory: List.from(_aiTrajectory),
        userTrajectory: List.from(_userTrajectory),
      ));
    }
  }

  void _onToggleTrajectory(MapToggleTrajectory event, Emitter<MapState> emit) {
    if (state is MapLoaded) {
      final s = state as MapLoaded;
      if (event.forAI) {
        emit(s.copyWith(showAITrajectory: !s.showAITrajectory));
      } else {
        emit(s.copyWith(showUserTrajectory: !s.showUserTrajectory));
      }
    }
  }

  Future<void> _onStartUserTracking(
      MapStartUserTracking event, Emitter<MapState> emit) async {
    await _userLocationSub?.cancel();
    try {
      _userLocationSub = LocationService.onLocationChanged(event.userId).listen(
        (record) {
          _userCurrentLocation = record;
          _userTrajectory.add(record);
          if (state is MapLoaded) {
            final s = state as MapLoaded;
            emit(s.copyWith(
              userLocation: record,
              userTrajectory: List.from(_userTrajectory),
            ));
          }
        },
        onError: (_) {},
      );
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<void> _onStopUserTracking(
      MapStopUserTracking event, Emitter<MapState> emit) async {
    await _userLocationSub?.cancel();
    _userLocationSub = null;
  }

  @override
  Future<void> close() async {
    _aiMoveTimer?.cancel();
    await _userLocationSub?.cancel();
    return super.close();
  }
}
