import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/appraisal.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../l10n/app_localizations.dart';

class AppraisalsScreen extends StatefulWidget {
  const AppraisalsScreen({super.key});

  @override
  State<AppraisalsScreen> createState() => _AppraisalsScreenState();
}

class _AppraisalsScreenState extends State<AppraisalsScreen> {
  List<Appraisal> _appraisals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAppraisals();
  }

  Future<void> _loadAppraisals() async {
    final employee = context.read<AuthProvider>().employee;
    if (employee == null) return;
    try {
      setState(() => _loading = true);
      if (employee.role == UserRole.superAdmin) {
        _appraisals = await ApiService().getAllAppraisals();
      } else if (employee.role == UserRole.branchAdmin || employee.role == UserRole.hr) {
        // Load appraisals for all employees in the branch
        final branchEmployees = await ApiService().getAllEmployees(branchId: employee.branchId);
        final List<Appraisal> all = [];
        for (final emp in branchEmployees) {
          try {
            final empAppraisals = await ApiService().getAppraisals(emp.id);
            all.addAll(empAppraisals);
          } catch (_) {}
        }
        all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _appraisals = all;
      } else {
        _appraisals = await ApiService().getAppraisals(employee.id);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateDialog() {
    final role = context.read<AuthProvider>().employee?.role;
    final canCreate = role == UserRole.branchAdmin || role == UserRole.hr;
    if (!canCreate) return;

    Navigator.pushNamed(context, '/create-appraisal').then((_) => _loadAppraisals());
  }

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<AuthProvider>().employee;
    final canCreate = employee?.role == UserRole.branchAdmin || employee?.role == UserRole.hr;

    return Scaffold(
      appBar: AppBar(title: Text(S.performanceEvaluations)),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: _showCreateDialog,
              backgroundColor: AppTheme.primaryBlue,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAppraisals,
              child: _appraisals.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assessment_outlined, size: 60, color: context.colors.textMuted),
                          SizedBox(height: 12),
                          Text(S.noEvaluationsYet, style: TextStyle(color: context.colors.textSecondary)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _appraisals.length,
                      itemBuilder: (context, index) => _appraisalCard(_appraisals[index]),
                    ),
            ),
    );
  }

  Widget _appraisalCard(Appraisal appraisal) {
    final score = appraisal.overallScore;
    Color scoreColor;
    if (score >= 80) {
      scoreColor = AppTheme.accentGreen;
    } else if (score >= 60) {
      scoreColor = AppTheme.warningAmber;
    } else {
      scoreColor = AppTheme.checkOutRed;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${S.period}: ${appraisal.period}', style: TextStyle(color: context.colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('${score.toStringAsFixed(0)}%', style: TextStyle(color: scoreColor, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SizedBox(height: 8),
          if (appraisal.employeeName.isNotEmpty)
            Text('${S.employee}: ${appraisal.employeeName}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
          Text('${S.evaluator}: ${appraisal.evaluatorName}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
          if (appraisal.comments.isNotEmpty) ...[
            SizedBox(height: 6),
            Text(appraisal.comments, style: TextStyle(color: context.colors.textSecondary, fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          // Score bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: context.colors.surfaceBorder,
              color: scoreColor,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
