enum NotificationType {
  requestApproval,
  requestRejection,
  newRequest,
  hrNotification,
  systemAlert,
  taskAssignment,
  attendanceAlert,
  payslipAvailable,
  evaluationResult,
  general,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final String? relatedId;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.relatedId,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        body: body,
        type: type,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        relatedId: relatedId,
      );

  /// The backend stores notification [type] as snake_case strings (e.g.
  /// `task_assigned`, `payslip_created`) that do NOT match the Dart enum
  /// names, so a naive `.name` lookup always fell through to [general] —
  /// breaking tap-navigation and the per-type icon/colour. Map the known
  /// backend types here, then fall back to enum-name matching for safety.
  static NotificationType _parseType(String? raw) {
    switch (raw) {
      case 'task_assigned':
      case 'task_status':
        return NotificationType.taskAssignment;
      case 'payslip_created':
        return NotificationType.payslipAvailable;
      case 'appraisal_started':
      case 'appraisal_submitted':
        return NotificationType.evaluationResult;
      case 'new_request':
        return NotificationType.newRequest;
      case 'request_review':
      case 'request_approved':
        return NotificationType.requestApproval;
      case 'request_rejected':
        return NotificationType.requestRejection;
      case 'attendance':
      case 'attendance_alert':
        return NotificationType.attendanceAlert;
      case 'hr_notification':
      case 'employee_created':
      case 'employee_deleted':
      case 'employee_held':
      case 'employee_unheld':
        return NotificationType.hrNotification;
      case 'system_alert':
        return NotificationType.systemAlert;
    }
    return NotificationType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NotificationType.general,
    );
  }

  /// Extracts the related entity id (task/request/payslip/cycle/appraisal)
  /// from either the legacy `related_id` field or the backend `data` object.
  static String? _parseRelatedId(Map<String, dynamic> json) {
    if (json['related_id'] != null) return json['related_id'].toString();
    final data = json['data'];
    if (data is Map) {
      for (final key in const [
        'task_id',
        'request_id',
        'payslip_id',
        'cycle_id',
        'appraisal_id',
      ]) {
        if (data[key] != null) return data[key].toString();
      }
    }
    return null;
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String? ?? '',
      type: _parseType(json['type'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      isRead: json['is_read'] as bool? ?? false,
      relatedId: _parseRelatedId(json),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type.name,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'related_id': relatedId,
    };
  }
}
