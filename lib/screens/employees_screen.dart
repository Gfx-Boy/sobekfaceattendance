import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _employees = [];
  List<Employee> _filtered = [];
  List<Branch> _branches = [];
  Map<String, int> _branchEmployeeCounts = {};
  Branch? _selectedBranch; // SA: pick branch first
  bool _loading = true;
  String? _error;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterEmployees);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final role = context.read<AuthProvider>().employee?.role;
      if (role == UserRole.superAdmin) {
        _loadBranches();
      } else {
        _loadEmployees();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterEmployees() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _employees
          : _employees.where((e) =>
              e.name.toLowerCase().contains(query) ||
              e.email.toLowerCase().contains(query) ||
              e.department.toLowerCase().contains(query)).toList();
    });
  }

  Future<void> _loadBranches() async {
    try {
      setState(() { _loading = true; _error = null; });
      final branches = await ApiService().getBranches();
      // Compute employee counts directly from the employees list
      // (more reliable than the backend-stored count)
      Map<String, int> counts = {};
      try {
        final allEmps = await ApiService().getAllEmployees();
        for (final e in allEmps) {
          if (e.branchId != null && e.branchId!.isNotEmpty) {
            counts[e.branchId!] = (counts[e.branchId!] ?? 0) + 1;
          }
        }
      } catch (_) {}
      if (mounted) setState(() {
        _branches = branches;
        _branchEmployeeCounts = counts;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadEmployees() async {
    try {
      setState(() => _loading = true);
      final me = context.read<AuthProvider>().employee;
      String? branchId;
      if (me?.role == UserRole.superAdmin) {
        branchId = _selectedBranch?.id;
      } else if (me?.role == UserRole.branchAdmin || me?.role == UserRole.hr) {
        branchId = me?.branchId;
      }
      List<Employee> employees = await ApiService().getAllEmployees(branchId: branchId);
      // HR should not see branchAdmin in the list
      if (me?.role == UserRole.hr) {
        employees = employees.where((e) => e.role != UserRole.branchAdmin).toList();
      }
      if (mounted) {
        setState(() {
          _employees = employees;
          _filtered = employees;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleHold(Employee emp) async {
    final newHoldState = !emp.isOnHold;
    final action = newHoldState ? 'hold' : 'unhold';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newHoldState ? S.holdAccount : S.unholdAccount),
        content: Text(newHoldState ? S.holdConfirmMessage(emp.name) : S.unholdConfirmMessage(emp.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(newHoldState ? S.holdAccount : S.unholdAccount, style: TextStyle(color: newHoldState ? AppTheme.warningAmber : AppTheme.accentGreen)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService().updateEmployee(emp.id, {'is_on_hold': newHoldState});
        _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(newHoldState ? S.accountHeld : S.accountUnheld), backgroundColor: AppTheme.accentGreen),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
          );
        }
      }
    }
  }

  Future<void> _deleteEmployee(Employee emp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.deleteEmployee),
        content: Text(S.deleteConfirmMessage(emp.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.delete, style: TextStyle(color: AppTheme.checkOutRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService().deleteEmployee(emp.id);
        _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.employeeDeleted), backgroundColor: AppTheme.accentGreen),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().employee?.role ?? UserRole.employee;
    final isSA = role == UserRole.superAdmin;

    // SA with no branch selected → show branches
    if (isSA && _selectedBranch == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(S.selectBranch),
          actions: [IconButton(icon: Icon(Icons.refresh), onPressed: _loadBranches)],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: AppTheme.checkOutRed)))
                : _branches.isEmpty
                    ? Center(child: Text(S.noBranchesFound, style: TextStyle(color: context.colors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _branches.length,
                        itemBuilder: (ctx, i) {
                          final b = _branches[i];
                          Color statusColor = b.status == 'work' ? AppTheme.accentGreen : b.status == 'hold' ? AppTheme.warningAmber : AppTheme.checkOutRed;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: context.colors.cardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                                child: Icon(Icons.business, color: AppTheme.primaryBlue),
                              ),
                              title: Text(b.name, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (b.address.isNotEmpty) Text(b.address, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                                  Row(children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(b.status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w500)),
                                    ),
                                    SizedBox(width: 8),
                                    Text(S.employeeCountLabel(_branchEmployeeCounts[b.id] ?? b.employeeCount), style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                                  ]),
                                ],
                              ),
                              trailing: Icon(Icons.chevron_right, color: context.colors.textSecondary),
                              onTap: () {
                                setState(() => _selectedBranch = b);
                                _loadEmployees();
                              },
                            ),
                          );
                        },
                      ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isSA ? _selectedBranch!.name : S.employees),
        leading: isSA
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() { _selectedBranch = null; _employees = []; _filtered = []; }),
              )
            : null,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadEmployees),
        ],
      ),
      floatingActionButton: Builder(
        builder: (context) {
          final r = context.watch<AuthProvider>().employee?.role;
          if (r == UserRole.superAdmin || r == UserRole.branchAdmin || r == UserRole.hr) {
            return FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/add-employee').then((_) => _loadEmployees()),
              backgroundColor: AppTheme.primaryBlue,
              child: const Icon(Icons.person_add, color: Colors.white),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: AppTheme.checkOutRed)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: InputDecoration(
                          hintText: S.searchEmployees,
                          prefixIcon: Icon(Icons.search, color: context.colors.textSecondary),
                          filled: true,
                          fillColor: context.colors.cardBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.colors.surfaceBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: context.colors.surfaceBorder),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        S.employeeCountLabel(_filtered.length),
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                      ),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(child: Text(S.noEmployeesFound, style: TextStyle(color: context.colors.textSecondary)))
                          : RefreshIndicator(
                              onRefresh: _loadEmployees,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: _filtered.length,
                                itemBuilder: (context, index) {
                                  final emp = _filtered[index];
                                  return _employeeCard(emp);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _employeeCard(Employee emp) {
    final me = context.read<AuthProvider>().employee;
    Color roleColor;
    switch (emp.role) {
      case UserRole.superAdmin: roleColor = AppTheme.checkOutRed; break;
      case UserRole.branchAdmin: roleColor = AppTheme.warningAmber; break;
      case UserRole.hr: roleColor = AppTheme.primaryBlue; break;
      case UserRole.employee: roleColor = AppTheme.accentGreen; break;
    }

    // Cannot delete yourself or superAdmin
    final canDelete = emp.role != UserRole.superAdmin && emp.id != me?.id;
    // HR cannot edit branchAdmin
    final canEdit = !(me?.role == UserRole.hr && emp.role == UserRole.branchAdmin);
    // Can toggle hold: SA can hold anyone except SA, BA can hold branch employees, HR can hold non-BA
    final canHold = emp.id != me?.id && emp.role != UserRole.superAdmin &&
        !(me?.role == UserRole.hr && emp.role == UserRole.branchAdmin);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: roleColor.withValues(alpha: 0.2),
          backgroundImage: emp.profileImageUrl != null ? NetworkImage(emp.profileImageUrl!) : null,
          child: emp.profileImageUrl == null
              ? Text(
                  emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                )
              : null,
        ),
        title: Text(emp.name, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emp.email, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(emp.roleDisplayName, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.w500)),
                ),
                if (emp.isOnHold) ...[
                  SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warningAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(S.onHold, style: TextStyle(color: AppTheme.warningAmber, fontSize: 9, fontWeight: FontWeight.w600)),
                  ),
                ],
                SizedBox(width: 6),
                Text(emp.department, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                if (emp.branchName != null) ...[
                  SizedBox(width: 6),
                  Icon(Icons.business, size: 11, color: context.colors.textMuted),
                  SizedBox(width: 2),
                  Flexible(child: Text(emp.branchName!, style: TextStyle(color: context.colors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis)),
                ],
              ],
            ),
          ],
        ),
        trailing: emp.role == UserRole.superAdmin || (!canDelete && !canEdit && !canHold)
            ? null
            : PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: context.colors.textSecondary),
          color: context.colors.cardBgLighter,
          onSelected: (value) {
            if (value == 'delete') _deleteEmployee(emp);
            if (value == 'edit') Navigator.pushNamed(context, '/edit-employee', arguments: emp).then((result) {
              if (result is Employee && mounted) {
                setState(() {
                  final idx = _employees.indexWhere((e) => e.id == result.id);
                  if (idx != -1) _employees[idx] = result;
                  final fidx = _filtered.indexWhere((e) => e.id == result.id);
                  if (fidx != -1) _filtered[fidx] = result;
                });
                Future.delayed(const Duration(seconds: 2), _loadEmployees);
              }
            });
            if (value == 'hold') _toggleHold(emp);
          },
          itemBuilder: (context) => [
            if (canEdit)
              PopupMenuItem(value: 'edit', child: Text(S.edit)),
            if (canHold)
              PopupMenuItem(
                value: 'hold',
                child: Text(
                  emp.isOnHold ? S.unholdAccount : S.holdAccount,
                  style: TextStyle(color: emp.isOnHold ? AppTheme.accentGreen : AppTheme.warningAmber),
                ),
              ),
            if (canDelete)
              PopupMenuItem(value: 'delete', child: Text(S.delete, style: TextStyle(color: AppTheme.checkOutRed))),
          ],
        ),
      ),
    );
  }
}
