class AppConfig {
  // Unified Backend API base URL - Inukta SaaS (Laravel / MySQL)
  // Both Mobile Attendance & SaaS features now use the same authoritative database.
  static const String apiBaseUrl = 'https://app.inukta.com/api';

  // The web SaaS (Laravel/Sanctum). Messenger, CRM and shifts read from here so
  // the phone and the web show the same data - review points 12, 18, 20 and 25.
  // Employees sign in with the same credentials; their password hash was
  // migrated across, so one password works on both.
  static const String workspaceApiBaseUrl = 'https://app.inukta.com/api';

  /// Workspace features are hidden until the employee has a session on the web
  /// side, so a failure there can never block attendance.
  static const Duration workspaceTimeout = Duration(seconds: 20);

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
