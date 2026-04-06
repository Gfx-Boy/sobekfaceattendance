class WorkingHours {
  final String start;
  final String end;

  WorkingHours({this.start = '09:00', this.end = '18:00'});

  factory WorkingHours.fromJson(Map<String, dynamic> json) {
    return WorkingHours(
      start: json['start'] as String? ?? '09:00',
      end: json['end'] as String? ?? '18:00',
    );
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class SystemSettings {
  final String timezone;
  final int utcOffset;
  final WorkingHours workingHours;
  final int breakDurationMinutes;
  final List<int> weekendDays;
  final String? updatedAt;
  final String? updatedBy;

  SystemSettings({
    this.timezone = 'Asia/Riyadh',
    this.utcOffset = 3,
    WorkingHours? workingHours,
    this.breakDurationMinutes = 60,
    List<int>? weekendDays,
    this.updatedAt,
    this.updatedBy,
  })  : workingHours = workingHours ?? WorkingHours(),
        weekendDays = weekendDays ?? [5, 6];

  factory SystemSettings.fromJson(Map<String, dynamic> json) {
    return SystemSettings(
      timezone: json['timezone'] as String? ?? 'Asia/Riyadh',
      utcOffset: json['utc_offset'] as int? ?? 3,
      workingHours: json['working_hours'] != null
          ? WorkingHours.fromJson(json['working_hours'] as Map<String, dynamic>)
          : WorkingHours(),
      breakDurationMinutes: json['break_duration_minutes'] as int? ?? 60,
      weekendDays: json['weekend_days'] != null
          ? (json['weekend_days'] as List).map((e) => e as int).toList()
          : [5, 6],
      updatedAt: json['updated_at'] as String?,
      updatedBy: json['updated_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'timezone': timezone,
        'utc_offset': utcOffset,
        'working_hours': workingHours.toJson(),
        'break_duration_minutes': breakDurationMinutes,
        'weekend_days': weekendDays,
        'updated_at': updatedAt,
        'updated_by': updatedBy,
      };

  /// Convert a UTC DateTime to the configured timezone
  DateTime toLocal(DateTime utcTime) {
    return utcTime.toUtc().add(Duration(hours: utcOffset));
  }

  /// Format a UTC timestamp string to local time string (HH:mm)
  String formatTime(String? isoTimestamp) {
    if (isoTimestamp == null) return '--:--';
    final utc = DateTime.parse(isoTimestamp).toUtc();
    final local = utc.add(Duration(hours: utcOffset));
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class TodaySummary {
  final bool signedIn;
  final bool signedOut;
  final bool onBreak;
  final String? signInTime;
  final String? signOutTime;
  final int totalBreakMinutes;
  final int breakCount;

  TodaySummary({
    this.signedIn = false,
    this.signedOut = false,
    this.onBreak = false,
    this.signInTime,
    this.signOutTime,
    this.totalBreakMinutes = 0,
    this.breakCount = 0,
  });

  factory TodaySummary.fromJson(Map<String, dynamic> json) {
    return TodaySummary(
      signedIn: json['signed_in'] as bool? ?? false,
      signedOut: json['signed_out'] as bool? ?? false,
      onBreak: json['on_break'] as bool? ?? false,
      signInTime: json['sign_in_time'] as String?,
      signOutTime: json['sign_out_time'] as String?,
      totalBreakMinutes: json['total_break_minutes'] as int? ?? 0,
      breakCount: json['break_count'] as int? ?? 0,
    );
  }
}
