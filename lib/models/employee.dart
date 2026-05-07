import '../l10n/app_localizations.dart';

enum UserRole {
  superAdmin,
  branchAdmin,
  hr,
  employee,
}

enum EmployeeType {
  general,
  sales,
  accountant,
  warehouse,
}

class Employee {
  final String id;
  final String name;
  final String email;
  final String department;
  final String? referenceImageUrl;
  final UserRole role;
  final EmployeeType employeeType;
  final String? branchId;
  final String? branchName;
  final String? address;
  final String? phone;
  final String? position;
  final DateTime? lastOnline;
  final String? profileImageUrl;
  final double? allowedLatitude;
  final double? allowedLongitude;
  final double? allowedRadius;
  final bool isOnHold;
  final double? basicSalary;
  final bool passwordResetPending;

  Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    this.referenceImageUrl,
    this.role = UserRole.employee,
    this.employeeType = EmployeeType.general,
    this.branchId,
    this.branchName,
    this.address,
    this.phone,
    this.position,
    this.lastOnline,
    this.profileImageUrl,
    this.allowedLatitude,
    this.allowedLongitude,
    this.allowedRadius,
    this.isOnHold = false,
    this.basicSalary,
    this.passwordResetPending = false,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      department: json['department'] as String,
      referenceImageUrl: json['reference_image_url'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.employee,
      ),
      employeeType: EmployeeType.values.firstWhere(
        (e) => e.name == json['employee_type'],
        orElse: () => EmployeeType.general,
      ),
      branchId: json['branch_id'] as String?,
      branchName: json['branch_name'] as String?,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      position: json['position'] as String?,
      lastOnline: json['last_online'] != null
          ? DateTime.tryParse(json['last_online'] as String)
          : null,
      profileImageUrl: json['profile_image_url'] as String?,
      allowedLatitude: (json['allowed_latitude'] as num?)?.toDouble(),
      allowedLongitude: (json['allowed_longitude'] as num?)?.toDouble(),
      allowedRadius: (json['allowed_radius'] as num?)?.toDouble(),
      isOnHold: json['is_on_hold'] == true,
      basicSalary: (json['basic_salary'] as num?)?.toDouble(),
      passwordResetPending: json['password_reset_pending'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'department': department,
      'reference_image_url': referenceImageUrl,
      'role': role.name,
      'employee_type': employeeType.name,
      'branch_id': branchId,
      'branch_name': branchName,
      'address': address,
      'phone': phone,
      'position': position,
      'last_online': lastOnline?.toIso8601String(),
      'profile_image_url': profileImageUrl,
      'allowed_latitude': allowedLatitude,
      'allowed_longitude': allowedLongitude,
      'allowed_radius': allowedRadius,
      'is_on_hold': isOnHold,
      'basic_salary': basicSalary,
    };
  }

  String get roleDisplayName {
    switch (role) {
      case UserRole.superAdmin:
        return S.superAdminTitle;
      case UserRole.branchAdmin:
        return S.branchAdminTitle;
      case UserRole.hr:
        return S.hrTitle;
      case UserRole.employee:
        return S.employeeTitle;
    }
  }
}
