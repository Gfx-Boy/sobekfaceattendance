import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../models/attendance_record.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

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
      _allBranchEmployees = employees
          .where((e) => e.role != UserRole.superAdmin && e.id != myId)
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
      _attendanceRecords = await ApiService().getAttendanceHistory(employeeId);
    } catch (_) {
      _attendanceRecords = [];
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
    final Map<String, List<AttendanceRecord>> dayRecords = {};
    final Map<String, String> dayStatus = {};

    for (final r in _attendanceRecords) {
      if (r.type == 'day_status') {
        final date = r.date ?? '';
        if (date.isNotEmpty) dayStatus[date] = r.dayStatus ?? '';
      } else {
        final key = DateFormat('yyyy-MM-dd').format(r.timestamp);
        dayRecords.putIfAbsent(key, () => []).add(r);
      }
    }

    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final startOffset = firstDay.weekday % 7;

    return Column(
      children: [
        _buildMonthSelector(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: S.weekDaysSun
                .map((d) => Expanded(
                    child: Center(
                        child: Text(d,
                            style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)))))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.85,
            ),
            itemCount: startOffset + lastDay.day,
            itemBuilder: (context, index) {
              if (index < startOffset) return const SizedBox();
              final day = index - startOffset + 1;
              final date =
                  DateTime(_selectedMonth.year, _selectedMonth.month, day);
              final dateKey = DateFormat('yyyy-MM-dd').format(date);
              final records = dayRecords[dateKey] ?? [];
              final status = dayStatus[dateKey] ?? '';
              final isWeekend = date.weekday == DateTime.saturday ||
                  date.weekday == DateTime.sunday;
              final isToday =
                  dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now());

              Color bgColor = Colors.transparent;
              if (isWeekend || status == 'holiday') {
                bgColor = context.colors.textMuted.withValues(alpha: 0.15);
              } else if (status == 'vacation') {
                bgColor = AppTheme.primaryBlue.withValues(alpha: 0.15);
              } else if (status == 'absent') {
                bgColor = AppTheme.checkOutRed.withValues(alpha: 0.15);
              }

              final signIns = records
                  .where((r) => r.type == 'sign_in' || r.type == 'check_in')
                  .toList();
              final signOuts = records
                  .where((r) => r.type == 'sign_out' || r.type == 'check_out')
                  .toList();

              return GestureDetector(
                onTap: (records.isEmpty && status.isEmpty)
                    ? null
                    : () => _showDayDetail(date, records, status),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: isToday
                        ? Border.all(color: AppTheme.primaryBlue, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day',
                          style: TextStyle(
                            color: isWeekend
                                ? context.colors.textMuted
                                : context.colors.textPrimary,
                            fontWeight:
                                isToday ? FontWeight.w700 : FontWeight.w400,
                            fontSize: 13,
                          )),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (signIns.isNotEmpty)
                            Container(
                                width: 5,
                                height: 5,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                decoration: const BoxDecoration(
                                    color: AppTheme.accentGreen,
                                    shape: BoxShape.circle)),
                          if (signOuts.isNotEmpty)
                            Container(
                                width: 5,
                                height: 5,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                decoration: const BoxDecoration(
                                    color: AppTheme.checkOutRed,
                                    shape: BoxShape.circle)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildLegend(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon:
                Icon(Icons.chevron_left, color: context.colors.textSecondary),
            onPressed: () => setState(() {
              _selectedMonth =
                  DateTime(_selectedMonth.year, _selectedMonth.month - 1);
            }),
          ),
          Text(
            DateFormat('MMMM yyyy', S.locale.languageCode).format(_selectedMonth),
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16),
          ),
          IconButton(
            icon:
                Icon(Icons.chevron_right, color: context.colors.textSecondary),
            onPressed: () => setState(() {
              _selectedMonth =
                  DateTime(_selectedMonth.year, _selectedMonth.month + 1);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _legendDot(AppTheme.accentGreen, S.signIn),
          _legendDot(AppTheme.checkOutRed, S.signOut),
          _legendDot(AppTheme.primaryBlue.withValues(alpha: 0.5), S.vacation),
          _legendDot(
              context.colors.textMuted.withValues(alpha: 0.5), S.weekend),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(color: context.colors.textMuted, fontSize: 10)),
      ],
    );
  }

  void _showDayDetail(
      DateTime date, List<AttendanceRecord> records, String status) {
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
            if (records.isEmpty)
              Text(S.noRecordsForThisDay,
                  style: TextStyle(color: context.colors.textSecondary))
            else
              ...records.map((r) {
                final isIn = r.type == 'sign_in' || r.type == 'check_in';
                final dt = r.timestamp;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(isIn ? Icons.login : Icons.logout,
                          color: isIn
                              ? AppTheme.accentGreen
                              : AppTheme.checkOutRed,
                          size: 18),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('h:mm a', S.locale.languageCode).format(dt),
                        style: TextStyle(
                            color: isIn
                                ? AppTheme.accentGreen
                                : AppTheme.checkOutRed,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Text(isIn ? S.signIn : S.signOut,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12)),
                    ],
                  ),
                );
              }),
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
