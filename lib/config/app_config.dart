class AppConfig {
  // Backend API base URL - AWS App Runner (permanent, no tunnel needed)
  static const String apiBaseUrl = 'https://evrw6qmfh7.us-east-1.awsapprunner.com/api';

  // Face match confidence threshold (0-100)
  static const double faceMatchThreshold = 90.0;

  // Location tolerance in meters
  static const double locationToleranceMeters = 200.0;

  // Camera settings
  static const double cameraAspectRatio = 4 / 3;

  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 60);
}
