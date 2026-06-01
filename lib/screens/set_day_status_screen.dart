import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/attendance_record.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Admin/HR view to set per-day attendance status for any employee in scope.
///
/// Super Admin drills down like the Tasks screen:
///   branch → titles → employees → month calendar.
/// Branch Admin / HR see their own branch employees directly.
///
/// "Branch Status" applies a status to every employee in a branch. For a
/// Super Admin this first asks which branch the rule applies to (#20), then
/// opens that branch's month calendar.
class SetDayStatusScreen extends StatefulWidget {
  const SetDayStatusScreen({super.key});

  @override
  State<SetDayStatusScreen> createState() => _SetDayStatusScreenState();
}

enum _DayLevel { branches, titles, employees, calendar }

class _SetDayStatusScreenState extends State<SetDayStatusScreen> {
  bool _loading = true;
  bool _loadingRecords = false;

  // Drill-down state.
  _DayLevel _level = _DayLevel.employees;
  bool _branchStatusMode = false; // applying a status to a whole branch

  // Data.
  List<Branch> _branches = [];
  Branch? _selectedBranch; // branch whose rules/employees we're viewing

  List<Employee> _branchEmployees = []; // employees within _selectedBranch
  List<String> _titles = [];
  String? _selectedTitle;
  List<Employee> _filtered = [];
  Employee? _selected;

  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  List<AttendanceRecord> _records = [];
  final _searchController = TextEditingController();

  bool get _isSA =>
      context.read<AuthProvider>().employee?.role == UserRole.superAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      // Branch list is used for the SA drill-down and to resolve branch rules.
      try {
        _branches = await ApiService().getBranches();
      } catch (_) {
        _branches = [];
      }

