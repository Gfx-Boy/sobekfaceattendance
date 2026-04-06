import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/dashboard_stats.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  DashboardStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      setState(() => _loading = true);
      final stats = await ApiService().getDashboardStats();
      if (mounted) setState(() { _stats = stats; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.adminDashboard),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${employee?.name ?? 'Admin'}',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee?.roleDisplayName ?? 'Super Admin',
                      style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.checkOutRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!, style: const TextStyle(color: AppTheme.checkOutRed, fontSize: 13)),
                      ),
                    // Stats Grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _statCard(S.employees, '${_stats?.employeeCount ?? 0}', Icons.people, AppTheme.primaryBlue),
                        _statCard('Branches', '${_stats?.branchCount ?? 0}', Icons.business, AppTheme.accentGreen),
                        _statCard('Pending Requests', '${_stats?.pendingRequests ?? 0}', Icons.pending_actions, AppTheme.warningAmber),
                        _statCard('Total Attendance', '${_stats?.totalAttendance ?? 0}', Icons.fingerprint, AppTheme.checkOutPink),
                        _statCard('Total Requests', '${_stats?.totalRequests ?? 0}', Icons.description, AppTheme.primaryBlue),
                        _statCard('Active Tasks', '${_stats?.totalTasks ?? 0}', Icons.task_alt, AppTheme.accentGreen),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Quick Actions',
                      style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _actionTile(Icons.people_outline, 'Manage Employees', () => Navigator.pushNamed(context, '/employees')),
                    _actionTile(Icons.business, 'Manage Branches', () => Navigator.pushNamed(context, '/branches')),
                    _actionTile(Icons.bar_chart, 'Attendance Reports', () => Navigator.pushNamed(context, '/reports')),
                    _actionTile(Icons.playlist_add_check, 'Manage Requests', () => Navigator.pushNamed(context, '/manage-requests')),
                    _actionTile(Icons.person_add, 'Add Employee', () => Navigator.pushNamed(context, '/add-employee')),
                    _actionTile(Icons.assessment, 'Appraisals', () => Navigator.pushNamed(context, '/appraisals')),
                    _actionTile(Icons.receipt_long, 'Payslips', () => Navigator.pushNamed(context, '/manage-payslips')),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Spacer(),
            ],
          ),
          SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primaryBlue, size: 22),
                SizedBox(width: 14),
                Expanded(child: Text(label, style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500))),
                Icon(Icons.chevron_right, color: context.colors.textMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
