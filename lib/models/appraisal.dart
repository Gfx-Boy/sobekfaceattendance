class Appraisal {
  final String id;
  final String employeeId;
  final String employeeName;
  final String evaluatorId;
  final String evaluatorName;
  final String period;
  final Map<String, dynamic> scores;
  final String comments;
  final double overallScore;
  final String status;
  final String? branchId;
  final DateTime createdAt;

  Appraisal({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.evaluatorId,
    required this.evaluatorName,
    required this.period,
    required this.scores,
    this.comments = '',
    this.overallScore = 0,
    this.status = 'submitted',
    this.branchId,
    required this.createdAt,
  });

  factory Appraisal.fromJson(Map<String, dynamic> json) {
    return Appraisal(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String? ?? '',
      evaluatorId: json['evaluator_id'] as String,
      evaluatorName: json['evaluator_name'] as String? ?? '',
      period: json['period'] as String,
      scores: json['scores'] as Map<String, dynamic>? ?? {},
      comments: json['comments'] as String? ?? '',
      overallScore: (json['overall_score'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'submitted',
      branchId: json['branch_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'evaluator_id': evaluatorId,
        'evaluator_name': evaluatorName,
        'period': period,
        'scores': scores,
        'comments': comments,
        'overall_score': overallScore,
        'status': status,
        'branch_id': branchId,
        'created_at': createdAt.toIso8601String(),
      };
}
