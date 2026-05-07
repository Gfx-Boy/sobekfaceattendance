import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../models/appraisal.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

enum _AppraisalLevel { branches, periods, titles, employees, appraisals }

class AppraisalsScreen extends StatefulWidget {
  const AppraisalsScreen({super.key});

  @override
  State<AppraisalsScreen> createState() => _AppraisalsScreenState();
}

class _AppraisalsScreenState extends State<AppraisalsScreen> {
  bool _loading = true;

  _AppraisalLevel _level = _AppraisalLevel.branches;

  Map<String, Employee> _employeesMap = {};
  List<Branch> _branches = [];
  List<Appraisal> _allAppraisals = [];

  Branch? _selectedBranch;
  String? _selectedPeriod;
  String? _selectedTitleRole;
  Employee? _selectedEmployee;

  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _titles = [];
  List<Map<String, dynamic>> _empItems = [];
  List<Appraisal> _appraisals = [];

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
      setState(() => _level = _AppraisalLevel.employees);
      await _loadBranchAppraisals();
    }
  }

  Future<void> _loadSuperAdminData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().getAllEmployees(),
        ApiService().getBranches(),
        ApiService().getAllAppraisals(),
      ]);
      final employees = results[0] as List<Employee>;
      _branches = results[1] as List<Branch>;
      _allAppraisals = results[2] as List<Appraisal>;

      _employeesMap = {for (final e in employees) e.id: e};
    } catch (e) {
      debugPrint('Load appraisals error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBranchAppraisals() async {
    setState(() => _loading = true);
    try {
      final branchId = context.read<AuthProvider>().employee?.branchId;
      final employees = await ApiService().getAllEmployees(branchId: branchId);
      _employeesMap = {for (final e in employees) e.id: e};

      final all = <Appraisal>[];
      for (final emp in employees) {
        try {
          final empAppraisals = await ApiService().getAppraisals(emp.id);
          all.addAll(empAppraisals);
        } catch (_) {}
      }
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _appraisals = all;
      _allAppraisals = all;
    } catch (e) {
      debugPrint('Load branch appraisals error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _buildPeriodsForBranch() {
    final appraisals = _allAppraisals.where((a) {
      final emp = _employeesMap[a.employeeId];
      return a.branchId == _selectedBranch?.id || emp?.branchId == _selectedBranch?.id;
    }).toList();

    final counts = <String, int>{};
    for (final a in appraisals) {
      counts[a.period] = (counts[a.period] ?? 0) + 1;
    }
    final sortedPeriods = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    _periods = sortedPeriods
        .map((p) => <String, dynamic>{'period': p, 'count': counts[p]})
        .toList();
  }

  void _buildTitlesForPeriod() {
    final appraisals = _allAppraisals.where((a) {
      if (a.period != _selectedPeriod) return false;
      final emp = _employeesMap[a.employeeId];
      return a.branchId == _selectedBranch?.id || emp?.branchId == _selectedBranch?.id;
    }).toList();

    final counts = <String, int>{};
    for (final a in appraisals) {
      final emp = _employeesMap[a.employeeId];
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
    final appraisals = _allAppraisals.where((a) {
      if (a.period != _selectedPeriod) return false;
      final emp = _employeesMap[a.employeeId];
      if (emp == null) return false;
      final role = emp.role.name;
      if (role != _selectedTitleRole) return false;
      return a.branchId == _selectedBranch?.id || emp.branchId == _selectedBranch?.id;
    }).toList();

    final seen = <String>{};
    _empItems = [];
    for (final a in appraisals) {
      if (seen.contains(a.employeeId)) continue;
      seen.add(a.employeeId);
      final emp = _employeesMap[a.employeeId];
      _empItems.add(<String, dynamic>{
        'id': a.employeeId,
        'name': a.employeeName,
        'count': appraisals.where((x) => x.employeeId == a.employeeId).length,
        'image': emp?.profileImageUrl ?? '',
      });
    }
    _empItems.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  }

  void _buildAppraisalsForEmployee() {
    _appraisals = _allAppraisals
        .where((a) =>
            a.employeeId == _selectedEmployee?.id &&
            a.period == _selectedPeriod)
        .toList();
    _appraisals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _goBack() {
    if (_level == _AppraisalLevel.appraisals) {
      setState(() {
        _level = _AppraisalLevel.employees;
        _selectedEmployee = null;
        _appraisals = [];
      });
    } else if (_level == _AppraisalLevel.employees) {
      setState(() {
        _level = _AppraisalLevel.titles;
        _selectedTitleRole = null;
        _empItems = [];
      });
    } else if (_level == _AppraisalLevel.titles) {
      setState(() {
        _level = _AppraisalLevel.periods;
        _selectedPeriod = null;
        _titles = [];
      });
    } else if (_level == _AppraisalLevel.periods) {
      setState(() {
        _level = _AppraisalLevel.branches;
        _selectedBranch = null;
        _periods = [];
      });
    }
  }

  bool get _canGoBack {
    if (!_isSA) return false;
    return _level != _AppraisalLevel.branches;
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().employee?.role;
    final canSeeCycles = role == UserRole.superAdmin ||
        role == UserRole.branchAdmin ||
        role == UserRole.hr;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.appraisals),
        leading: _canGoBack
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack)
            : null,
        actions: [
          if (canSeeCycles)
            IconButton(
              tooltip: S.appraisalCycles,
              icon: const Icon(Icons.event_note_outlined),
              onPressed: () => Navigator.pushNamed(
                context,
                '/appraisal-cycles',
              ).then((_) {
                if (_isSA) {
                  _loadSuperAdminData();
                } else {
                  _loadBranchAppraisals();
                }
              }),
            ),
        ],
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
    if (_level == _AppraisalLevel.appraisals && _selectedEmployee != null) {
      // #23/#37 — HR cannot appraise a Branch Admin
      if (role == UserRole.hr &&
          _selectedEmployee!.role == UserRole.branchAdmin) {
        return null;
      }
      return FloatingActionButton(
        onPressed: () => _showCreateAppraisalDialog(),
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }
    return null;
  }

  Widget _buildBody() {
    switch (_level) {
      case _AppraisalLevel.branches:
        return _buildBranchesList();
      case _AppraisalLevel.periods:
        return _buildPeriodsList();
      case _AppraisalLevel.titles:
        return _buildTitlesList();
      case _AppraisalLevel.employees:
        return _isSA ? _buildEmployeesList() : _buildAppraisalsList();
      case _AppraisalLevel.appraisals:
        return _buildAppraisalsList();
    }
  }

  Widget _buildBranchesList() {
    if (_branches.isEmpty) {
      return _buildEmpty(S.noBranchesFound, Icons.business_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadSuperAdminData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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
              setState(() => _level = _AppraisalLevel.periods);
            },
          );
        },
      ),
    );
  }

  Widget _buildPeriodsList() {
    if (_periods.isEmpty) {
      return _buildEmpty(S.noEvaluations, Icons.assessment_outlined);
    }
    return RefreshIndicator(
      onRefresh: _loadSuperAdminData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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
              setState(() => _level = _AppraisalLevel.titles);
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
              _buildEmployeesForTitle();
              setState(() => _level = _AppraisalLevel.employees);
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
        padding: const EdgeInsets.all(16),
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
                _buildAppraisalsForEmployee();
                setState(() => _level = _AppraisalLevel.appraisals);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppraisalsList() {
    if (_appraisals.isEmpty) {
      return _buildEmpty(S.noEvaluations, Icons.assessment_outlined);
    }
    return RefreshIndicator(
      onRefresh: _isSA ? _loadSuperAdminData : _loadBranchAppraisals,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _appraisals.length,
        itemBuilder: (context, i) {
          final a = _appraisals[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        a.employeeName,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: a.overallScore >= 70
                            ? AppTheme.accentGreen.withValues(alpha: 0.15)
                            : AppTheme.checkOutRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${a.overallScore.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: a.overallScore >= 70
                              ? AppTheme.accentGreen
                              : AppTheme.checkOutRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${S.period}: ${a.period}',
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 12),
                ),
                if (a.evaluatorName.isNotEmpty)
                  Text(
                    '${S.evaluator}: ${a.evaluatorName}',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11),
                  ),
                if (a.comments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    a.comments,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
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

  void _showCreateAppraisalDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.newEvaluation),
        content: const Text('Create appraisal dialog'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(S.cancel)),
        ],
      ),
    );
  }
}