      if (me?.role == UserRole.superAdmin) {
        _level = _DayLevel.branches;
      } else {
        // Branch Admin / HR: load their branch employees directly.
        _selectedBranch = _branchById(me?.branchId);
        final list = await ApiService().getAllEmployees(branchId: me?.branchId);
        // #6 admin cannot act on himself.
        _branchEmployees = list.where((e) => e.id != me?.id).toList();
        _filtered = _branchEmployees;
        _level = _DayLevel.employees;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Branch? _branchById(String? id) {
    if (id == null) return null;
    for (final b in _branches) {
      if (b.id == id) return b;
    }
    return null;
  }

  // ── Drill-down transitions ──────────────────────────────────────────────

  Future<void> _selectBranch(Branch b) async {
    // In branch-status mode, picking a branch goes straight to its calendar.
    if (_branchStatusMode) {
      setState(() {
        _selectedBranch = b;
        _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
        _records = [];
        _level = _DayLevel.calendar;
      });
      return;
    }
    setState(() {
      _selectedBranch = b;
      _loading = true;
    });
    try {
      final me = context.read<AuthProvider>().employee;
      final list = await ApiService().getAllEmployees(branchId: b.id);
      _branchEmployees = list.where((e) => e.id != me?.id).toList();
      final titles = <String>{};
      for (final e in _branchEmployees) {
        titles.add(_titleKey(e));
      }
      _titles = titles.toList()..sort(_titleSort);
    } catch (_) {
      _branchEmployees = [];
      _titles = [];
    }
    if (mounted) setState(() {
      _loading = false;
      _level = _DayLevel.titles;
    });
  }

  void _selectTitle(String title) {
    _selectedTitle = title;
    _filtered = _branchEmployees.where((e) => _titleKey(e) == title).toList();
    setState(() => _level = _DayLevel.employees);
  }

  void _selectEmployee(Employee e) {
    setState(() {
      _selected = e;
      _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
      _level = _DayLevel.calendar;
    });
    _loadRecords(e.id);
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

  void _goBack() {
    setState(() {
      switch (_level) {
        case _DayLevel.calendar:
          _records = [];
          _selected = null;
          if (_branchStatusMode) {
            if (_isSA) {
              _selectedBranch = null;
              _level = _DayLevel.branches; // pick another branch
            } else {
              _branchStatusMode = false;
              _level = _DayLevel.employees;
            }
          } else {
            _level = _DayLevel.employees;
          }
          break;
        case _DayLevel.employees:
          if (_isSA) {
            _selectedTitle = null;
            _level = _DayLevel.titles;
          }
          break;
        case _DayLevel.titles:
          _selectedBranch = null;
          _level = _DayLevel.branches;
          break;
        case _DayLevel.branches:
          // Only reachable when a Super Admin is in branch-status mode and
          // backs out of the branch picker.
          _branchStatusMode = false;
          _selectedBranch = null;
          break;
      }
    });
  }

  bool get _canGoBack {
    if (_level == _DayLevel.calendar) return true;
    if (_level == _DayLevel.branches) return _branchStatusMode && _isSA;
    if (!_isSA) return false; // employee list is the top level for non-SA
    return true; // titles / employees for Super Admin
  }

  // ── Title helpers (mirrors the Tasks drill-down) ──────────────────────────

  String _titleKey(Employee e) =>
      (e.position?.isNotEmpty == true) ? e.position! : e.role.name;

  int _titleSort(String a, String b) {
    int rank(String t) {
      switch (t) {
        case 'branchAdmin':
          return 0;
        case 'hr':
          return 1;
        case 'employee':
          return 2;
        default:
          return 3;
      }
    }
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.compareTo(b);
  }

  String _titleLabel(String t) {
    switch (t) {
      case 'superAdmin':
        return S.superAdminTitle;
      case 'branchAdmin':
        return S.branchAdminTitle;
      case 'hr':
        return S.hrTitle;
      case 'employee':
        return S.employeeTitle;
      default:
        return t;
    }
  }

  IconData _iconForTitle(String t) {
    switch (t) {
      case 'branchAdmin':
        return Icons.shield_outlined;
      case 'hr':
        return Icons.badge_outlined;
      case 'employee':
        return Icons.person_outline;
      default:
        return Icons.work_outline;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final role = context.read<AuthProvider>().employee?.role;
    final canSetBranch =
        role == UserRole.branchAdmin || role == UserRole.superAdmin;

    String title;
    if (_level == _DayLevel.calendar) {
      final who = _branchStatusMode
          ? (_selectedBranch?.name ?? S.branch)
          : (_selected?.name ?? '');
      title = '$who — ${S.dayStatus}';
    } else if (_branchStatusMode && _level == _DayLevel.branches) {
      title = S.setBranchStatus;
    } else {
      title = S.setDayStatusTitle;
    }

    // Show the "Branch Status" action only at a list root (not inside a flow).
    final showBranchAction = canSetBranch &&
        !_branchStatusMode &&
        (_level == _DayLevel.branches || _level == _DayLevel.employees) &&
        _selected == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _goBack)
            : null,
        actions: [
          if (showBranchAction)
            TextButton.icon(
              onPressed: _enterBranchStatusMode,
              icon: const Icon(Icons.business, size: 18),
              label: Text(S.setBranchStatus,
                  style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  void _enterBranchStatusMode() {
    setState(() {
      _branchStatusMode = true;
      _selected = null;
      _records = [];
      if (_isSA) {
        // Super Admin must first choose which branch the rule applies to.
        _selectedBranch = null;
        _level = _DayLevel.branches;
      } else {
        // Branch Admin / HR apply to their own branch directly.
        _selectedMonth =
            DateTime(DateTime.now().year, DateTime.now().month);
        _level = _DayLevel.calendar;
      }
    });
  }

  Widget _buildBody() {
    switch (_level) {
      case _DayLevel.branches:
        return _buildBranchesList();
      case _DayLevel.titles:
        return _buildTitlesList();
      case _DayLevel.employees:
        return _buildEmployeePicker();
      case _DayLevel.calendar:
        return _buildCalendar();
    }
  }

  // ── Lists ──────────────────────────────────────────────────────────────────

  Widget _buildBranchesList() {
    if (_branches.isEmpty) {
      return _buildEmpty(S.noBranchesFound, Icons.business_outlined);
    }
    return Column(
      children: [
        if (_branchStatusMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: context.colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(S.chooseBranchToApply,
                      style: TextStyle(
                          color: context.colors.textSecondary, fontSize: 13)),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _branches.length,
            itemBuilder: (_, i) {
              final b = _branches[i];
              return _drillCard(
                icon: Icons.business,
                title: b.name,
                subtitle: b.address.isNotEmpty ? b.address : S.branch,
                onTap: () => _selectBranch(b),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTitlesList() {
    if (_titles.isEmpty) {
      return _buildEmpty(S.noTitlesFound, Icons.badge_outlined);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _titles.length,
      itemBuilder: (_, i) {
        final t = _titles[i];
        final count = _branchEmployees.where((e) => _titleKey(e) == t).length;
        return _drillCard(
          icon: _iconForTitle(t),
          title: _titleLabel(t),
          subtitle: S.employeeCountLabel(count),
          onTap: () => _selectTitle(t),
        );
      },
    );
  }

  Widget _buildEmployeePicker() {
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
              ? _buildEmpty(S.noEmployeesInBranch, Icons.people_outline)
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
                          backgroundImage: (e.profileImageUrl != null &&
                                  e.profileImageUrl!.isNotEmpty)
                              ? NetworkImage(e.profileImageUrl!)
                              : null,
                          child: (e.profileImageUrl == null ||
                                  e.profileImageUrl!.isEmpty)
                              ? Text(
                                  e.name.isNotEmpty
                                      ? e.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: AppTheme.primaryBlue))
                              : null,
                        ),
                        title: Text(e.name,
                            style:
                                TextStyle(color: context.colors.textPrimary)),
                        subtitle: Text(e.position ?? e.department,
                            style: TextStyle(
                                color: context.colors.textSecondary)),
                        trailing: Icon(Icons.chevron_right,
                            color: context.colors.textMuted),
                        onTap: () => _selectEmployee(e),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _applySearch(String q) {
    final needle = q.trim().toLowerCase();
    setState(() {
      _filtered = needle.isEmpty
          ? _branchEmployees
              .where((e) =>
                  _selectedTitle == null || _titleKey(e) == _selectedTitle)
              .toList()
          : _branchEmployees
              .where((e) =>
                  (_selectedTitle == null ||
                      _titleKey(e) == _selectedTitle) &&
                  (e.name.toLowerCase().contains(needle) ||
                      e.email.toLowerCase().contains(needle) ||
                      (e.position ?? '').toLowerCase().contains(needle)))
              .toList();
    });
  }

  // ── Calendar ────────────────────────────────────────────────────────────────

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
        _buildBranchRulesBar(),
        if (_branchStatusMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              S.tapDayToSetBranchStatus,
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 13),
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

  /// Shows the branch's general rules: working days, weekly holidays and hours.
  Widget _buildBranchRulesBar() {
    final b = _selectedBranch;
    if (b == null) return const SizedBox.shrink();
    const order = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const dayToWeekday = {
      'Monday': 1,
      'Tuesday': 2,
      'Wednesday': 3,
      'Thursday': 4,
      'Friday': 5,
      'Saturday': 6,
      'Sunday': 7,
    };
    String shortOf(String day) => S.weekDaysSun[dayToWeekday[day]! % 7];
    final working = order.where((d) => b.workingDays.contains(d)).toList();
    final holidays = order.where((d) => !b.workingDays.contains(d)).toList();

    Widget chips(String label, List<String> days, Color color) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 12)),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: days
                    .map((d) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(shortOf(d),
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ),
          ],
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule, size: 16, color: AppTheme.primaryBlue),
              const SizedBox(width: 6),
              Text(S.branchRules,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const Spacer(),
              Text('${b.workingHoursStart}–${b.workingHoursEnd}',
                  style: TextStyle(
                      color: context.colors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          chips(S.workingDays, working, AppTheme.accentGreen),
          const SizedBox(height: 6),
          chips(S.weeklyHolidays, holidays, AppTheme.warningAmber),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final year = _selectedMonth.year;
    final month = _selectedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // 0=Sun
    final today = DateTime.now();

    final statusByDate = <String, String>{};
    for (final r in _records) {
      if (r.type == 'day_status' && r.date != null) {
        statusByDate[r.date!] = r.dayStatus ?? '';
      }
    }

    // Branch working-day rule: weekdays not in workingDays are weekly holidays.
    final workingDays =
        _selectedBranch?.workingDays ?? Branch.defaultWorkingDays;
    const weekdayName = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };

    final totalCells = firstWeekday + daysInMonth;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
                8, 0, 8, 8 + MediaQuery.of(context).viewPadding.bottom),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.9,
            ),
            itemCount: totalCells,
            itemBuilder: (_, index) {
              if (index < firstWeekday) return const SizedBox();
              final day = index - firstWeekday + 1;
              final dateStr =
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final st = statusByDate[dateStr];
              final weekday = DateTime(year, month, day).weekday;
              final isWeeklyHoliday =
                  !workingDays.contains(weekdayName[weekday]);
              final isToday = year == today.year &&
                  month == today.month &&
                  day == today.day;

              // Explicit status wins over the branch weekly-holiday rule.
              Color? bg;
              String? labelText;
              switch (st) {
                case 'vacation':
                  bg = AppTheme.primaryBlue.withValues(alpha: 0.25);
                  labelText = S.vacation;
                  break;
                case 'holiday':
                  bg = AppTheme.warningAmber.withValues(alpha: 0.25);
                  labelText = S.holiday;
                  break;
                case 'absent':
                  bg = AppTheme.checkOutRed.withValues(alpha: 0.25);
                  labelText = S.absent;
                  break;
                case 'attend':
                  bg = AppTheme.accentGreen.withValues(alpha: 0.25);
                  labelText = S.signIn;
                  break;
                default:
                  if (isWeeklyHoliday) {
                    bg = AppTheme.warningAmber.withValues(alpha: 0.10);
                    labelText = S.holiday;
                  }
              }

              return GestureDetector(
                onTap: () => _branchStatusMode
                    ? _pickBranchStatus(dateStr)
                    : _pickStatus(dateStr),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: bg ?? context.colors.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isToday
                            ? AppTheme.primaryBlue
                            : context.colors.surfaceBorder,
                        width: isToday ? 1.5 : 0.5),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$day',
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontWeight: isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 13)),
                        if (labelText != null)
                          Text(labelText,
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 9)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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

  Future<void> _pickBranchStatus(String date) async {
    final branchId = _selectedBranch?.id;
    if (branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectBranchFirst)),
      );
      return;
    }
    final statuses = ['attend', 'vacation', 'absent', 'holiday'];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${S.setBranchStatus}: $date'),
        children: statuses
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text(_short(s)),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    try {
      final me = context.read<AuthProvider>().employee;
      final count = await ApiService().setBranchDayStatus(
        branchId: branchId,
        date: date,
        status: selected,
        appliedBy: me?.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.branchDayStatusApplied(count))),
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

  // ── Shared widgets ───────────────────────────────────────────────────────

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
