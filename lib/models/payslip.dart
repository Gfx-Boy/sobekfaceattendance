class Payslip {
  final String id;
  final String employeeId;
  final String employeeName;
  final String period;
  final double basicSalary;
  final double bonuses;
  final double deductions;
  final double overtimePay;
  final double netSalary;
  final String? paymentDate;
  final String notes;
  final String? branchId;
  final DateTime createdAt;

  Payslip({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.period,
    required this.basicSalary,
    this.bonuses = 0,
    this.deductions = 0,
    this.overtimePay = 0,
    required this.netSalary,
    this.paymentDate,
    this.notes = '',
    this.branchId,
    required this.createdAt,
  });

  factory Payslip.fromJson(Map<String, dynamic> json) {
    return Payslip(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String? ?? '',
      period: json['period'] as String,
      basicSalary: (json['basic_salary'] as num?)?.toDouble() ?? 0,
      bonuses: (json['bonuses'] as num?)?.toDouble() ?? 0,
      deductions: (json['deductions'] as num?)?.toDouble() ?? 0,
      overtimePay: (json['overtime_pay'] as num?)?.toDouble() ?? 0,
      netSalary: (json['net_salary'] as num?)?.toDouble() ?? 0,
      paymentDate: json['payment_date'] as String?,
      notes: json['notes'] as String? ?? '',
      branchId: json['branch_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'period': period,
        'basic_salary': basicSalary,
        'bonuses': bonuses,
        'deductions': deductions,
        'overtime_pay': overtimePay,
        'net_salary': netSalary,
        'payment_date': paymentDate,
        'notes': notes,
        'branch_id': branchId,
        'created_at': createdAt.toIso8601String(),
      };
}
