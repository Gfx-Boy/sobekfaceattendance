import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/attendance_provider.dart';
import '../providers/auth_provider.dart';
import '../models/attendance_record.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.employee != null) {
        context
            .read<AttendanceProvider>()
            .loadAttendanceHistory(auth.employee!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.attendanceHistory),
      ),
      body: Consumer<AttendanceProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.attendanceHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: context.colors.textMuted),
                  SizedBox(height: 16),
                  Text(
                    S.noAttendanceRecords,
                    style: TextStyle(
                      fontSize: 18,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    S.historyAppearHere,
                    style: TextStyle(color: context.colors.textMuted),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              final auth = context.read<AuthProvider>();
              if (auth.employee != null) {
                await provider.loadAttendanceHistory(auth.employee!.id);
              }
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.attendanceHistory.length,
              itemBuilder: (context, index) {
                final record = provider.attendanceHistory[index];
                return _AttendanceCard(record: record);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final AttendanceRecord record;

  const _AttendanceCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final loc = S.locale.languageCode;
    final dateFormat = DateFormat('EEE, MMM d, yyyy', loc);
    final timeFormat = DateFormat('hh:mm a', loc);
    final isSignOut = record.type == 'sign_out';
    final isBreak = record.type == 'break_start' || record.type == 'break_end';
    final typeLabel = switch (record.type) {
      'sign_out' => S.signOut,
      'break_start' => S.breakStart,
      'break_end' => S.breakEnd,
      _ => S.signIn,
    };
    final typeColor = isBreak ? AppTheme.warningAmber : (isSignOut ? AppTheme.checkOutRed : AppTheme.accentGreen);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: record.status == AttendanceStatus.success
                    ? typeColor.withValues(alpha: 0.1)
                    : AppTheme.checkOutRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isBreak ? Icons.coffee : (isSignOut ? Icons.logout : Icons.login),
                color: record.status == AttendanceStatus.success
                    ? typeColor
                    : AppTheme.checkOutRed,
              ),
            ),
            const SizedBox(width: 14),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dateFormat.format(record.timestamp),
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    timeFormat.format(record.timestamp),
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Confidence badge
            if (record.faceMatchConfidence != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${record.faceMatchConfidence!.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
