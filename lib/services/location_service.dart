import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/location_record.dart';

class LocationService {
  static Future<bool> checkPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }
      if (permission == LocationPermission.deniedForever) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<LocationRecord?> getCurrentLocation(String userId) async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) return null;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      return LocationRecord(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        ownerId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        isUser: true,
        placeType: 'user',
      );
    } catch (_) {
      return null;
    }
  }

  static Stream<LocationRecord> onLocationChanged(String userId) async* {
    final hasPermission = await checkPermission();
    if (!hasPermission) return;
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map((position) => LocationRecord(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      ownerId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: DateTime.now(),
      isUser: true,
      placeType: 'user',
    ));
  }

  static LocationRecord createManualUserLocation(
    String userId,
    double lat,
    double lng,
    String? placeName,
  ) {
    return LocationRecord(
      id: 'user_manual_${DateTime.now().millisecondsSinceEpoch}',
      ownerId: userId,
      latitude: lat,
      longitude: lng,
      placeName: placeName,
      timestamp: DateTime.now(),
      isUser: true,
      placeType: 'user',
    );
  }
}
