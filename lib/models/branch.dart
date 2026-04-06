class Branch {
  final String id;
  final String name;
  final String address;
  final String? adminId;
  final String? adminName;
  final bool isActive;
  final String status; // work | hold | closed
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final String workingHoursStart;
  final String workingHoursEnd;
  final int breakDurationMinutes;
  final List<String> workingDays;
  final int employeeCount;
  final DateTime? createdAt;
  final double deductionLate;
  final double deductionEarlyOut;
  final double deductionAbsent;

  static const List<String> allDays = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  static const List<String> defaultWorkingDays = ['Monday','Tuesday','Wednesday','Thursday','Friday'];

  Branch({
    required this.id,
    required this.name,
    this.address = '',
    this.adminId,
    this.adminName,
    this.isActive = true,
    this.status = 'work',
    this.validityStart,
    this.validityEnd,
    this.workingHoursStart = '09:00',
    this.workingHoursEnd = '18:00',
    this.breakDurationMinutes = 60,
    this.workingDays = defaultWorkingDays,
    this.employeeCount = 0,
    this.createdAt,
    this.deductionLate = 0,
    this.deductionEarlyOut = 0,
    this.deductionAbsent = 0,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    final rawDays = json['working_days'];
    return Branch(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String? ?? '',
      adminId: json['admin_id'] as String?,
      adminName: json['admin_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      status: json['status'] as String? ?? 'work',
      validityStart: json['validity_start'] != null
          ? DateTime.tryParse(json['validity_start'] as String)
          : null,
      validityEnd: json['validity_end'] != null
          ? DateTime.tryParse(json['validity_end'] as String)
          : null,
      workingHoursStart: json['working_hours_start'] as String? ?? '09:00',
      workingHoursEnd: json['working_hours_end'] as String? ?? '18:00',
      breakDurationMinutes: json['break_duration_minutes'] as int? ?? 60,
      workingDays: rawDays != null ? List<String>.from(rawDays as List) : defaultWorkingDays,
      employeeCount: json['employee_count'] as int? ?? 0,
      deductionLate: (json['deduction_late'] as num?)?.toDouble() ?? 0,
      deductionEarlyOut: (json['deduction_early_out'] as num?)?.toDouble() ?? 0,
      deductionAbsent: (json['deduction_absent'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'admin_id': adminId,
        'admin_name': adminName,
        'is_active': isActive,
        'status': status,
        'validity_start': validityStart?.toIso8601String(),
        'validity_end': validityEnd?.toIso8601String(),
        'working_hours_start': workingHoursStart,
        'working_hours_end': workingHoursEnd,
        'break_duration_minutes': breakDurationMinutes,
        'working_days': workingDays,
        'employee_count': employeeCount,
        'deduction_late': deductionLate,
        'deduction_early_out': deductionEarlyOut,
        'deduction_absent': deductionAbsent,
        'created_at': createdAt?.toIso8601String(),
      };

  String get statusDisplayName {
    switch (status) {
      case 'work': return 'Working';
      case 'hold': return 'On Hold';
      case 'closed': return 'Closed';
      default: return status;
    }
  }
}
