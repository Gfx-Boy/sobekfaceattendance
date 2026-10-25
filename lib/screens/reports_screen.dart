import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../models/attendance_record.dart';
import '../models/request.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../widgets/attendance_calendar.dart';

enum _ReportLevel { branches, titles, employees, calendar }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportLevel _level = _ReportLevel.branches;
  bool _loading = true;

  // Level 1: branches (SA only)
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedBranch;

  // Level 2: titles (SA only)
  List<Map<String, dynamic>> _titles = [];
  String? _selectedTitleRole;

  // All employees in current branch (cached)
  List<Map<String, dynamic>> _allBranchEmployees = [];

  // Level 3: employees
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic>? _selectedEmployee;

  // Level 4: calendar
  List<AttendanceRecord> _attendanceRecords = [];
  List<AppRequest> _employeeRequests = [];
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isSA =>
      context.read<AuthProvider>().employee?.role == UserRole.superAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLoad());
  }

  Future<void> _initLoad() async {
    final role = context.read<AuthProvider>().employee?.role;
    if (role == UserRole.superAdmin) {
      await _loadBranches();
    } else {
      final branchId = context.read<AuthProvider>().employee?.branchId;
      setState(() => _level = _ReportLevel.employees);
      await _loadBranchEmployees(branchId);
      _employees = List<Map<String, dynamic>>.from(_allBranchEmployees);
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _level = _ReportLevel.branches;
    });
    try {
      final branches = await ApiService().getBranches();
      _branches = branches
          .map((b) => <String, dynamic>{
                'id': b.id,
                'name': b.name,
                'address': b.address,
              })
          .toList();
      _branches.sort((a, b) =>
          (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBranchEmployees(String? branchId) async {
    setState(() => _loading = true);
    try {
      final employees = await ApiService().getAllEmployees(branchId: branchId);
      final myId = context.read<AuthProvider>().employee?.id;
      // #12 — the attendance monitor excludes super admins and branch admins
      // (managers aren't monitored here), as well as the viewer themselves.
      _allBranchEmployees = employees
          .where((e) =>
              e.role != UserRole.superAdmin &&
              e.role != UserRole.branchAdmin &&
              e.id != myId)
          .map((e) => <String, dynamic>{
                'id': e.id,
                'name': e.name,
                'email': e.email,
                'role': e.role.name,
                'position': e.position ?? '',
                'profile_image_url': e.profileImageUrl ?? '',
              })
          .toList();
      _allBranchEmployees.sort((a, b) =>
          (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
    } catch (_) {
      _allBranchEmployees = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _buildTitlesFromBranchEmployees() {
    final Map<String, int> counts = {};
    for (final emp in _allBranchEmployees) {
      final r = (emp['role'] as String?) ?? 'employee';
      counts[r] = (counts[r] ?? 0) + 1;
    }
    const order = ['branchAdmin', 'hr', 'employee'];
    _titles = order
        .where((r) => counts.containsKey(r))
        .map((r) => <String, dynamic>{
              'role': r,
              'label': _roleName(r),
              'count': counts[r] ?? 0,
            })
        .toList();
  }

  Future<void> _loadAttendance(String employeeId) async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getAttendanceHistory(employeeId),
        ApiService().getRequests(employeeId),
      ]);
      _attendanceRecords = results[0] as List<AttendanceRecord>;
      _employeeRequests = results[1] as List<AppRequest>;
    } catch (_) {
      _attendanceRecords = [];
      _employeeRequests = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _goBack() {
    if (_level == _ReportLevel.calendar) {
      setState(() {
        _level = _ReportLevel.employees;
        _selectedEmployee = null;
        _attendanceRecords = [];
      });
    } else if (_level == _ReportLevel.employees && _isSA) {
      setState(() {
        _level = _ReportLevel.titles;
        _selectedTitleRole = null;
        _employees = [];
      });
    } else if (_level == _ReportLevel.titles && _isSA) {
      setState(() {
        _level = _ReportLevel.branches;
        _selectedBranch = null;
        _titles = [];
        _allBranchEmployees = [];
      });
    }
  }

  bool get _canGoBack {
    if (_level == _ReportLevel.calendar) return true;
    if (!_isSA) return false;
    return _level == _ReportLevel.employees || _level == _ReportLevel.titles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(),
        leading: _canGoBack
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack)
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildTitle() {
    switch (_level) {
      case _ReportLevel.branches:
        return Text(S.attendanceReports);
      case _ReportLevel.titles:
        return Text(_selectedBranch?['name'] as String? ?? S.titles);
      case _ReportLevel.employees:
        if (_isSA) return Text(_roleName(_selectedTitleRole ?? ''));
        return Text(S.employees);
      case _ReportLevel.calendar:
        return Text(_selectedEmployee?['name'] as String? ?? S.attendance);
    }
  }

  Widget _buildBody() {
    switch (_level) {
      case _ReportLevel.branches:
        return _buildBranchesList();
      case _ReportLevel.titles:
        return _buildTitlesList();
      case _ReportLevel.employees:
        return _buildEmployeesList();
      case _ReportLevel.calendar:
        return _buildCalendar();
    }
  }

  Widget _buildBranchesList() {
    if (_branches.isEmpty) {
      return _buildEmpty(S.noBranchesFound, Icons.business_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadBranches,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _branches.length,
        itemBuilder: (context, i) {
          final branch = _branches[i];
          return _drillCard(
            icon: Icons.business,
            title: branch['name'] as String? ?? '',
            subtitle: branch['address'] as String? ?? '',
            onTap: () async {
              _selectedBranch = branch;
              setState(() => _level = _ReportLevel.titles);
              await _loadBranchEmployees(branch['id'] as String?);
              _buildTitlesFromBranchEmployees();
              if (mounted) setState(() {});
            },
          );
        },
      ),
    );
  }

  Widget _buildTitlesList() {
    if (_titles.isEmpty) {
      return _buildEmpty(S.noTitlesFound, Icons.badge_outlined);
    }
    return RefreshIndicator(
      onRefresh: () async {
        await _loadBranchEmployees(_selectedBranch?['id'] as String?);
        _buildTitlesFromBranchEmployees();
        if (mounted) setState(() {});
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _titles.length,
        itemBuilder: (context, i) {
          final t = _titles[i];
          final role = t['role'] as String;
          return _drillCard(
            icon: _iconForRole(role),
            title: t['label'] as String,
            subtitle: S.employeeCountLabel(t['count'] as int),
            onTap: () {
              _selectedTitleRole = role;
              _employees = _allBranchEmployees
                  .where((e) => (e['role'] as String?) == role)
                  .toList();
              setState(() => _level = _ReportLevel.employees);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmployeesList() {
    if (_employees.isEmpty) {
      return _buildEmpty(S.noEmployeesInBranch, Icons.people_outline);
    }
    Future<void> refresh() async {
      if (_isSA) {
        await _loadBranchEmployees(_selectedBranch?['id'] as String?);
        if (_selectedTitleRole != null) {
          _employees = _allBranchEmployees
              .where((e) => (e['role'] as String?) == _selectedTitleRole)
              .toList();
        }
      } else {
        await _loadBranchEmployees(
            context.read<AuthProvider>().employee?.branchId);
        _employees = List<Map<String, dynamic>>.from(_allBranchEmployees);
      }
      if (mounted) setState(() {});
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _employees.length,
        itemBuilder: (context, i) {
          final emp = _employees[i];
          final imageUrl = emp['profile_image_url'] as String? ?? '';
          final name = emp['name'] as String? ?? '';
          final role = emp['role'] as String? ?? '';
          final position = emp['position'] as String? ?? '';
          final email = emp['email'] as String? ?? '';
          return Card(
            color: context.colors.cardBg,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.colors.surfaceBorder, width: 0.5),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                backgroundImage:
                    imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                child: imageUrl.isEmpty
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              title: Text(name,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (position.isNotEmpty)
                    Text(position,
                        style: TextStyle(
                            color: context.colors.textSecondary, fontSize: 12)),
                  if (email.isNotEmpty)
                    Text(email,
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                  if (role.isNotEmpty && position.isEmpty)
                    Text(_roleName(role),
                        style: TextStyle(
                            color: context.colors.textSecondary, fontSize: 12)),
                ],
              ),
              isThreeLine: true,
              trailing:
                  Icon(Icons.chevron_right, color: context.colors.textMuted),
              onTap: () async {
                _selectedEmployee = emp;
                _selectedMonth =
                    DateTime(DateTime.now().year, DateTime.now().month);
                await _loadAttendance(emp['id'] as String);
                if (mounted) setState(() => _level = _ReportLevel.calendar);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _drillCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: context.colors.cardBg,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
        ),
        title: Text(title,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600)),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
        onTap: onTap,
      ),
    );
  }

  String _roleName(String role) {
    switch (role) {
      case 'hr':
        return S.hrTitle;
      case 'branchAdmin':
        return S.branchAdminTitle;
      case 'superAdmin':
        return S.superAdminTitle;
      default:
        return S.employeeTitle;
    }
  }

  IconData _iconForRole(String role) {
    switch (role) {
      case 'hr':
        return Icons.badge_outlined;
      case 'branchAdmin':
        return Icons.shield_outlined;
      case 'superAdmin':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.person_outline;
    }
  }

  Widget _buildCalendar() {
    // Managers view an employee's attendance in the same rich layout as the
    // employee's own screen — but read-only (canEdit: false, no edit callback).
    // Tapping a day opens the existing read-only detail sheet (incl. requests).
    return AttendanceCalendar(
      month: _selectedMonth,
      records: _attendanceRecords,
      canEdit: false,
      showStatusLegend: true,
      onPrevMonth: () => setState(() {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      }),
      onNextMonth: () => setState(() {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      }),
      onTapDay: _showDayDetailForDate,
    );
  }

  /// Gathers the records/status/requests for [date] and opens the read-only
  /// day detail sheet (no-op when there's nothing to show).
  void _showDayDetailForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final records = _attendanceRecords
        .where((r) =>
            r.type != 'day_status' &&
            DateFormat('yyyy-MM-dd').format(r.timestamp) == dateKey)
        .toList();
    String status = '';
    for (final r in _attendanceRecords) {
      if (r.type == 'day_status' && (r.date ?? '') == dateKey) {
        status = r.dayStatus ?? '';
      }
    }
    final dayRequests = _employeeRequests.where((r) {
      if (r.startDate == null) return false;
      final s = DateFormat('yyyy-MM-dd').format(r.startDate!);
      final e = r.endDate != null
          ? DateFormat('yyyy-MM-dd').format(r.endDate!)
          : s;
      return dateKey.compareTo(s) >= 0 && dateKey.compareTo(e) <= 0;
    }).toList();
    // An explicit status override (vacation/absent/holiday) supersedes any
    // punches for the day — don't list attend/leave times alongside it, or the
    // detail contradicts the calendar (data-conflict fix).
    final isOverride =
        status == 'vacation' || status == 'absent' || status == 'holiday';
    final shownRecords = isOverride ? <AttendanceRecord>[] : records;
    if (shownRecords.isEmpty && status.isEmpty && dayRequests.isEmpty) return;
    _showDayDetail(date, shownRecords, status, dayRequests);
  }

  void _showDayDetail(
      DateTime date, List<AttendanceRecord> records, String status, [List<AppRequest> dayRequests = const []]) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.cardBg,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMMM d, yyyy', S.locale.languageCode).format(date),
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
            ],
            const SizedBox(height: 12),
            // Sign-in / Sign-out records
            if (records.isEmpty && dayRequests.isEmpty && status.isEmpty)
              Text(S.noRecordsForThisDay,
                  style: TextStyle(color: context.colors.textSecondary))
            else ...[  
              ...records.map((r) {
                final type = r.type;
                final isIn = type == 'sign_in' || type == 'check_in';
                final isBreak = type == 'break_start' || type == 'break_end';
                final isOut = type == 'sign_out' || type == 'check_out';
                if (!isIn && !isOut && !isBreak) return const SizedBox.shrink();
                IconData icon;
                Color color;
                String label;
                if (isIn) {
                  icon = Icons.login; color = AppTheme.accentGreen; label = S.signIn;
                } else if (isOut) {
                  icon = Icons.logout; color = AppTheme.checkOutRed; label = S.signOut;
                } else if (type == 'break_start') {
                  icon = Icons.coffee; color = Colors.orange; label = S.breakStart;
                } else {
                  icon = Icons.play_circle_outline; color = Colors.orange; label = S.breakEnd;
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('h:mm a', S.locale.languageCode).format(r.timestamp),
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(label, style: TextStyle(color: ctx.colors.textSecondary, fontSize: 12)),
                    ],
                  ),
                );
              }),
              // Applied requests section
              if (dayRequests.isNotEmpty) ...[  
                const Divider(height: 20),
                Text(S.requests,
                    style: TextStyle(
                        color: ctx.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                ...dayRequests.map((req) {
                  final statusColor = req.status == RequestStatus.approved
                      ? AppTheme.accentGreen
                      : req.status == RequestStatus.rejected
                          ? AppTheme.checkOutRed
                          : Colors.orange;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            req.typeDisplayName,
                            style: TextStyle(color: ctx.colors.textPrimary, fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            req.status.name.toUpperCase(),
                            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildEmpty(String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 64,
              color: context.colors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: context.colors.textSecondary)),
        ],
      ),
    );
  }
}
