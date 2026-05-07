/// Represents an appraisal cycle that gates individual appraisal submissions.
///
/// Cycles are created by a Branch Admin with a defined start/end window
/// and weight split between the admin's score and the HR's score.
class AppraisalCycle {
  final String id;
  final String branchId;
  final String branchName;
  final DateTime startDate;
  final DateTime endDate;
  final double adminWeight;
  final double hrWeight;
  final String status; // 'active' | 'closed'
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime? closedAt;
  final String? closedReason;

  AppraisalCycle({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.startDate,
    required this.endDate,
    required this.adminWeight,
    required this.hrWeight,
    required this.status,
    required this.createdAt,
    this.createdBy,
    this.createdByName,
    this.closedAt,
    this.closedReason,
  });

  bool get isActive => status == 'active';

  factory AppraisalCycle.fromJson(Map<String, dynamic> json) => AppraisalCycle(
        id: json['id'] as String,
        branchId: json['branch_id'] as String? ?? '',
        branchName: json['branch_name'] as String? ?? '',
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        adminWeight: (json['admin_weight'] as num?)?.toDouble() ?? 70,
        hrWeight: (json['hr_weight'] as num?)?.toDouble() ?? 30,
        status: json['status'] as String? ?? 'active',
        createdBy: json['created_by'] as String?,
        createdByName: json['created_by_name'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        closedAt: json['closed_at'] != null
            ? DateTime.tryParse(json['closed_at'] as String)
            : null,
        closedReason: json['closed_reason'] as String?,
      );
}
