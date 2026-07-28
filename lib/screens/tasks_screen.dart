import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
// Hide mobile_scanner's Barcode to avoid clashing with barcode_widget's
// Barcode (used for rendering); we only need BarcodeCapture from here.
import 'package:mobile_scanner/mobile_scanner.dart' hide Barcode;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';
import '../models/branch.dart';

enum _SATaskLevel { branches, titles, employees, months }

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

  // Super Admin drill-down: branches → titles → employees → months → tasks
  _SATaskLevel _saLevel = _SATaskLevel.branches;
  List<Branch> _saBranches = [];
  Branch? _selectedSABranch;
  List<String> _saTitles = [];
  String? _selectedSATitle;
  List<Employee> _saAllBranchEmps = [];
  List<Employee> _saFilteredEmps = [];
  Employee? _selectedSAEmployee;
  List<Task> _saTasks = [];
  bool _saLoading = false;
  // All loaded SA employee tasks (for month drill-down)
  List<Task> _saAllEmployeeTasks = [];

  // Search for the Super Admin drill-down lists (#39)
  final _saSearchController = TextEditingController();
  String get _saQ => _saSearchController.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _saSearchController.addListener(() => setState(() {}));
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
    if (isSA) {
      _loadSABranches();
    } else {
      _loadTasks();
    }
  }

  Future<void> _loadSABranches() async {
    setState(() => _saLoading = true);
    try {
      _saBranches = await ApiService().getBranches();
    } catch (_) { _saBranches = []; }
    if (mounted) setState(() { _saLoading = false; _loading = false; });
  }

  Future<void> _selectSABranch(Branch b) async {
    _saSearchController.clear();
    setState(() { _selectedSABranch = b; _saLoading = true; });
    try {
      _saAllBranchEmps = await ApiService().getAllEmployees(branchId: b.id);
      final positions = <String>{};
      for (final e in _saAllBranchEmps) {
        positions.add(e.position?.isNotEmpty == true ? e.position! : e.role.name);
      }
      _saTitles = positions.toList();
    } catch (_) { _saTitles = []; }
    if (mounted) setState(() { _saLoading = false; _saLevel = _SATaskLevel.titles; });
  }

  void _selectSATitle(String title) {
    _saSearchController.clear();
    _selectedSATitle = title;
    _saFilteredEmps = _saAllBranchEmps
        .where((e) => (e.position?.isNotEmpty == true ? e.position! : e.role.name) == title)
        .toList();
    setState(() => _saLevel = _SATaskLevel.employees);
  }

  Future<void> _selectSAEmployee(Employee emp) async {
    _saSearchController.clear();
    setState(() { _selectedSAEmployee = emp; _loading = true; _saLevel = _SATaskLevel.months; });
    try {
      _saAllEmployeeTasks = await ApiService().getTasks(emp.id);
    } catch (_) { _saAllEmployeeTasks = []; }
    if (mounted) setState(() => _loading = false);
  }

  void _selectSAMonth(int year, int month) {
    _saTasks = _saAllEmployeeTasks.where((t) =>
        t.dueDate.year == year && t.dueDate.month == month).toList();
    setState(() {
      _selectedMonth = DateTime(year, month);
    });
  }

  void _goBackSA() {
    _saSearchController.clear();
    setState(() {
      if (_saTasks.isNotEmpty) {
        // Back from task detail view → months list
        _saTasks = [];
        _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
      } else if (_selectedSAEmployee != null) {
        // Back from months list → employees
        _selectedSAEmployee = null;
        _saAllEmployeeTasks = [];
        _saLevel = _SATaskLevel.employees;
      } else if (_saLevel == _SATaskLevel.employees) {
        _saLevel = _SATaskLevel.titles;
        _selectedSATitle = null;
      } else if (_saLevel == _SATaskLevel.titles) {
        _saLevel = _SATaskLevel.branches;
        _selectedSABranch = null;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _saSearchController.dispose();
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
          // #9/#28 — branch managers (HR + Branch Admin) see all tasks
          // assigned within their branch, not only the ones they created.
          if (employee.branchId != null && employee.branchId!.isNotEmpty) {
            _assignedTasks = await api.getBranchAssignedTasks(employee.branchId!);
          } else {
            _assignedTasks = await api.getAssignedTasks(employee.id);
          }
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
    // Prefill with any tally saved via "continue counting" (#18).
    final countController =
        TextEditingController(text: task.countedTotal?.toString() ?? '');
    final isWarehouse = task.taskType == 'warehouse';
    File? attachment;
    String? attachmentUrl;
    bool uploading = false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> pick() async {
          final result = await FilePicker.platform.pickFiles(
            allowMultiple: false,
            type: FileType.any,
          );
          final filePath = result?.files.single.path;
          if (filePath == null) return;
          setS(() {
            attachment = File(filePath);
            attachmentUrl = null;
            uploading = true;
          });
          try {
            final res = await ApiService().uploadTaskAttachment(File(filePath));
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
                TextField(
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: Text(S.scanToCount),
                    onPressed: () async {
                      final total = await _scanToCount(task.itemCode,
                          initialCount:
                              int.tryParse(countController.text.trim()) ?? 0);
                      if (total != null) {
                        setS(() => countController.text = total.toString());
                      }
                    },
                  ),
                ),
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
            // Warehouse counting can span multiple sessions — let the counter
            // persist the tally and come back later without completing (#2 r3).
            if (isWarehouse && newStatus == 'done')
              TextButton(
                onPressed: () => Navigator.pop(ctx, {
                  'save_only': true,
                  'counted_total': int.tryParse(countController.text.trim()),
                }),
                child: Text(S.saveAndContinueLater),
              ),
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
      final count = result['counted_total'] as int?;
      if (result['save_only'] == true) {
        try {
          await ApiService().saveTaskCount(task.id, count ?? 0);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('${S.countedTotal}: ${count ?? 0}'),
                  backgroundColor: AppTheme.accentGreen),
            );
          }
          _loadTasks();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
            );
          }
        }
        return;
      }
      final cmt = (result['comment'] as String?) ?? '';
      final att = result['attachment'] as String?;
      _updateStatus(
        task,
        newStatus,
        comment: cmt.isEmpty ? null : cmt,
        attachments: att != null ? [att] : null,
        countedTotal: count,
      );
    }
  }

  /// Opens a live counting scanner. Each scan (optionally matching
  /// [expectedCode]) increments a tally; returns the final counted total.
  Future<int?> _scanToCount(String? expectedCode, {int initialCount = 0}) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera permission required to scan codes.'),
            backgroundColor: AppTheme.checkOutRed,
          ),
        );
      }
      return null;
    }
    return await Navigator.of(context).push<int>(
      MaterialPageRoute(
          builder: (_) => _CountingScannerScreen(
              expectedCode: expectedCode, initialCount: initialCount)),
    );
  }

  /// Scan starting from the task's saved tally and persist the new total
  /// without completing the task — "save & continue counting" (#18).
  Future<void> _continueCounting(Task task) async {
    final total = await _scanToCount(task.itemCode,
        initialCount: task.countedTotal ?? 0);
    if (total == null) return;
    try {
      await ApiService().saveTaskCount(task.id, total);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${S.countedTotal}: $total'),
              backgroundColor: AppTheme.accentGreen),
        );
      }
      _loadTasks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    final isSA = employee?.role == UserRole.superAdmin;
    final isManager = employee?.role != UserRole.employee;
    final showAssignedTab = isManager && !isSA;

    // Super Admin: hierarchical drill-down
    if (isSA) {
      final showingTasks = _saTasks.isNotEmpty;
      final showingMonths = _selectedSAEmployee != null && _saTasks.isEmpty;
      final showBack = _saTasks.isNotEmpty || _selectedSAEmployee != null || _saLevel != _SATaskLevel.branches;
      String title = S.tasks;
      if (showingTasks) {
        title = '${_selectedSAEmployee!.name} — ${S.months[_selectedMonth.month - 1]}';
      } else if (_selectedSAEmployee != null) {
        title = _selectedSAEmployee!.name;
      } else if (_saLevel == _SATaskLevel.employees) {
        title = _selectedSATitle ?? S.tasks;
      } else if (_saLevel == _SATaskLevel.titles) {
        title = _selectedSABranch?.name ?? S.tasks;
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: showBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBackSA,
                )
              : null,
          actions: [
            if (showingTasks)
              IconButton(
                icon: Icon(_calendarView ? Icons.view_list : Icons.calendar_month),
                onPressed: () => setState(() => _calendarView = !_calendarView),
              ),
          ],
        ),
        floatingActionButton: showingTasks
            ? FloatingActionButton(
                onPressed: () => Navigator.pushNamed(context, '/create-task')
                    .then((_) => _selectSAEmployee(_selectedSAEmployee!)),
                backgroundColor: AppTheme.primaryBlue,
                child: const Icon(Icons.add_task, color: Colors.white),
              )
            : null,
        body: _saLoading
            ? const Center(child: CircularProgressIndicator())
            : showingTasks
                ? (_loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_calendarView
                        ? _buildSACalendarBody()
                        : _buildTaskList(_saTasks, showActions: false)))
                : showingMonths
                    ? (_loading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildSAMonthsList())
                    : _buildSAHierarchyBody(),
      );
    }

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
            Tab(text: S.myTasks),
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
                  _buildTaskList(_myTasks, showActions: true),
                  if (showAssignedTab) _buildTaskList(_assignedTasks, showActions: false),
                ],
              ),
            ),
    );
  }

  Widget _buildSAHierarchyBody() {
    Widget list;
    switch (_saLevel) {
      case _SATaskLevel.branches:
        list = _buildSABranchesList();
        break;
      case _SATaskLevel.titles:
        list = _buildSATitlesList();
        break;
      case _SATaskLevel.employees:
        list = _buildSAEmployeesList();
        break;
      case _SATaskLevel.months:
        list = _buildSAMonthsList();
        break;
    }
    // Months are not searchable; everything else is (#39).
    if (_saLevel == _SATaskLevel.months) return list;
    return Column(
      children: [
        _buildSASearchBar(),
        Expanded(child: list),
      ],
    );
  }

  Widget _buildSASearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _saSearchController,
        style: TextStyle(color: context.colors.textPrimary),
        decoration: InputDecoration(
          hintText: S.search,
          prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
          suffixIcon: _saQ.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.clear, color: context.colors.textMuted),
                  onPressed: () => _saSearchController.clear(),
                ),
          filled: true,
          fillColor: context.colors.cardBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildSAMonthsList() {
    // Group tasks by year-month
    final Map<String, int> monthCounts = {};
    for (final t in _saAllEmployeeTasks) {
      final key = '${t.dueDate.year}-${t.dueDate.month.toString().padLeft(2, '0')}';
      monthCounts[key] = (monthCounts[key] ?? 0) + 1;
    }
    if (monthCounts.isEmpty) {
      return Center(child: Text(S.noTasks, style: TextStyle(color: context.colors.textSecondary)));
    }
    final sorted = monthCounts.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: sorted.length,
      itemBuilder: (_, i) {
        final parts = sorted[i].split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final count = monthCounts[sorted[i]]!;
        return Card(
          color: context.colors.cardBg,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_month, color: AppTheme.primaryBlue, size: 22),
            ),
            title: Text(
              '${S.months[month - 1]} $year',
              style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '$count ${count == 1 ? "task" : "tasks"}',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
            onTap: () {
              _selectSAMonth(year, month);
            },
          ),
        );
      },
    );
  }

  Widget _buildSABranchesList() {
    if (_saBranches.isEmpty) {
      return Center(child: Text(S.noBranchesYet, style: TextStyle(color: context.colors.textSecondary)));
    }
    final branches = _saBranches
        .where((b) =>
            _saQ.isEmpty ||
            b.name.toLowerCase().contains(_saQ) ||
            b.address.toLowerCase().contains(_saQ))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: branches.length,
      itemBuilder: (_, i) {
        final b = branches[i];
        return Card(
          color: context.colors.cardBg,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.business, color: AppTheme.primaryBlue, size: 22),
            ),
            title: Text(b.name, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(b.address, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
            trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
            onTap: () => _selectSABranch(b),
          ),
        );
      },
    );
  }

  Widget _buildSATitlesList() {
    if (_saTitles.isEmpty) {
      return Center(child: Text(S.noEmployees, style: TextStyle(color: context.colors.textSecondary)));
    }
    final titles = _saTitles
        .where((t) => _saQ.isEmpty || t.toLowerCase().contains(_saQ))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: titles.length,
      itemBuilder: (_, i) {
        final title = titles[i];
        return Card(
          color: context.colors.cardBg,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.badge_outlined, color: Color(0xFF6C63FF), size: 22),
            ),
            title: Text(title, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
            onTap: () => _selectSATitle(title),
          ),
        );
      },
    );
  }

  Widget _buildSAEmployeesList() {
    if (_saFilteredEmps.isEmpty) {
      return Center(child: Text(S.noEmployees, style: TextStyle(color: context.colors.textSecondary)));
    }
    final emps = _saFilteredEmps
        .where((e) =>
            _saQ.isEmpty ||
            e.name.toLowerCase().contains(_saQ) ||
            e.email.toLowerCase().contains(_saQ))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: emps.length,
      itemBuilder: (_, i) {
        final e = emps[i];
        return Card(
          color: context.colors.cardBg,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
              child: Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppTheme.primaryBlue)),
            ),
            title: Text(e.name, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: Text(e.email, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
            trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
            onTap: () => _selectSAEmployee(e),
          ),
        );
      },
    );
  }

  Widget _buildSACalendarBody() {
    return Column(
      children: [
        _buildMonthSelector(),
        _buildDayHeaders(),
        Expanded(child: _buildCalendarGrid(_saTasks)),
        const SizedBox(height: 8),
        _buildCalendarLegend(),
        const SizedBox(height: 8),
      ],
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
            // Tapping a task opens the same rich detail used by the list view.
            ...tasks.map((t) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTaskDetail(t);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.scaffoldBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: context.colors.surfaceBorder, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(t.title,
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (t.taskType == 'warehouse')
                            Icon(Icons.qr_code_2,
                                size: 16, color: context.colors.textMuted),
                          if ((t.attachments?.isNotEmpty ?? false))
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.attach_file,
                                  size: 14, color: context.colors.textMuted),
                            ),
                        ]),
                        if (t.description.isNotEmpty)
                          Text(t.description,
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(
                            child: Text(
                              '${S.assignedBy}: ${t.assignedByName ?? t.assignedBy}',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(t.statusDisplayName,
                              style: TextStyle(
                                  color: _statusColor(t.status),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Text(
                              '${S.dueDate}: ${t.dueDate.day}/${t.dueDate.month}/${t.dueDate.year}',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 11)),
                          const Spacer(),
                          Text(S.viewDetails,
                              style: TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          Icon(Icons.chevron_right,
                              size: 14, color: AppTheme.primaryBlue),
                        ]),
                      ],
                    ),
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
                    if (task.taskType == 'warehouse') ...[
                      _statusButton(S.scanToCount, AppTheme.primaryBlue,
                          () => _continueCounting(task)),
                      const SizedBox(width: 8),
                    ],
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
    // The calendar view (the default) opens tasks only through this sheet, so
    // the assignee needs the start/count/complete actions here too (#2 r3).
    final me = context.read<AuthProvider>().employee;
    final canAct = me != null &&
        task.assignedTo == me.id &&
        task.status != TaskStatus.done &&
        task.status != TaskStatus.failed;
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
                _buildItemCodeView(task),
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
              if (canAct) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (task.status == TaskStatus.toDo)
                      _statusButton(S.startTask, AppTheme.primaryBlue, () {
                        Navigator.pop(ctx);
                        _updateStatus(task, 'inProgress');
                      }),
                    if (task.status == TaskStatus.inProgress) ...[
                      if (task.taskType == 'warehouse') ...[
                        _statusButton(S.scanToCount, AppTheme.primaryBlue, () {
                          Navigator.pop(ctx);
                          _continueCounting(task);
                        }),
                        const SizedBox(width: 8),
                      ],
                      _statusButton(S.done, AppTheme.accentGreen, () {
                        Navigator.pop(ctx);
                        _showCompletionDialog(task, 'done');
                      }),
                      const SizedBox(width: 8),
                      _statusButton(S.failed, AppTheme.checkOutRed, () {
                        Navigator.pop(ctx);
                        _showCompletionDialog(task, 'failed');
                      }),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the warehouse item code as a QR, a barcode, or both, per
  /// the task's `codeType`.
  Widget _buildItemCodeView(Task task) {
    final code = task.itemCode!;
    final type = task.codeType;
    final showQr = type == 'qr' || type == 'both';
    final showBarcode = type == 'barcode' || type == 'both';

    Widget qr = GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: QrImageView(data: code, size: 260),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: QrImageView(data: code, size: 140),
      ),
    );

    // Tappable exactly like the QR — the client tapped the barcode expecting
    // it to open enlarged and "it didn't open" (#2 round 3).
    Widget barcode = GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: code,
              width: 300,
              height: 130,
              drawText: true,
              style: const TextStyle(color: Colors.black, fontSize: 14),
            ),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: BarcodeWidget(
          barcode: Barcode.code128(),
          data: code,
          width: 220,
          height: 80,
          drawText: false,
        ),
      ),
    );

    return Center(
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          if (showQr) qr,
          if (showBarcode) barcode,
        ],
      ),
    );
  }

  static const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  String _extOf(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0) return '';
    return clean.substring(dot + 1).toLowerCase();
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _attachmentThumbs(List<String> urls) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: urls.map((u) {
        final ext = _extOf(u);
        final isImage = _imageExts.contains(ext);
        if (isImage) {
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
                errorBuilder: (_, __, ___) => _fileTile(ext),
              ),
            ),
          );
        }
        // Non-image (pdf / word / excel / etc.): tap opens it externally —
        // the attachment endpoint is public, so the browser/viewer can fetch
        // it without auth headers (#17).
        return GestureDetector(
          onTap: () => _openAttachment(u),
          child: _fileTile(ext),
        );
      }).toList(),
    );
  }

  Future<void> _openAttachment(String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    try {
      ok = uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(S.failedToOpenAttachment),
            backgroundColor: AppTheme.checkOutRed),
      );
    }
  }

  Widget _fileTile(String ext) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: context.colors.cardBgLighter,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_iconForExt(ext), color: AppTheme.primaryBlue, size: 30),
          const SizedBox(height: 4),
          Text(ext.isEmpty ? S.attachments : ext.toUpperCase(),
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
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

/// Fullscreen camera view that tallies scanned items. Each detected code
/// increments the counter (debounced so one physical scan counts once). When
/// [expectedCode] is given, only matching codes are counted. Returns the final
/// total when the user confirms.
class _CountingScannerScreen extends StatefulWidget {
  const _CountingScannerScreen({this.expectedCode, this.initialCount = 0});

  final String? expectedCode;

  /// Resume counting from a previously saved tally (#18).
  final int initialCount;

  @override
  State<_CountingScannerScreen> createState() => _CountingScannerScreenState();
}

class _CountingScannerScreenState extends State<_CountingScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  late int _count = widget.initialCount;
  String? _lastValue;
  DateTime? _lastAt;
  String? _toast;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v == null || v.isEmpty) continue;

      // Debounce: ignore the same value seen again within 1.5s so holding an
      // item in frame doesn't inflate the count.
      final now = DateTime.now();
      if (_lastValue == v &&
          _lastAt != null &&
          now.difference(_lastAt!) < const Duration(milliseconds: 1500)) {
        return;
      }
      _lastValue = v;
      _lastAt = now;

      if (widget.expectedCode != null && v != widget.expectedCode) {
        setState(() => _toast = S.scannedCodeMismatch);
        return;
      }
      setState(() {
        _count += 1;
        _toast = null;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.scanToCount),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Live count overlay.
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    S.countedItems(_count),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _toast ?? S.tapToCountHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _toast != null
                          ? AppTheme.warningAmber
                          : Colors.white70,
                      fontSize: 13,
                      backgroundColor: Colors.black45),
                ),
              ],
            ),
          ),
          // Bottom controls.
          Positioned(
            bottom: 24 + MediaQuery.of(context).viewPadding.bottom,
            left: 16,
            right: 16,
            child: Row(
              children: [
                IconButton.filled(
                  onPressed: _count > 0
                      ? () => setState(() => _count -= 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => setState(() => _count += 1),
                  icon: const Icon(Icons.add),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen),
                  onPressed: () => Navigator.pop(context, _count),
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: Text(S.useCount,
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
