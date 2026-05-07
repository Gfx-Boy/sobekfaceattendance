import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/attendance_record.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Admin/HR view to set per-day attendance status for any employee in scope.
/// This is distinct from the user's own attendance calendar; HR uses this
/// screen to mark holidays/vacations etc. on an employee's behalf.
class SetDayStatusScreen extends StatefulWidget {
  const SetDayStatusScreen({super.key});

  @override
  State<SetDayStatusScreen> createState() => _SetDayStatusScreenState();
}

class _SetDayStatusScreenState extends State<SetDayStatusScreen> {
  bool _loadingEmployees = true;
  bool _loadingRecords = false;
  List<Employee> _employees = [];
  List<Employee> _filtered = [];
  Employee? _selected;
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceRecord> _records = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmployees());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _loadingEmployees = true);
    try {
      final me = context.read<AuthProvider>().employee;
      final branchId =
          me?.role == UserRole.superAdmin ? null : me?.branchId;
      final list = await ApiService().getAllEmployees(branchId: branchId);
      // #6 admin cannot see himself in monitor/set status
      _employees = list.where((e) => e.id != me?.id).toList();
      _filtered = _employees;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
    if (mounted) setState(() => _loadingEmployees = false);
  }

  Future<void> _loadRecords(String employeeId) async {
    setState(() => _loadingRecords = true);
    try {
      _records = await ApiService().getAttendanceHistory(employeeId);
    } catch (_) {
      _records = [];
    }
    if (mounted) setState(() => _loadingRecords = false);
  }

  void _applySearch(String q) {
    final needle = q.trim().toLowerCase();
    setState(() {
      _filtered = needle.isEmpty
          ? _employees
          : _employees
              .where((e) =>
                  e.name.toLowerCase().contains(needle) ||
                  e.email.toLowerCase().contains(needle) ||
                  (e.position ?? '').toLowerCase().contains(needle))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected == null
            ? S.setDayStatusTitle
            : '${_selected!.name} — ${S.dayStatus}'),
        leading: _selected != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selected = null),
              )
            : null,
      ),
      body: _selected == null ? _buildEmployeePicker() : _buildCalendar(),
    );
  }

  Widget _buildEmployeePicker() {
    if (_loadingEmployees) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _applySearch,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: S.searchEmployee,
              prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
              filled: true,
              fillColor: context.colors.cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.colors.surfaceBorder),
              ),
            ),
          ),
        ),
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(S.noEmployees,
                      style: TextStyle(color: context.colors.textSecondary)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final e = _filtered[i];
                    return Card(
                      color: context.colors.cardBg,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppTheme.primaryBlue.withValues(alpha: 0.2),
                          child: Text(
                            e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                            style:
                                const TextStyle(color: AppTheme.primaryBlue),
                          ),
                        ),
                        title: Text(e.name,
                            style: TextStyle(
                                color: context.colors.textPrimary)),
                        subtitle: Text(
                            e.position ?? e.department,
                            style: TextStyle(
                                color: context.colors.textSecondary)),
                        trailing: Icon(Icons.chevron_right,
                            color: context.colors.textMuted),
                        onTap: () {
                          setState(() => _selected = e);
                          _loadRecords(e.id);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCalendar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left,
                    color: context.colors.textPrimary),
                onPressed: () => setState(() {
                  _selectedMonth = DateTime(
                      _selectedMonth.year, _selectedMonth.month - 1);
                }),
              ),
              Text(
                '${S.months[_selectedMonth.month - 1]} ${_selectedMonth.year}',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: context.colors.textPrimary),
                onPressed: () => setState(() {
                  _selectedMonth = DateTime(
                      _selectedMonth.year, _selectedMonth.month + 1);
                }),
              ),
            ],
          ),
        ),
        if (_loadingRecords)
          const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator())
        else
          Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildGrid() {
    final daysInMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final statusByDate = <String, String>{};
    for (final r in _records) {
      if (r.type == 'day_status' && r.date != null) {
        statusByDate[r.date!] = r.dayStatus ?? '';
      }
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.9,
      ),
      itemCount: daysInMonth,
      itemBuilder: (_, i) {
        final day = i + 1;
        final dateStr =
            '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        final st = statusByDate[dateStr];
        Color? bg;
        switch (st) {
          case 'vacation':
            bg = AppTheme.primaryBlue.withValues(alpha: 0.25);
            break;
          case 'holiday':
            bg = AppTheme.warningAmber.withValues(alpha: 0.25);
            break;
          case 'absent':
            bg = AppTheme.checkOutRed.withValues(alpha: 0.25);
            break;
          case 'attend':
            bg = AppTheme.accentGreen.withValues(alpha: 0.25);
            break;
        }
        return GestureDetector(
          onTap: () => _pickStatus(dateStr),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: bg ?? context.colors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: context.colors.surfaceBorder, width: 0.5),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  if (st != null)
                    Text(_short(st),
                        style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 9)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _short(String s) {
    switch (s) {
      case 'vacation':
        return S.vacation;
      case 'holiday':
        return S.holiday;
      case 'absent':
        return S.absent;
      case 'attend':
        return S.signIn;
      default:
        return s;
    }
  }

  Future<void> _pickStatus(String date) async {
    final statuses = ['attend', 'vacation', 'absent', 'holiday'];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${S.dayStatus}: $date'),
        children: statuses
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text(_short(s)),
                ))
            .toList(),
      ),
    );
    if (selected == null || _selected == null) return;
    try {
      await ApiService().setDayStatus(
        employeeId: _selected!.id,
        date: date,
        status: selected,
      );
      await _loadRecords(_selected!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.dayStatus}: ${_short(selected)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }
}
