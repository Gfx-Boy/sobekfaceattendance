enum RequestCategory {
  it,
  hr,
}

enum RequestType {
  // IT Requests
  emailAndUserAccount,
  accessRight,
  equipment,
  applications,
  // HR Requests
  businessMission,
  permission,
  vacation,
  leave,
  leavePermission,
  passwordChange,
  other,
}

enum RequestStatus {
  pending,
  approved,
  rejected,
  forwarded,
}

class AppRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String? employeeEmail;
  final String? branchName;
  final RequestCategory category;
  final RequestType type;
  final RequestStatus status;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? comment;
  final String? reviewedBy;
  final DateTime? reviewedAt;

  AppRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.employeeEmail,
    this.branchName,
    required this.category,
    required this.type,
    required this.status,
    required this.title,
    required this.description,
    required this.createdAt,
    this.startDate,
    this.endDate,
    this.comment,
    this.reviewedBy,
    this.reviewedAt,
  });

  factory AppRequest.fromJson(Map<String, dynamic> json) {
    return AppRequest(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String,
      employeeEmail: json['employee_email'] as String?,
      branchName: json['branch_name'] as String?,
      category: RequestCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => RequestCategory.hr,
      ),
      type: RequestType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RequestType.other,
      ),
      status: RequestStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RequestStatus.pending,
      ),
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'] as String)
          : null,
      comment: json['comment'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'category': category.name,
      'type': type.name,
      'status': status.name,
      'title': title,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'comment': comment,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
    };
  }

  String get typeDisplayName {
    switch (type) {
      case RequestType.emailAndUserAccount:
        return 'Email & User Account';
      case RequestType.accessRight:
        return 'Access Right';
      case RequestType.equipment:
        return 'Equipment';
      case RequestType.applications:
        return 'Applications';
      case RequestType.businessMission:
        return 'Business Mission';
      case RequestType.permission:
        return 'Permission';
      case RequestType.vacation:
        return 'Vacation';
      case RequestType.leave:
        return 'Leave';
      case RequestType.leavePermission:
        return 'Leave Permission';
      case RequestType.passwordChange:
        return 'Password Change';
      case RequestType.other:
        return 'Other';
    }
  }
}
