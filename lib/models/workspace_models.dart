/// Models for the web SaaS (Laravel) API: messenger, CRM and shifts.
///
/// Attendance models stay where they are - these only cover the features the
/// client asked to mirror from the web app (review points 18, 20 and 25).
///
/// Every parser is deliberately forgiving: the web side is a separate codebase
/// and a missing or renamed field should leave a row looking empty, never crash
/// a screen an employee is standing in front of.
library;

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _asDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString();
  return s.isEmpty ? fallback : s;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  // Timestamps arrive as ISO-8601 UTC; show them in the device's zone.
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// Someone the employee can message.
class WorkspaceContact {
  final int id;
  final String name;
  final String email;
  final String type;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final int unreadCount;

  const WorkspaceContact({
    required this.id,
    required this.name,
    required this.email,
    required this.type,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeenAt,
    this.unreadCount = 0,
  });

  factory WorkspaceContact.fromJson(Map<String, dynamic> json) {
    return WorkspaceContact(
      id: _asInt(json['id']),
      name: _asString(json['name'], _asString(json['email'], 'Unknown')),
      email: _asString(json['email']),
      type: _asString(json['type'], 'user'),
      avatarUrl: (json['avatar'] as String?)?.isEmpty ?? true
          ? null
          : json['avatar'] as String,
      isOnline: _asBool(json['is_online']),
      lastSeenAt: _asDate(json['last_seen_at']),
      unreadCount: _asInt(json['unread_count']),
    );
  }

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

/// One message in a conversation.
class WorkspaceMessage {
  final int id;
  final int fromId;
  final int toId;
  final String body;
  final String? attachmentUrl;
  final bool seen;
  final bool isMine;
  final DateTime? createdAt;

  const WorkspaceMessage({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.body,
    this.attachmentUrl,
    this.seen = false,
    this.isMine = false,
    this.createdAt,
  });

  factory WorkspaceMessage.fromJson(Map<String, dynamic> json) {
    return WorkspaceMessage(
      id: _asInt(json['id']),
      fromId: _asInt(json['from_id']),
      toId: _asInt(json['to_id']),
      body: _asString(json['body']),
      attachmentUrl: (json['attachment'] as String?)?.isEmpty ?? true
          ? null
          : json['attachment'] as String,
      seen: _asBool(json['seen']),
      isMine: _asBool(json['is_mine']),
      createdAt: _asDate(json['created_at']),
    );
  }
}

/// A CRM lead.
class WorkspaceLead {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String subject;
  final int stageId;
  final String stageName;
  final DateTime? createdAt;

  const WorkspaceLead({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.subject = '',
    this.stageId = 0,
    this.stageName = '',
    this.createdAt,
  });

  factory WorkspaceLead.fromJson(Map<String, dynamic> json, {String stage = ''}) {
    return WorkspaceLead(
      id: _asInt(json['id']),
      name: _asString(json['name'], 'Untitled lead'),
      email: _asString(json['email']),
      phone: _asString(json['phone']),
      subject: _asString(json['subject']),
      stageId: _asInt(json['stage_id']),
      stageName: stage.isNotEmpty ? stage : _asString(json['stage_name']),
      createdAt: _asDate(json['created_at']),
    );
  }
}

/// A CRM deal.
class WorkspaceDeal {
  final int id;
  final String name;
  final double price;
  final String phone;
  final String status;
  final int stageId;
  final int pipelineId;
  final bool isActive;
  final String stageName;
  final DateTime? createdAt;

  const WorkspaceDeal({
    required this.id,
    required this.name,
    this.price = 0,
    this.phone = '',
    this.status = '',
    this.stageId = 0,
    this.pipelineId = 0,
    this.isActive = true,
    this.stageName = '',
    this.createdAt,
  });

  factory WorkspaceDeal.fromJson(Map<String, dynamic> json, {String stage = ''}) {
    return WorkspaceDeal(
      id: _asInt(json['id']),
      name: _asString(json['name'], 'Untitled deal'),
      price: _asDouble(json['price']),
      phone: _asString(json['phone']),
      status: _asString(json['status']),
      stageId: _asInt(json['stage_id']),
      pipelineId: _asInt(json['pipeline_id']),
      isActive: json['is_active'] == null ? true : _asBool(json['is_active']),
      stageName: stage,
      createdAt: _asDate(json['created_at']),
    );
  }
}

/// One column of the leads/deals board.
class WorkspaceStage<T> {
  final int id;
  final String name;
  final List<T> items;

  const WorkspaceStage({
    required this.id,
    required this.name,
    required this.items,
  });
}

/// A shift as managed on the web (review point 25).
class WorkspaceShift {
  final int id;
  final String name;
  final String startTime;
  final String endTime;
  final String? breakStartTime;
  final String? breakEndTime;
  final bool isNightShift;
  final int breakMinutes;
  final int totalMinutes;
  final int workingMinutes;
  final int employeeCount;

  const WorkspaceShift({
    required this.id,
    required this.name,
    this.startTime = '',
    this.endTime = '',
    this.breakStartTime,
    this.breakEndTime,
    this.isNightShift = false,
    this.breakMinutes = 0,
    this.totalMinutes = 0,
    this.workingMinutes = 0,
    this.employeeCount = 0,
  });

  factory WorkspaceShift.fromJson(Map<String, dynamic> json) {
    return WorkspaceShift(
      id: _asInt(json['id']),
      name: _asString(json['name'], 'Shift'),
      startTime: _asString(json['start_time']),
      endTime: _asString(json['end_time']),
      breakStartTime: json['break_start_time'] as String?,
      breakEndTime: json['break_end_time'] as String?,
      isNightShift: _asBool(json['is_night_shift']),
      breakMinutes: _asInt(json['break_minutes']),
      totalMinutes: _asInt(json['total_minutes']),
      workingMinutes: _asInt(json['working_minutes']),
      employeeCount: _asInt(json['employee_count']),
    );
  }

  /// "8h 30m", from the minutes the server already worked out (it handles the
  /// night-shift rollover, so we must not recompute it here).
  String get workingLabel {
    final h = workingMinutes ~/ 60;
    final m = workingMinutes % 60;
    if (h == 0) return '${m}m';
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
