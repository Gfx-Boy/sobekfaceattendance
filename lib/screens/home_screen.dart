import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';
import '../models/employee.dart';
import '../models/system_settings.dart';
import '../services/api_service.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TodaySummary? _todaySummary;
  bool _loadingStatus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTodayStatus());
  }

  Future<void> _loadTodayStatus() async {
    final auth = context.read<AuthProvider>();
    final employee = auth.employee;
    if (employee == null) return;
    setState(() => _loadingStatus = true);
    try {
      final summary = await ApiService().getTodayStatus(employee.id);
      if (mounted) setState(() => _todaySummary = summary);
    } catch (_) {}
    if (mounted) setState(() => _loadingStatus = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final employee = auth.employee;
    final role = employee?.role ?? UserRole.employee;
    final isSuperAdmin = role == UserRole.superAdmin;
    final isBranchAdmin = role == UserRole.branchAdmin;
    final isAdmin = isSuperAdmin || isBranchAdmin;
    final isHR = role == UserRole.hr;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            AppTheme.primaryBlue.withValues(alpha: 0.2),
                        child: Text(
                          employee?.name.isNotEmpty == true
                              ? employee!.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppTheme.accentGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.colors.scaffoldBg, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.welcomeBack,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          employee?.name ?? 'Employee',
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/notifications'),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.colors.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: context.colors.surfaceBorder, width: 0.5),
                      ),
                      child: Icon(Icons.notifications_outlined,
                          color: context.colors.textSecondary, size: 22),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              // Quick actions grid
              Text(
                S.quickActions,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (isAdmin) ...[
                // ── Admin / SuperAdmin quick actions ──
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _QuickAction(
                      icon: Icons.people_outline,
                      label: S.manageEmployees,
                      color: AppTheme.primaryBlue,
                      onTap: () =>
                          Navigator.pushNamed(context, '/employees'),
                    ),
                    _QuickAction(
                      icon: Icons.bar_chart,
                      label: S.attendanceReports,
                      color: AppTheme.accentGreen,
                      onTap: () =>
                          Navigator.pushNamed(context, '/reports'),
                    ),
                    _QuickAction(
                      icon: Icons.playlist_add_check,
                      label: S.manageRequests,
                      color: AppTheme.warningAmber,
                      onTap: () =>
                          Navigator.pushNamed(context, '/manage-requests'),
                    ),
                    if (role == UserRole.superAdmin)
                      _QuickAction(
                        icon: Icons.business,
                        label: S.manageBranches,
                        color: AppTheme.checkOutPink,
                        onTap: () =>
                            Navigator.pushNamed(context, '/branches'),
                      )
                    else
                      _QuickAction(
                        icon: Icons.person_add_outlined,
                        label: S.addEmployee,
                        color: AppTheme.checkOutPink,
                        onTap: () =>
                            Navigator.pushNamed(context, '/add-employee'),
                      ),
                    _QuickAction(
                      icon: Icons.task_alt,
                      label: S.tasks,
                      color: const Color(0xFF6C63FF),
                      onTap: () => Navigator.pushNamed(context, '/tasks'),
                    ),
                    _QuickAction(
                      icon: Icons.star_outline,
                      label: S.appraisals,
                      color: const Color(0xFFFF6B6B),
                      onTap: () => Navigator.pushNamed(context, '/appraisals'),
                    ),
                    _QuickAction(
                      icon: Icons.receipt_long,
                      label: S.payslips,
                      color: const Color(0xFF4ECDC4),
                      onTap: () => Navigator.pushNamed(context, '/manage-payslips'),
                    ),
                    if (role == UserRole.superAdmin) ...[
                      _QuickAction(
                        icon: Icons.settings,
                        label: S.systemSettings,
                        color: const Color(0xFF7E8C8D),
                        onTap: () => Navigator.pushNamed(context, '/settings'),
                      ),
                    ],
                  ],
                ),                const SizedBox(height: 24),
                // Admin info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.admin_panel_settings,
                          color: AppTheme.primaryBlue, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        role == UserRole.superAdmin
                            ? S.superAdminDesc
                            : S.branchAdminDesc,
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isHR) ...[
                // ── HR quick actions: Attendance + Management ──
                // Attendance row
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _QuickAction(
                      icon: Icons.login,
                      label: S.signIn,
                      color: AppTheme.accentGreen,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('sign_in');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.logout,
                      label: S.signOut,
                      color: AppTheme.checkOutRed,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('sign_out');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.coffee,
                      label: S.takeBreak,
                      color: AppTheme.warningAmber,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('break_start');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.play_arrow,
                      label: S.endBreak,
                      color: AppTheme.primaryBlue,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('break_end');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Management row
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _QuickAction(
                      icon: Icons.people_outline,
                      label: S.employeeDataLabel,
                      color: AppTheme.primaryBlue,
                      onTap: () =>
                          Navigator.pushNamed(context, '/employees'),
                    ),
                    _QuickAction(
                      icon: Icons.bar_chart,
                      label: S.attendanceMonitorLabel,
                      color: AppTheme.accentGreen,
                      onTap: () =>
                          Navigator.pushNamed(context, '/reports'),
                    ),
                    _QuickAction(
                      icon: Icons.playlist_add_check,
                      label: S.manageRequests,
                      color: const Color(0xFF6C63FF),
                      onTap: () =>
                          Navigator.pushNamed(context, '/manage-requests'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _QuickAction(
                      icon: Icons.task_alt,
                      label: S.tasks,
                      color: const Color(0xFF6C63FF),
                      onTap: () => Navigator.pushNamed(context, '/tasks'),
                    ),
                    _QuickAction(
                      icon: Icons.star_outline,
                      label: S.appraisals,
                      color: const Color(0xFFFF6B6B),
                      onTap: () => Navigator.pushNamed(context, '/appraisals'),
                    ),
                    _QuickAction(
                      icon: Icons.receipt_long,
                      label: S.payslips,
                      color: const Color(0xFF4ECDC4),
                      onTap: () => Navigator.pushNamed(context, '/manage-payslips'),
                    ),
                    _QuickAction(
                      icon: Icons.history,
                      label: S.history,
                      color: const Color(0xFF7E8C8D),
                      onTap: () => Navigator.pushNamed(context, '/history'),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                // Today's Status for HR
                Text(
                  S.todayStatus,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTodayStatusCard(),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.warningAmber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.warningAmber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.badge_outlined,
                          color: AppTheme.warningAmber, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        S.hrDesc,
                        style: TextStyle(
                          color: AppTheme.warningAmber,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ── Employee quick actions ──
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _QuickAction(
                      icon: Icons.login,
                      label: S.signIn,
                      color: AppTheme.accentGreen,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('sign_in');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.logout,
                      label: S.signOut,
                      color: AppTheme.checkOutRed,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('sign_out');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.coffee,
                      label: S.takeBreak,
                      color: AppTheme.warningAmber,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('break_start');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.play_arrow,
                      label: S.endBreak,
                      color: AppTheme.primaryBlue,
                      onTap: () {
                        context.read<AttendanceProvider>().setAttendanceType('break_end');
                        Navigator.pushNamed(context, '/camera');
                      },
                    ),
                    _QuickAction(
                      icon: Icons.description_outlined,
                      label: S.makeRequest,
                      color: AppTheme.warningAmber,
                      onTap: () =>
                          Navigator.pushNamed(context, '/create-request'),
                    ),
                    _QuickAction(
                      icon: Icons.history,
                      label: S.history,
                      color: AppTheme.primaryBlue,
                      onTap: () =>
                          Navigator.pushNamed(context, '/history'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    _QuickAction(
                      icon: Icons.task_alt,
                      label: S.myTasks,
                      color: const Color(0xFF6C63FF),
                      onTap: () => Navigator.pushNamed(context, '/tasks'),
                    ),
                    _QuickAction(
                      icon: Icons.receipt_long,
                      label: S.myPayslips,
                      color: const Color(0xFF4ECDC4),
                      onTap: () => Navigator.pushNamed(context, '/payslips'),
                    ),
                    _QuickAction(
                      icon: Icons.notifications_outlined,
                      label: S.notifications,
                      color: AppTheme.checkOutPink,
                      onTap: () =>
                          Navigator.pushNamed(context, '/notifications'),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                Text(
                  S.todayStatus,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTodayStatusCard(),
                const SizedBox(height: 24),
                // Online status
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accentGreen.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, color: AppTheme.accentGreen, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        S.onlineReady,
                        style: const TextStyle(
                          color: AppTheme.accentGreen,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildTodayStatusCard() {
    final s = _todaySummary;
    if (_loadingStatus) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: context.colors.cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.colors.surfaceBorder, width: 0.5)),
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final statusIcon = s == null || !s.signedIn
        ? Icons.fingerprint
        : s.onBreak
            ? Icons.coffee
            : s.signedOut
                ? Icons.check_circle
                : Icons.access_time;
    final statusColor = s == null || !s.signedIn
        ? context.colors.textMuted
        : s.onBreak
            ? AppTheme.warningAmber
            : s.signedOut
                ? AppTheme.accentGreen
                : AppTheme.primaryBlue;
    final statusText = s == null || !s.signedIn
        ? S.notSignedInYet
        : s.onBreak
            ? S.onBreak
            : s.signedOut
                ? S.signedOutStatus
                : S.signedInWorking;
    final subText = s == null || !s.signedIn
        ? S.tapSignIn
        : s.onBreak
            ? '${S.breakLabel} ${s.breakCount} · ${s.totalBreakMinutes} min'
            : s.signedOut
                ? '${S.breakLabel}: ${s.breakCount} (${s.totalBreakMinutes} min)'
                : s.breakCount > 0
                    ? '${S.breakLabel}: ${s.breakCount} (${s.totalBreakMinutes} min)'
                    : S.noBreaksTaken;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(statusIcon, color: statusColor, size: 26),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText, style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
                SizedBox(height: 2),
                Text(subText, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: context.colors.textMuted, size: 20),
            onPressed: _loadTodayStatus,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
