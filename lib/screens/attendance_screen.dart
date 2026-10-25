import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';
import '../models/attendance_record.dart';
import '../models/branch.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../widgets/attendance_calendar.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = false;
  List<AttendanceRecord> _records = [];

  /// Weekend weekdays derived from the employee's branch working days, so
  /// this sheet greys out the same days as the HR day-status grid.
  List<int> _weekendDays = const [DateTime.saturday, DateTime.sunday];

  static const Map<int, String> _weekdayName = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRecords());
  }

  Future<void> _loadRecords() async {
    final auth = context.read<AuthProvider>();
    if (auth.employee == null) return;

    setState(() => _loading = true);
    try {
      final provider = context.read<AttendanceProvider>();
      await provider.loadAttendanceHistory(auth.employee!.id);
      if (mounted) setState(() => _records = provider.attendanceHistory);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.failedToLoadData)),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
    _loadBranchWeekend();
  }

  Future<void> _loadBranchWeekend() async {
    final me = context.read<AuthProvider>().employee;
    if (me?.branchId == null) return;
    try {
      final branches = await ApiService().getBranches();
      final branch = branches.where((b) => b.id == me!.branchId).toList();
      final working =
          branch.isNotEmpty ? branch.first.workingDays : Branch.defaultWorkingDays;
      final weekend = [
        for (var w = 1; w <= 7; w++)
          if (!working.contains(_weekdayName[w])) w
      ];
      if (mounted && weekend.isNotEmpty) {
        setState(() => _weekendDays = weekend);
      }
    } catch (_) {
      // Keep the Sat/Sun default if the branch can't be loaded.
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    // This screen only ever shows the logged-in user's OWN attendance, so it is
    // strictly read-only — nobody (not even HR/admins) may set their own day
    // status here. Editing employees' day status lives in the dedicated
    // "Set Employee Day Status" tool, which excludes the acting user.
    return Scaffold(
      appBar: AppBar(
        title: Text(S.attendance),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadRecords,
          ),
        ],
      ),
      body: AttendanceCalendar(
        month: _selectedMonth,
        records: _records,
        loading: _loading,
        canEdit: false,
        showStatusLegend: true,
        weekendDays: _weekendDays,
        onPrevMonth: () => _changeMonth(-1),
        onNextMonth: () => _changeMonth(1),
      ),
    );
  }
}
