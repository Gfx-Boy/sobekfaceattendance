enum TaskStatus {
  toDo,
  inProgress,
  done,
  failed,
}

class Task {
  final String id;
  final String title;
  final String description;
  final String assignedTo;
  final String assignedBy;
  final String? assignedToName;
  final String? assignedByName;
  final DateTime dueDate;
  final TaskStatus status;
  final DateTime createdAt;
  final List<String>? attachments;
  final String? comment;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.assignedBy,
    this.assignedToName,
    this.assignedByName,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    this.attachments,
    this.comment,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      assignedTo: json['assigned_to'] as String,
      assignedBy: json['assigned_by'] as String,
      assignedToName: json['assigned_to_name'] as String?,
      assignedByName: json['assigned_by_name'] as String?,
      dueDate: DateTime.parse(json['due_date'] as String),
      status: TaskStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TaskStatus.toDo,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      attachments: (json['attachments'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      comment: json['comment'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'assigned_to': assignedTo,
      'assigned_by': assignedBy,
      'assigned_to_name': assignedToName,
      'assigned_by_name': assignedByName,
      'due_date': dueDate.toIso8601String(),
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'attachments': attachments,
      'comment': comment,
    };
  }

  String get statusDisplayName {
    switch (status) {
      case TaskStatus.toDo:
        return 'To Do';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.done:
        return 'Done';
      case TaskStatus.failed:
        return 'Failed';
    }
  }
}
