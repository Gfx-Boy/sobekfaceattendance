class DashboardStats {
  final int employeeCount;
  final int branchCount;
  final int todayAttendance;
  final int totalAttendance;
  final int pendingRequests;
  final int totalRequests;
  final int totalTasks;

  DashboardStats({
    this.employeeCount = 0,
    this.branchCount = 0,
    this.todayAttendance = 0,
    this.totalAttendance = 0,
    this.pendingRequests = 0,
    this.totalRequests = 0,
    this.totalTasks = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      employeeCount: json['employee_count'] as int? ?? 0,
      branchCount: json['branch_count'] as int? ?? 0,
      todayAttendance: json['today_attendance'] as int? ?? 0,
      totalAttendance: json['total_attendance'] as int? ?? 0,
      pendingRequests: json['pending_requests'] as int? ?? 0,
      totalRequests: json['total_requests'] as int? ?? 0,
      totalTasks: json['total_tasks'] as int? ?? 0,
    );
  }
}
