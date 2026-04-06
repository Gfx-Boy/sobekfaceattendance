import 'employee.dart';

class AuthSession {
  final Employee employee;
  final String? accessToken;
  final String? refreshToken;
  final int? expiresInSeconds;
  final int? refreshExpiresInSeconds;

  const AuthSession({
    required this.employee,
    this.accessToken,
    this.refreshToken,
    this.expiresInSeconds,
    this.refreshExpiresInSeconds,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final employeeData =
        json['employee'] is Map<String, dynamic>
            ? json['employee'] as Map<String, dynamic>
            : json['employee'] is Map
                ? Map<String, dynamic>.from(json['employee'] as Map)
                : json;

    return AuthSession(
      employee: Employee.fromJson(employeeData),
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
      expiresInSeconds: (json['expires_in'] as num?)?.toInt(),
      refreshExpiresInSeconds:
          (json['refresh_expires_in'] as num?)?.toInt(),
    );
  }
}
