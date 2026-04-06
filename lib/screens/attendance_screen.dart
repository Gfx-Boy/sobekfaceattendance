import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';
import '../models/attendance_record.dart';
import '../l10n/app_localizations.dart';
import '../models/employee.dart';
import '../services/api_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = false;
  List<AttendanceRecord> _records = [];

  bool get _isAdmin {
    final role = context.read<AuthProvider>().employee?.role;
    return role == UserRole.superAdmin ||
        role == UserRole.branchAdmin ||
        role == UserRole.hr;
  }

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
    return Scaffold(
      appBar: AppBar(title: Text(S.attendance)),
      body: Column(
        children: [
          // Month selector
          _buildMonthSelector(),
          const SizedBox(height: 8),
          // Day headers
          _buildDayHeaders(),
          // Calendar grid
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildCalendarGrid(),
          ),
          // Legend
          _buildLegend(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _changeMonth(-1),
            child: Icon(Icons.chevron_left, color: context.colors.textPrimary),
          ),
          Text(
            '${S.months[_selectedMonth.month - 1]} ${_selectedMonth.year}',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          GestureDetector(
            onTap: () => _changeMonth(1),
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
        children: S.weekDays
            .map((d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday;
    // Monday = 1

    final today = DateTime.now();

    // Build a map: day-of-month → list of records for that day
    final Map<int, List<AttendanceRecord>> dayRecords = {};
    for (final r in _records) {
      if (r.timestamp.year == _selectedMonth.year && r.timestamp.month == _selectedMonth.month) {
        dayRecords.putIfAbsent(r.timestamp.day, () => []).add(r);
      }
    }

    final cells = <Widget>[];

    // Leading empty cells
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }

    // Day cells
    for (var day = 1; day <= daysInMonth; day++) {
      final date =
          DateTime(_selectedMonth.year, _selectedMonth.month, day);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isWeekend = date.weekday == 6 || date.weekday == 7;

      // Get real attendance records for this day
      final records = dayRecords[day];
      String? checkIn;
      String? checkOut;
      int breakCount = 0;
      String? dayStatus;
      if (records != null && records.isNotEmpty) {
        // Check for day_status records first
        final statusRecords = records.where((r) => r.type == 'day_status').toList();
        if (statusRecords.isNotEmpty) {
          dayStatus = statusRecords.last.dayStatus;
        }

        // Sort by timestamp
        records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        // Find sign_in and sign_out records
        final signInRecord = records.where((r) => r.type == 'sign_in').toList();
        final signOutRecord = records.where((r) => r.type == 'sign_out').toList();
        breakCount = records.where((r) => r.type == 'break_start').length;
        if (signInRecord.isNotEmpty) {
          final t = signInRecord.first.timestamp;
          checkIn = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        } else if (records.any((r) => r.type != 'day_status')) {
          // Fallback for legacy records without type
          final t = records.firstWhere((r) => r.type != 'day_status').timestamp;
          checkIn = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        }
        if (signOutRecord.isNotEmpty) {
          final t = signOutRecord.last.timestamp;
          checkOut = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        }
      }

      cells.add(_buildDayCell(
        day: day,
        isToday: isToday,
        isWeekend: isWeekend,
        checkIn: checkIn,
        checkOut: checkOut,
        breakCount: breakCount,
        dayStatus: dayStatus,
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      childAspectRatio: 0.7,
      children: cells,
    );
  }

  Widget _buildDayCell({
    required int day,
    required bool isToday,
    required bool isWeekend,
    String? checkIn,
    String? checkOut,
    int breakCount = 0,
    String? dayStatus,
  }) {
    // Determine day status for coloring
    final bool attended = checkIn != null;
    final bool completedDay = checkIn != null && checkOut != null;

    Color topColor;
    Color bottomColor;

    if (dayStatus != null && dayStatus != 'attend') {
      final isHoliday = dayStatus == 'holiday';
      final statusColor = isHoliday
          ? context.colors.textMuted.withValues(alpha: 0.15)
          : _dayStatusColor(dayStatus).withValues(alpha: 0.25);
      topColor = statusColor;
      bottomColor = statusColor;
    } else if (isWeekend) {
      topColor = context.colors.textMuted.withValues(alpha: 0.15);
      bottomColor = context.colors.textMuted.withValues(alpha: 0.15);
    } else if (completedDay) {
      topColor = AppTheme.accentGreen.withValues(alpha: 0.2);
      bottomColor = AppTheme.checkOutRed.withValues(alpha: 0.2);
    } else if (attended) {
      topColor = AppTheme.accentGreen.withValues(alpha: 0.2);
      bottomColor = AppTheme.primaryBlue.withValues(alpha: 0.1);
    } else {
      topColor = context.colors.cardBg;
      bottomColor = context.colors.cardBg;
    }

    final cell = Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: AppTheme.primaryBlue, width: 1.5)
            : Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          children: [
            // Top half — Sign In
            Expanded(
              child: Container(
                color: topColor,
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        color: isWeekend ? context.colors.textMuted : context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    if (dayStatus != null && dayStatus != 'attend') ...[
                      SizedBox(height: 1),
                      if (dayStatus == 'holiday')
                        Icon(Icons.celebration, size: 10, color: context.colors.textMuted)
                      else
                        Text(
                          _dayStatusLabel(dayStatus),
                          style: TextStyle(
                            color: _dayStatusColor(dayStatus),
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ] else if (checkIn != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        checkIn,
                        style: const TextStyle(
                          color: AppTheme.accentGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Bottom half — Sign Out / Break
            Expanded(
              child: Container(
                color: bottomColor,
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (checkOut != null)
                      Text(
                        checkOut,
                        style: const TextStyle(
                          color: AppTheme.checkOutRed,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (_isAdmin) {
      return GestureDetector(
        onLongPress: () => _showDayStatusDialog(day),
        child: cell,
      );
    }
    return cell;
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _legendDot(AppTheme.accentGreen, S.signIn),
          _legendDot(AppTheme.checkOutRed, S.signOut),
          _legendDot(context.colors.textMuted, S.weekend),
          if (_isAdmin) ...[
            _legendDot(Colors.orange, S.vacation),
            _legendDot(Colors.red, S.absent),
            _legendDot(Colors.teal, S.holiday),
          ],
        ],
      ),
    );
  }

  Color _dayStatusColor(String status) {
    switch (status) {
      case 'vacation':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'sick':
        return Colors.purple;
      case 'business_mission':
        return Colors.blue;
      case 'holiday':
        return Colors.teal;
      case 'attend':
        return AppTheme.accentGreen;
      default:
        return context.colors.textMuted;
    }
  }

  String _dayStatusLabel(String status) {
    switch (status) {
      case 'vacation':
        return S.vacation;
      case 'absent':
        return S.absent;
      case 'holiday':
        return S.holiday;
      case 'attend':
        return S.signIn;
      default:
        return status;
    }
  }

  Future<void> _showDayStatusDialog(int day) async {
    final auth = context.read<AuthProvider>();
    final employeeId = auth.employee!.id;
    final date =
        '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    final statuses = ['attend', 'vacation', 'absent', 'holiday'];

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${S.dayStatus}: $date'),
        children: statuses
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _dayStatusColor(s),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_dayStatusLabel(s)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (selected == null || !mounted) return;

    try {
      await ApiService().setDayStatus(
        employeeId: employeeId,
        date: date,
        status: selected,
      );
      await _loadRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.dayStatus}: ${_dayStatusLabel(selected)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.error}: $e')),
        );
      }
    }
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
