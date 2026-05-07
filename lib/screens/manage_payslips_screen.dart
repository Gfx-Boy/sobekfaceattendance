import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../models/payslip.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

enum _PayslipLevel { branches, periods, titles, employees, payslips }

class ManagePayslipsScreen extends StatefulWidget {
  const ManagePayslipsScreen({super.key});

  @override
  State<ManagePayslipsScreen> createState() => _ManagePayslipsScreenState();
}

class _ManagePayslipsScreenState extends State<ManagePayslipsScreen> {
  bool _loading = true;

  // Super Admin drill-down levels
  _PayslipLevel _level = _PayslipLevel.branches;

  // Employees map for cross-referencing (employeeId -> role, branchId, name)
  Map<String, Employee> _employeesMap = {};
  List<Branch> _branches = [];
  List<Payslip> _allPayslips = [];

  // Selected drill-down state
  Branch? _selectedBranch;
  String? _selectedPeriod;
  String? _selectedTitleRole;
  Employee? _selectedEmployee;

  // Current level items
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _titles = [];
  List<Map<String, dynamic>> _empItems = [];
  List<Payslip> _payslips = [];

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
      await _loadSuperAdminData();
    } else {
      setState(() => _level = _PayslipLevel.employees);
      await _loadBranchPayslips();
    }
  }

  Future<void> _loadSuperAdminData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getAllEmployees(),
        ApiService().getBranches(),
        ApiService().getAllPayslips(),
      ]);
      final employees = results[0] as List<Employee>;
      _branches = results[1] as List<Branch>;
      _allPayslips = results[2] as List<Payslip>;

      _employeesMap = {for (final e in employees) e.id: e};
    } catch (e) {
      debugPrint('Load payslips error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBranchPayslips() async {
    setState(() => _loading = true);
    try {
      final branchId = context.read<AuthProvider>().employee?.branchId;
      final employees = await ApiService().getAllEmployees(branchId: branchId);
      _employeesMap = {for (final e in employees) e.id: e};

      final all = <Payslip>[];
      for (final emp in employees) {
        try {
          final empPayslips = await ApiService().getPayslips(emp.id);
          all.addAll(empPayslips);
        } catch (_) {}
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _payslips = all;
      _allPayslips = all;
    } catch (e) {
      debugPrint('Load branch payslips error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _buildPeriodsForBranch() {
    final payslips = _allPayslips.where((p) {
      final emp = _employeesMap[p.employeeId];
      return p.branchId == _selectedBranch?.id || emp?.branchId == _selectedBranch?.id;
    }).toList();

    final periods = <String, int>{};
    for (final p in payslips) {
      periods[p.period] = (periods[p.period] ?? 0) + 1;
    }
    final sortedPeriods = periods.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    _periods = sortedPeriods
        .map((p) => <String, dynamic>{'period': p, 'count': periods[p]})
        .toList();
  }

  void _buildTitlesForPeriod() {
    final payslips = _allPayslips.where((p) {
      if (p.period != _selectedPeriod) return false;
      final emp = _employeesMap[p.employeeId];
      return p.branchId == _selectedBranch?.id || emp?.branchId == _selectedBranch?.id;
    }).toList();

    final counts = <String, int>{};
    for (final p in payslips) {
      final emp = _employeesMap[p.employeeId];
      final role = emp?.role.name ?? 'employee';
      counts[role] = (counts[role] ?? 0) + 1;
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

  void _buildEmployeesForTitle() {
    final payslips = _allPayslips.where((p) {
      if (p.period != _selectedPeriod) return false;
      final emp = _employeesMap[p.employeeId];
      if (emp == null) return false;
      final role = emp.role.name;
      if (role != _selectedTitleRole) return false;
      return p.branchId == _selectedBranch?.id || emp.branchId == _selectedBranch?.id;
    }).toList();

    final seen = <String>{};
    _empItems = [];
    for (final p in payslips) {
      if (seen.contains(p.employeeId)) continue;
      seen.add(p.employeeId);
      final emp = _employeesMap[p.employeeId];
      _empItems.add(<String, dynamic>{
        'id': p.employeeId,
        'name': p.employeeName,
        'count': payslips.where((x) => x.employeeId == p.employeeId).length,
        'image': emp?.profileImageUrl ?? '',
      });
    }
    _empItems.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));
  }

  void _buildPayslipsForEmployee() {
    _payslips = _allPayslips
        .where((p) =>
            p.employeeId == _selectedEmployee?.id &&
            p.period == _selectedPeriod)
        .toList();
    _payslips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _goBack() {
    if (_level == _PayslipLevel.payslips) {
      setState(() {
        _level = _PayslipLevel.employees;
        _selectedEmployee = null;
        _payslips = [];
      });
    } else if (_level == _PayslipLevel.employees) {
      setState(() {
        _level = _PayslipLevel.titles;
        _selectedTitleRole = null;
        _empItems = [];
      });
    } else if (_level == _PayslipLevel.titles) {
      setState(() {
        _level = _PayslipLevel.periods;
        _selectedPeriod = null;
        _titles = [];
      });
    } else if (_level == _PayslipLevel.periods) {
      setState(() {
        _level = _PayslipLevel.branches;
        _selectedBranch = null;
        _periods = [];
      });
    }
  }

  bool get _canGoBack {
    if (!_isSA) return false;
    return _level != _PayslipLevel.branches;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.payslips),
        leading: _canGoBack
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack)
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: _buildFab(),
    );
  }

  Widget? _buildFab() {
    final role = context.read<AuthProvider>().employee?.role;
    final canCreate = role == UserRole.superAdmin ||
        role == UserRole.branchAdmin ||
        role == UserRole.hr;
    if (!canCreate) return null;

    if (_level == _PayslipLevel.payslips && _selectedEmployee != null) {
      return FloatingActionButton(
        onPressed: () => _showCreatePayslipDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }
    return null;
  }

  Widget _buildBody() {
    switch (_level) {
      case _PayslipLevel.branches:
        return _buildBranchesList();
      case _PayslipLevel.periods:
        return _buildPeriodsList();
      case _PayslipLevel.titles:
        return _buildTitlesList();
      case _PayslipLevel.employees:
        return _isSA ? _buildEmployeesList() : _buildPayslipsList();
      case _PayslipLevel.payslips:
        return _buildPayslipsList();
    }
  }

  Widget _buildBranchesList() {
    if (_branches.isEmpty) {
      return _buildEmpty(S.noBranchesFound, Icons.business_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadSuperAdminData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        itemCount: _branches.length,
        itemBuilder: (context, i) {
          final b = _branches[i];
          return _drillCard(
            icon: Icons.business,
            title: b.name,
            subtitle: b.address.isNotEmpty ? b.address : S.branch,
            onTap: () {
              _selectedBranch = b;
              _buildPeriodsForBranch();
              setState(() => _level = _PayslipLevel.periods);
            },
          );
        },
      ),
    );
  }

  Widget _buildPeriodsList() {
    if (_periods.isEmpty) {
      return _buildEmpty(S.noPayslipsFound, Icons.receipt_long_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadSuperAdminData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        itemCount: _periods.length,
        itemBuilder: (context, i) {
          final p = _periods[i];
          return _drillCard(
            icon: Icons.calendar_month_outlined,
            title: p['period'] as String,
            subtitle: S.employeeCountLabel(p['count'] as int),
            onTap: () {
              _selectedPeriod = p['period'] as String;
              _buildTitlesForPeriod();
              setState(() => _level = _PayslipLevel.titles);
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
      onRefresh: _loadSuperAdminData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
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
              _buildEmployeesForTitle();
              setState(() => _level = _PayslipLevel.employees);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmployeesList() {
    if (_empItems.isEmpty) {
      return _buildEmpty(S.noEmployeesInBranch, Icons.people_outline);
    }
    return RefreshIndicator(
      onRefresh: _loadSuperAdminData,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        itemCount: _empItems.length,
        itemBuilder: (context, i) {
          final emp = _empItems[i];
          final imageUrl = emp['image'] as String;
          final name = emp['name'] as String;
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
              subtitle: Text(
                  S.employeeCountLabel(emp['count'] as int),
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 12)),
              trailing:
                  Icon(Icons.chevron_right, color: context.colors.textMuted),
              onTap: () {
                _selectedEmployee = _employeesMap[emp['id'] as String];
                _buildPayslipsForEmployee();
                setState(() => _level = _PayslipLevel.payslips);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPayslipsList() {
    if (_payslips.isEmpty) {
      return _buildEmpty(S.noPayslipsFound, Icons.receipt_long_outlined);
    }
    return RefreshIndicator(
      onRefresh: _isSA ? _loadSuperAdminData : _loadBranchPayslips,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        itemCount: _payslips.length,
        itemBuilder: (context, i) => _payslipCard(_payslips[i]),
      ),
    );
  }

  Widget _payslipCard(Payslip payslip) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showPayslipDetails(payslip),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  payslip.period,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${payslip.netSalary.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (payslip.employeeName.isNotEmpty)
            Text('${S.employee}: ${payslip.employeeName}',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 12)),
          Text('${S.basicSalary}: ${payslip.basicSalary.toStringAsFixed(2)}',
              style: TextStyle(
                  color: context.colors.textSecondary, fontSize: 12)),
          if (payslip.bonuses > 0)
            Text('${S.bonuses}: +${payslip.bonuses.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppTheme.accentGreen, fontSize: 12)),
          if (payslip.deductions > 0)
            Text('${S.deductions}: -${payslip.deductions.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppTheme.checkOutRed, fontSize: 12)),
          if (payslip.overtimePay > 0)
            Text('${S.overtimePay}: +${payslip.overtimePay.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppTheme.primaryBlue, fontSize: 12)),
        ],
      ),
        ),
      ),
    );
  }

  Future<void> _showPayslipDetails(Payslip p) async {
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 13)),
              Text(value,
                  style: TextStyle(
                      color: color ?? context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        title: Text('${S.payslip} · ${p.period}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (p.employeeName.isNotEmpty)
                row(S.employee, p.employeeName),
              row(S.basicSalary, p.basicSalary.toStringAsFixed(2)),
              if (p.bonuses > 0)
                row(S.bonuses, '+${p.bonuses.toStringAsFixed(2)}',
                    color: AppTheme.accentGreen),
              if (p.overtimePay > 0)
                row(S.overtimePay, '+${p.overtimePay.toStringAsFixed(2)}',
                    color: AppTheme.primaryBlue),
              if (p.deductions > 0)
                row(S.deductions, '-${p.deductions.toStringAsFixed(2)}',
                    color: AppTheme.checkOutRed),
              const Divider(height: 18),
              row(S.netSalary, p.netSalary.toStringAsFixed(2),
                  color: AppTheme.accentGreen),
              if (p.paymentDate != null && p.paymentDate!.isNotEmpty)
                row(S.paymentDate, p.paymentDate!),
              if (p.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(S.notesOptional,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(p.notes,
                    style: TextStyle(
                        color: context.colors.textPrimary, fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(S.close)),
        ],
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
      default:
        return Icons.person_outline;
    }
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

  Future<void> _showCreatePayslipDialog() async {
    final emp = _selectedEmployee;
    if (emp == null) return;
    DateTime selectedMonth = _selectedPeriod != null
        ? DateTime.parse('$_selectedPeriod-01')
        : DateTime(DateTime.now().year, DateTime.now().month);
    Map<String, dynamic>? preview;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> runPreview() async {
          setS(() => busy = true);
          try {
            final period =
                '${selectedMonth.year}-${selectedMonth.month.toString().padLeft(2, '0')}';
            final p = await ApiService()
                .generatePayslip(employeeId: emp.id, period: period);
            setS(() => preview = p);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed));
            }
          } finally {
            setS(() => busy = false);
          }
        }

        Future<void> save() async {
          setS(() => busy = true);
          try {
            final period =
                '${selectedMonth.year}-${selectedMonth.month.toString().padLeft(2, '0')}';
            await ApiService().generatePayslip(
                employeeId: emp.id, period: period, save: true);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(S.savedSuccessfully)));
              _refreshAfterCreate();
            }
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed));
            }
          } finally {
            setS(() => busy = false);
          }
        }

        final period =
            '${selectedMonth.year}-${selectedMonth.month.toString().padLeft(2, '0')}';
        return AlertDialog(
          backgroundColor: context.colors.cardBg,
          title: Text(S.createPayslip),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(emp.name,
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: Text(period),
                          onPressed: busy
                              ? null
                              : () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedMonth,
                                    firstDate: DateTime(now.year - 3),
                                    lastDate: DateTime(now.year + 1, 12),
                                  );
                                  if (picked != null) {
                                    setS(() {
                                      selectedMonth = DateTime(picked.year, picked.month);
                                      preview = null;
                                    });
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: busy ? null : runPreview,
                        child: Text(S.calculate),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (busy) const Center(child: CircularProgressIndicator()),
                  if (!busy && preview != null) _buildPreview(preview!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(S.cancel)),
            ElevatedButton(
              onPressed: (busy || preview == null) ? null : save,
              child: Text(S.save),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildPreview(Map<String, dynamic> p) {
    final bd = (p['breakdown'] as Map?) ?? const {};
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(k,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 13)),
              Text(v,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(S.basicSalary, '${p['basic_salary']}'),
        row(S.bonuses, '${p['bonuses']}'),
        row(S.deductions, '${p['deductions']}'),
        row(S.overtimePay, '${p['overtime_pay']}'),
        const Divider(),
        row(S.netSalary, '${p['net_salary']}'),
        const SizedBox(height: 8),
        Text(S.breakdown,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600)),
        row(S.presentDays, '${bd['present_days'] ?? 0}'),
        row(S.absentDays, '${bd['absent_days'] ?? 0}'),
        row(S.lateCount, '${bd['late_count'] ?? 0}'),
        row(S.earlyOutCount, '${bd['early_out_count'] ?? 0}'),
        row(S.overtimeMinutes, '${bd['overtime_minutes'] ?? 0}'),
      ],
    );
  }

  void _refreshAfterCreate() {
    if (_isSA) {
      _loadSuperAdminData();
    } else {
      _loadBranchPayslips();
    }
  }
}
