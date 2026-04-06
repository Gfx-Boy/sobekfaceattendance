class VerificationResult {
  final bool isVerified;
  final bool faceMatched;
  final bool livenessDetected;
  final double? faceMatchConfidence;
  final String message;
  final String? attendanceId;
  final String? type;

  VerificationResult({
    required this.isVerified,
    required this.faceMatched,
    required this.livenessDetected,
    this.faceMatchConfidence,
    required this.message,
    this.attendanceId,
    this.type,
  });

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    return VerificationResult(
      isVerified: json['is_verified'] as bool? ?? false,
      faceMatched: json['face_matched'] as bool? ?? false,
      livenessDetected: json['liveness_detected'] as bool? ?? false,
      faceMatchConfidence:
          (json['face_match_confidence'] as num?)?.toDouble(),
      message: json['message'] as String? ?? 'Unknown error',
      attendanceId: json['attendance_id'] as String?,
      type: json['type'] as String?,
    );
  }
}
