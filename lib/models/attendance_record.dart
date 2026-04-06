class AttendanceRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final String type; // sign_in, sign_out, day_status
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final String? address;
  final AttendanceStatus status;
  final double? faceMatchConfidence;
  final bool livenessVerified;
  final String? imageUrl;
  final String? dayStatus; // attend, vacation, absent, sick, business_mission, holiday
  final String? date; // YYYY-MM-DD for day_status records

  AttendanceRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.type = 'sign_in',
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.status,
    this.faceMatchConfidence,
    required this.livenessVerified,
    this.imageUrl,
    this.dayStatus,
    this.date,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String? ?? '',
      type: json['type'] as String? ?? 'sign_in',
      timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      address: json['address'] as String?,
      status: AttendanceStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AttendanceStatus.failed,
      ),
      faceMatchConfidence: (json['face_match_confidence'] as num?)?.toDouble(),
      livenessVerified: json['liveness_verified'] as bool? ?? false,
      imageUrl: json['image_url'] as String?,
      dayStatus: json['day_status'] as String?,
      date: json['date'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'type': type,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status.name,
      'face_match_confidence': faceMatchConfidence,
      'liveness_verified': livenessVerified,
      'image_url': imageUrl,
    };
  }
}

enum AttendanceStatus {
  success,
  failed,
  pending,
}
