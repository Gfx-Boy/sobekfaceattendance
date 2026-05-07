import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Task> _myTasks = [];
  List<Task> _assignedTasks = [];
  bool _loading = true;
  bool _calendarView = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _lastTabIndex = 0;

  @override
  void initState() {
    super.initState();
    final employee = context.read<AuthProvider>().employee;
    final isSA = employee?.role == UserRole.superAdmin;
    final isManager = employee?.role != UserRole.employee;
    _tabController = TabController(length: (isManager && !isSA) ? 2 : 1, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted &&
          _tabController.index != _lastTabIndex) {
        _lastTabIndex = _tabController.index;
        setState(() {});
        _loadTasks();
      }
    });
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final employee = context.read<AuthProvider>().employee;
    if (employee == null) return;
    try {
      setState(() => _loading = true);
      final api = ApiService();
      if (employee.role == UserRole.superAdmin) {
        // SuperAdmin sees all tasks across all branches
        _myTasks = await api.getAllTasks();
        _assignedTasks = [];
      } else {
        _myTasks = await api.getTasks(employee.id);
        if (employee.role != UserRole.employee) {
          _assignedTasks = await api.getAssignedTasks(employee.id);
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(Task task, String newStatus,
      {String? comment, List<String>? attachments, int? countedTotal}) async {
    try {
      await ApiService().updateTaskStatus(
        task.id,
        newStatus,
        comment: comment,
        attachments: attachments,
        countedTotal: countedTotal,
      );
      _loadTasks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }

  Future<void> _showCompletionDialog(Task task, String newStatus) async {
    final commentController = TextEditingController();
    final countController = TextEditingController();
    final isWarehouse = task.taskType == 'warehouse';
    File? attachment;
    String? attachmentUrl;
    bool uploading = false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> pick() async {
          final picker = ImagePicker();
          final picked =
              await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
          if (picked == null) return;
          setS(() {
            attachment = File(picked.path);
            attachmentUrl = null;
            uploading = true;
          });
          try {
            final res = await ApiService().uploadTaskAttachment(File(picked.path));
            setS(() {
              attachmentUrl = res['url'] as String?;
              uploading = false;
            });
          } catch (e) {
            setS(() {
              attachment = null;
              uploading = false;
            });
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                    content: Text('$e'),
                    backgroundColor: AppTheme.checkOutRed),
              );
            }
          }
        }

        return AlertDialog(
          backgroundColor: context.colors.cardBg,
          title: Text(newStatus == 'done' ? S.done : S.failed),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                newStatus == 'done'
                    ? S.addCompletionComment
                    : S.addReasonOptional,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 3,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  hintText: S.comment,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              if (isWarehouse && newStatus == 'done') ...[
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        labelText: S.countedTotal,
                        hintText: task.itemCode != null
                            ? '${S.itemCode}: ${task.itemCode}'
                            : null,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: S.scanCode,
                    onPressed: () async {
                      final scanned = await _scanCode();
                      if (scanned != null) {
                        // If the scanned code matches the task's item code, we
                        // just confirm; otherwise we still pre-fill so the
                        // employee can correct the value manually.
                        if (task.itemCode != null &&
                            scanned != task.itemCode) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(S.scannedCodeMismatch),
                                backgroundColor: AppTheme.warningAmber),
                          );
                        }
                        // On successful scan we do not modify the count input
                        // — the employee still enters the total they counted.
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ]),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: uploading ? null : pick,
                icon: uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file, size: 18),
                label: Text(attachment == null
                    ? S.attachFile
                    : (attachmentUrl != null
                        ? '✓ ${attachment!.uri.pathSegments.last}'
                        : attachment!.uri.pathSegments.last)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null), child: Text(S.cancel)),
            ElevatedButton(
              onPressed: uploading
                  ? null
                  : () => Navigator.pop(ctx, {
                        'comment': commentController.text.trim(),
                        'attachment': attachmentUrl,
                        'counted_total':
                            int.tryParse(countController.text.trim()),
                      }),
              child: Text(S.confirm),
            ),
          ],
        );
      }),
    );
    if (result != null) {
      final cmt = (result['comment'] as String?) ?? '';
      final att = result['attachment'] as String?;
      final count = result['counted_total'] as int?;
      _updateStatus(
        task,
        newStatus,
        comment: cmt.isEmpty ? null : cmt,
        attachments: att != null ? [att] : null,
        countedTotal: count,
      );
    }
  }

  /// Opens a camera scanner and returns the first detected barcode/QR value.
  Future<String?> _scanCode() async {
    return await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const _ScannerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    final isSA = employee?.role == UserRole.superAdmin;
    final isManager = employee?.role != UserRole.employee;
    final showAssignedTab = isManager && !isSA;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.tasks),
        actions: [
          IconButton(
            icon: Icon(_calendarView ? Icons.view_list : Icons.calendar_month),
            onPressed: () => setState(() => _calendarView = !_calendarView),
            tooltip: _calendarView ? S.listView : S.calendarView,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryBlue,
          tabs: [
            Tab(text: isSA ? S.tasks : S.myTasks),
            if (showAssignedTab) Tab(text: S.assignedTasks),
          ],
        ),
      ),
      floatingActionButton: (isManager)
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/create-task').then((_) => _loadTasks()),
              backgroundColor: AppTheme.primaryBlue,
              child: const Icon(Icons.add_task, color: Colors.white),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _calendarView
              ? _buildCalendarBody(showAssignedTab)
              : RefreshIndicator(
              onRefresh: _loadTasks,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTaskList(_myTasks, showActions: !isSA),
                  if (showAssignedTab) _buildTaskList(_assignedTasks, showActions: false),
                ],
              ),
            ),
    );
  }

  Widget _buildCalendarBody(bool showAssignedTab) {
    final tasks = (_tabController.index == 0 || !showAssignedTab) ? _myTasks : _assignedTasks;
    return Column(
      children: [
        _buildMonthSelector(),
        _buildDayHeaders(),
        Expanded(child: _buildCalendarGrid(tasks)),
        const SizedBox(height: 8),
        _buildCalendarLegend(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1)),
            child: Icon(Icons.chevron_left, color: context.colors.textPrimary),
          ),
          Text(
            '${S.months[_selectedMonth.month - 1]} ${_selectedMonth.year}',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          GestureDetector(
            onTap: () => setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1)),
            child: Icon(Icons.chevron_right, color: context.colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: S.weekDays.map((d) => Expanded(
          child: Center(child: Text(d, style: TextStyle(color: context.colors.textMuted, fontSize: 12, fontWeight: FontWeight.w500))),
        )).toList(),
      ),
    );
  }

  Widget _buildCalendarGrid(List<Task> tasks) {
    final daysInMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday;
    final today = DateTime.now();

    // Group tasks by due date day
    final Map<int, List<Task>> dayTasks = {};
    for (final t in tasks) {
      if (t.dueDate.year == _selectedMonth.year && t.dueDate.month == _selectedMonth.month) {
        dayTasks.putIfAbsent(t.dueDate.day, () => []).add(t);
      }
    }

    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
      final tasksForDay = dayTasks[day] ?? [];

      cells.add(_buildCalendarDayCell(day, isToday, tasksForDay));
    }

    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      childAspectRatio: 0.75,
      children: cells,
    );
  }

  Widget _buildCalendarDayCell(int day, bool isToday, List<Task> tasks) {
    return GestureDetector(
      onTap: tasks.isNotEmpty ? () => _showDayTasks(day, tasks) : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppTheme.primaryBlue, width: 1.5)
              : Border.all(color: context.colors.surfaceBorder, width: 0.5),
        ),
        child: Column(
          children: [
            SizedBox(height: 2),
            Text(
              '$day',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (tasks.isNotEmpty) ...[
              SizedBox(height: 2),
              ...tasks.take(3).map((t) {
                Color dotColor;
                switch (t.status) {
                  case TaskStatus.toDo:
                    dotColor = context.colors.textSecondary;
                    break;
                  case TaskStatus.inProgress:
                    dotColor = AppTheme.primaryBlue;
                    break;
                  case TaskStatus.done:
                    dotColor = AppTheme.accentGreen;
                    break;
                  case TaskStatus.failed:
                    dotColor = AppTheme.checkOutRed;
                    break;
                }
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: dotColor, fontSize: 7, fontWeight: FontWeight.w600),
                  ),
                );
              }),
              if (tasks.length > 3)
                Text('+${tasks.length - 3}', style: TextStyle(color: context.colors.textMuted, fontSize: 7)),
            ],
          ],
        ),
      ),
    );
  }

  void _showDayTasks(int day, List<Task> tasks) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.cardBg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.colors.surfaceBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Text('${S.tasks} - ${S.months[_selectedMonth.month - 1]} $day', style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...tasks.map((t) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.scaffoldBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
                  if (t.description.isNotEmpty)
                    Text(t.description, style: TextStyle(color: context.colors.textSecondary, fontSize: 12), maxLines: 2),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text(
                        '${S.assignedBy}: ${t.assignedByName ?? t.assignedBy}',
                        style: TextStyle(color: context.colors.textMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(t.statusDisplayName, style: TextStyle(color: _statusColor(t.status), fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                  Text('${S.createdAt}: ${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}', style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                ],
              ),
            )),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.toDo: return context.colors.textSecondary;
      case TaskStatus.inProgress: return AppTheme.primaryBlue;
      case TaskStatus.done: return AppTheme.accentGreen;
      case TaskStatus.failed: return AppTheme.checkOutRed;
    }
  }

  Widget _buildCalendarLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _legendDot(context.colors.textSecondary, S.toDo),
          _legendDot(AppTheme.primaryBlue, S.inProgress),
          _legendDot(AppTheme.accentGreen, S.done),
          _legendDot(AppTheme.checkOutRed, S.failed),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        SizedBox(width: 4),
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildTaskList(List<Task> tasks, {required bool showActions}) {
    if (tasks.isEmpty) {
      return Center(child: Text(S.noTasks, style: TextStyle(color: context.colors.textSecondary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      itemBuilder: (context, index) => _taskCard(tasks[index], showActions: showActions),
    );
  }

  Widget _taskCard(Task task, {required bool showActions}) {
    Color statusColor;
    IconData statusIcon;
    switch (task.status) {
      case TaskStatus.toDo:
        statusColor = context.colors.textSecondary;
        statusIcon = Icons.radio_button_unchecked;
        break;
      case TaskStatus.inProgress:
        statusColor = AppTheme.primaryBlue;
        statusIcon = Icons.pending;
        break;
      case TaskStatus.done:
        statusColor = AppTheme.accentGreen;
        statusIcon = Icons.check_circle;
        break;
      case TaskStatus.failed:
        statusColor = AppTheme.checkOutRed;
        statusIcon = Icons.cancel;
        break;
    }

    final isOverdue = task.dueDate.isBefore(DateTime.now()) && task.status != TaskStatus.done;

    return GestureDetector(
      onTap: () => _showTaskDetail(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isOverdue ? AppTheme.checkOutRed.withValues(alpha: 0.5) : context.colors.surfaceBorder, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text(task.title, style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(task.statusDisplayName, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (task.description.isNotEmpty) ...[
              SizedBox(height: 6),
              Text(task.description, style: TextStyle(color: context.colors.textSecondary, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: isOverdue ? AppTheme.checkOutRed : context.colors.textMuted),
                SizedBox(width: 4),
                Text(
                  '${S.dueDate}: ${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                  style: TextStyle(color: isOverdue ? AppTheme.checkOutRed : context.colors.textMuted, fontSize: 11),
                ),
                if (isOverdue) ...[
                  const SizedBox(width: 6),
                  Text(S.overdue, style: TextStyle(color: AppTheme.checkOutRed, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            if (showActions && task.status != TaskStatus.done && task.status != TaskStatus.failed) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (task.status == TaskStatus.toDo)
                    _statusButton(S.startTask, AppTheme.primaryBlue, () => _updateStatus(task, 'inProgress')),
                  if (task.status == TaskStatus.inProgress) ...[
                    _statusButton(S.done, AppTheme.accentGreen, () => _showCompletionDialog(task, 'done')),
                    const SizedBox(width: 8),
                    _statusButton(S.failed, AppTheme.checkOutRed, () => _showCompletionDialog(task, 'failed')),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTaskDetail(Task task) {
    Color statusColor = _statusColor(task.status);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.colors.surfaceBorder, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(task.title, style: TextStyle(color: context.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(task.statusDisplayName, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 12),
              if (task.description.isNotEmpty)
                Text(task.description, style: TextStyle(color: context.colors.textSecondary, fontSize: 14)),
              const SizedBox(height: 12),
              _detailRow(Icons.person_outline, S.assignedBy, task.assignedByName ?? task.assignedBy),
              _detailRow(Icons.person, S.assignedToLabel, task.assignedToName ?? task.assignedTo),
              _detailRow(Icons.calendar_today, S.dueDate, '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}'),
              _detailRow(Icons.access_time, S.createdAt, '${task.createdAt.day}/${task.createdAt.month}/${task.createdAt.year}'),
              if (task.startedAt != null)
                _detailRow(Icons.play_arrow, S.startedLabel, '${task.startedAt!.day}/${task.startedAt!.month}/${task.startedAt!.year}'),
              if (task.completedAt != null)
                _detailRow(Icons.flag, S.completedLabel, '${task.completedAt!.day}/${task.completedAt!.month}/${task.completedAt!.year}'),
              if (task.taskType == 'warehouse' && task.itemCode != null) ...[
                const SizedBox(height: 12),
                Text(S.itemCode,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 6),
                Center(
                  child: GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: QrImageView(
                              data: task.itemCode!, size: 260),
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(data: task.itemCode!, size: 140),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: SelectableText(
                    task.itemCode!,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
              if (task.countedTotal != null) ...[
                const SizedBox(height: 8),
                _detailRow(Icons.numbers, S.countedTotal,
                    task.countedTotal!.toString()),
              ],
              if (task.completionComment != null && task.completionComment!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(S.completionCommentLabel, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(task.completionComment!, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
              ],
              if (task.attachments != null && task.attachments!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(S.attachments,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 6),
                _attachmentThumbs(task.attachments!),
              ],
              if (task.completionAttachments != null &&
                  task.completionAttachments!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(S.completionAttachments,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 6),
                _attachmentThumbs(task.completionAttachments!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentThumbs(List<String> urls) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: urls.map((u) {
        return GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              child: InteractiveViewer(child: Image.network(u)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              u,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: context.colors.cardBgLighter,
                child: Icon(Icons.insert_drive_file,
                    color: context.colors.textMuted),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: context.colors.textMuted),
        SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ]),
    );
  }

  Widget _statusButton(String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(side: BorderSide(color: color), padding: const EdgeInsets.symmetric(vertical: 6)),
        child: Text(label, style: TextStyle(color: color, fontSize: 13)),
      ),
    );
  }
}

/// Fullscreen camera view that reads a single QR / barcode and returns it.
class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.scanCode)),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_handled) return;
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && v.isNotEmpty) {
              _handled = true;
              Navigator.pop(context, v);
              break;
            }
          }
        },
      ),
    );
  }
}
