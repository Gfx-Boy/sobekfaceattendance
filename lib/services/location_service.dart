import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    // Check if GPS/location service is enabled on the device
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationServiceException(
        'Location services are turned off on your device. Please enable GPS and try again.',
        needsServiceEnable: true,
      );
    }

    // Check / request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationServiceException(
        'Location permission was denied. Please allow location access for attendance.',
        needsPermission: true,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationServiceException(
        'Location permission is permanently denied. Open Settings to allow location access.',
        needsSettings: true,
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }
}

class LocationServiceException implements Exception {
  final String message;
  final bool needsSettings;    // open app settings
  final bool needsPermission;  // request permission again
  final bool needsServiceEnable; // open location/GPS settings

  const LocationServiceException(
    this.message, {
    this.needsSettings = false,
    this.needsPermission = false,
    this.needsServiceEnable = false,
  });

  @override
  String toString() => message;
}
