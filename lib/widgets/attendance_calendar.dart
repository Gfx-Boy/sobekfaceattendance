import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/attendance_record.dart';
import '../l10n/app_localizations.dart';

/// Colour used to tint a day cell / legend dot for a given day status.
Color dayStatusColor(BuildContext context, String status) {
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

/// Short label for a day status.
String dayStatusLabel(String status) {
  switch (status) {
    case 'vacation':
      return S.vacation;
    case 'absent':
      return S.absent;
    case 'holiday':
      return S.holiday;
    case 'attend':
      return S.signIn;
    case 'permission':
      return S.permission;
    case 'business_mission':
      return S.businessMission;
    case 'sick':
      return S.sickLeave;
    default:
      return status;
  }
}

/// The rich monthly attendance calendar used on an employee's own attendance
/// screen. It is shared so managers can view an employee's attendance in the
/// same nice layout — but read-only, by leaving [canEdit] false and passing no
/// [onEditDay]. Editing employees' attendance stays in the dedicated
/// set-day-status tool.
class AttendanceCalendar extends StatelessWidget {
  final DateTime month;
  final List<AttendanceRecord> records;
  final bool loading;

  /// When true (and [onEditDay] is provided) a long-press on a day triggers
  /// editing. Managers viewing an employee pass false → fully read-only.
  final bool canEdit;
  final void Function(int day)? onEditDay;

  /// Optional tap handler (e.g. open a read-only day-detail sheet).
  final void Function(DateTime date)? onTapDay;

  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  /// Whether to include the vacation/absent/holiday entries in the legend.
  final bool showStatusLegend;

  /// Weekday numbers (DateTime.monday=1 … DateTime.sunday=7) rendered as
  /// weekend. Defaults to Sat/Sun; pass the branch's real weekend so this
  /// calendar and the HR day-status grid grey out the same days.
  final List<int> weekendDays;

  const AttendanceCalendar({
    super.key,
    required this.month,
    required this.records,
    this.loading = false,
    this.canEdit = false,
    this.onEditDay,
    this.onTapDay,
    this.onPrevMonth,
    this.onNextMonth,
    this.showStatusLegend = false,
    this.weekendDays = const [DateTime.saturday, DateTime.sunday],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildMonthSelector(context),
        const SizedBox(height: 8),
        _buildDayHeaders(context),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : _buildCalendarGrid(context),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildLegend(context),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSelector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: onPrevMonth,
            child: Icon(Icons.chevron_left, color: context.colors.textPrimary),
          ),
          Text(
            '${S.months[month.month - 1]} ${month.year}',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          GestureDetector(
            onTap: onNextMonth,
            child: Icon(Icons.chevron_right, color: context.colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: S.weekDaysSun
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

  Widget _buildCalendarGrid(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // Mon = 1
    final today = DateTime.now();

    final Map<int, List<AttendanceRecord>> dayRecords = {};
    for (final r in records) {
      // A day_status record's `timestamp` is when it was SET (e.g. the moment a
      // vacation request was approved) — the day it applies to lives in `date`.
      // Bucketing those by timestamp put the status on the approval day instead
      // of the vacation days (#16).
      DateTime effective = r.timestamp;
      if (r.type == 'day_status' && (r.date ?? '').isNotEmpty) {
        effective = DateTime.tryParse(r.date!) ?? r.timestamp;
      }
      if (effective.year == month.year && effective.month == month.month) {
        dayRecords.putIfAbsent(effective.day, () => []).add(r);
      }
    }

    final cells = <Widget>[];
    // Sunday-first grid (matches the HR day-status screen): Sunday lands in
    // column 0, so a month starting on weekday w needs w % 7 leading blanks.
    for (var i = 0; i < firstWeekday % 7; i++) {
      cells.add(const SizedBox());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isWeekend = weekendDays.contains(date.weekday);

      final dayRecs = dayRecords[day];
      String? checkIn;
      String? checkOut;
      int breakCount = 0;
      String? dayStatus;
      if (dayRecs != null && dayRecs.isNotEmpty) {
        dayRecs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final statusRecords =
            dayRecs.where((r) => r.type == 'day_status').toList();
        if (statusRecords.isNotEmpty) {
          // Sorted above, so `last` really is the most recently set status.
          dayStatus = statusRecords.last.dayStatus;
        }
        final signInRecord = dayRecs.where((r) => r.type == 'sign_in').toList();
        final signOutRecord =
            dayRecs.where((r) => r.type == 'sign_out').toList();
        breakCount = dayRecs.where((r) => r.type == 'break_start').length;
        if (signInRecord.isNotEmpty) {
          final t = signInRecord.first.timestamp;
          checkIn =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        } else if (dayRecs.any((r) => r.type != 'day_status')) {
          final t = dayRecs.firstWhere((r) => r.type != 'day_status').timestamp;
          checkIn =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        }
        if (signOutRecord.isNotEmpty) {
          final t = signOutRecord.last.timestamp;
          checkOut =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        }
      }

      cells.add(_buildDayCell(
        context,
        day: day,
        date: date,
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

  Widget _buildDayCell(
    BuildContext context, {
    required int day,
    required DateTime date,
    required bool isToday,
    required bool isWeekend,
    String? checkIn,
    String? checkOut,
    int breakCount = 0,
    String? dayStatus,
  }) {
    // An admin-set "attend" day counts as attended even without a punch —
    // HR marking someone present via set-status must show on the sheet (#8).
    final bool attended = checkIn != null || dayStatus == 'attend';
    final bool completedDay = checkIn != null && checkOut != null;

    Color topColor;
    Color bottomColor;

    if (dayStatus != null && dayStatus != 'attend') {
      final isHoliday = dayStatus == 'holiday';
      final statusColor = isHoliday
          ? context.colors.textMuted.withValues(alpha: 0.15)
          : dayStatusColor(context, dayStatus).withValues(alpha: 0.25);
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
                        color: isWeekend
                            ? context.colors.textMuted
                            : context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    // An explicit day status (vacation/absent/holiday) is the
                    // whole story for the day — show only its label, never a
                    // check-in/out time. Otherwise the cell contradicts itself
                    // (e.g. "Vacation" with an attend time next to it).
                    if (dayStatus != null && dayStatus != 'attend') ...[
                      const SizedBox(height: 1),
                      Text(
                        dayStatusLabel(dayStatus),
                        style: TextStyle(
                          color: dayStatusColor(context, dayStatus),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else if (dayStatus == 'attend' && checkIn == null) ...[
                      // Admin-set presence with no real punch time.
                      const SizedBox(height: 1),
                      Text(
                        S.signIn,
                        style: const TextStyle(
                          color: AppTheme.accentGreen,
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
            Expanded(
              child: Container(
                color: bottomColor,
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hide punch times entirely on a day with an explicit
                    // status override, so a vacation/absent/holiday day never
                    // also shows an attend/leave time (data-conflict fix).
                    if ((dayStatus == null || dayStatus == 'attend') &&
                        checkOut != null)
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

    final canLongPress = canEdit && onEditDay != null;
    if (canLongPress || onTapDay != null) {
      return GestureDetector(
        onTap: onTapDay == null ? null : () => onTapDay!(date),
        onLongPress: canLongPress ? () => onEditDay!(day) : null,
        child: cell,
      );
    }
    return cell;
  }

  Widget _buildLegend(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _legendDot(context, AppTheme.accentGreen, S.signIn),
          _legendDot(context, AppTheme.checkOutRed, S.signOut),
          _legendDot(context, context.colors.textMuted, S.weekend),
          if (showStatusLegend) ...[
            _legendDot(context, Colors.orange, S.vacation),
            _legendDot(context, Colors.red, S.absent),
            _legendDot(context, Colors.teal, S.holiday),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
