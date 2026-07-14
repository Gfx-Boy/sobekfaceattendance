import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';
import '../models/attendance_record.dart';
import '../l10n/app_localizations.dart';
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
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
      appBar: AppBar(title: Text(S.attendance)),
      body: AttendanceCalendar(
        month: _selectedMonth,
        records: _records,
        loading: _loading,
        canEdit: false,
        showStatusLegend: true,
        onPrevMonth: () => _changeMonth(-1),
        onNextMonth: () => _changeMonth(1),
      ),
    );
  }
}
