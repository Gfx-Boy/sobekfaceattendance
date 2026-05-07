import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/appraisal_cycle.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Lets a Branch Admin start / close appraisal cycles for their branch.
/// Super Admin sees cycles from all branches (read-only). HR sees cycles
/// for their branch (read-only) so they know whether appraisals are open.
class AppraisalCyclesScreen extends StatefulWidget {
  const AppraisalCyclesScreen({super.key});

  @override
  State<AppraisalCyclesScreen> createState() => _AppraisalCyclesScreenState();
}

class _AppraisalCyclesScreenState extends State<AppraisalCyclesScreen> {
  bool _loading = true;
  List<AppraisalCycle> _cycles = [];
  List<Branch> _branches = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      final branchId =
          (me?.role == UserRole.superAdmin) ? null : me?.branchId;
      final results = await Future.wait([
        ApiService().getAppraisalCycles(branchId: branchId),
        ApiService().getBranches(),
      ]);
      _cycles = results[0] as List<AppraisalCycle>;
      _branches = results[1] as List<Branch>;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().employee?.role;
    final canStart = role == UserRole.branchAdmin;
    return Scaffold(
      appBar: AppBar(title: Text(S.appraisalCycles)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _cycles.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 100),
                      Center(
                          child: Icon(Icons.event_busy_outlined,
                              size: 64, color: context.colors.textMuted)),
                      const SizedBox(height: 12),
                      Center(
                          child: Text(S.noAppraisalCycles,
                              style: TextStyle(
                                  color: context.colors.textSecondary))),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _cycles.length,
                      itemBuilder: (_, i) => _cycleCard(_cycles[i], canStart),
                    ),
            ),
      floatingActionButton: canStart
          ? FloatingActionButton.extended(
              onPressed: _showStartCycleDialog,
              icon: const Icon(Icons.play_arrow),
              label: Text(S.startCycle),
              backgroundColor: AppTheme.primaryBlue,
            )
          : null,
    );
  }

  Widget _cycleCard(AppraisalCycle c, bool canClose) {
    final active = c.isActive;
    final color = active ? AppTheme.accentGreen : context.colors.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.surfaceBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(active ? Icons.event_available : Icons.event_busy,
                color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                c.branchName.isNotEmpty ? c.branchName : c.branchId,
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                active ? S.active : S.closed,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _kv(Icons.date_range, S.startDate, _fmt(c.startDate)),
          _kv(Icons.event_outlined, S.endDate, _fmt(c.endDate)),
          _kv(Icons.balance, S.weights,
              '${c.adminWeight.toStringAsFixed(0)}% / ${c.hrWeight.toStringAsFixed(0)}%'),
          if (canClose && active) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _confirmClose(c),
                icon: const Icon(Icons.stop_circle_outlined,
                    color: Colors.redAccent),
                label: Text(S.closeCycle,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(IconData icon, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 14, color: context.colors.textMuted),
          const SizedBox(width: 6),
          Text('$k: ',
              style:
                  TextStyle(color: context.colors.textMuted, fontSize: 12)),
          Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary, fontSize: 12)),
        ]),
      );

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _confirmClose(AppraisalCycle c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.closeCycle),
        content: Text(S.closeCycleConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.checkOutRed),
              child: Text(S.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService().closeAppraisalCycle(c.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }

  Future<void> _showStartCycleDialog() async {
    final me = context.read<AuthProvider>().employee;
    if (me == null || me.branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.branchRequired)),
      );
      return;
    }
    // Prevent a second active cycle for the same branch.
    final existingActive =
        _cycles.any((c) => c.branchId == me.branchId && c.isActive);
    if (existingActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(S.cycleAlreadyActive),
            backgroundColor: AppTheme.warningAmber),
      );
      return;
    }

    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(days: 7));
    double adminWeight = 70;

    final branchName = _branches
        .firstWhere(
          (b) => b.id == me.branchId,
          orElse: () => Branch(
              id: me.branchId!,
              name: me.branchName ?? ''),
        )
        .name;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> pick(bool isStart) async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: isStart ? start : end,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) {
            setS(() {
              if (isStart) {
                start = picked;
                if (end.isBefore(start)) {
                  end = start.add(const Duration(days: 7));
                }
              } else {
                end = picked;
              }
            });
          }
        }

        return AlertDialog(
          backgroundColor: context.colors.cardBg,
          title: Text(S.startCycle),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${S.branch}: $branchName',
                    style: TextStyle(color: context.colors.textSecondary)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text('${S.startDate}: ${_fmt(start)}'),
                  onPressed: () => pick(true),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text('${S.endDate}: ${_fmt(end)}'),
                  onPressed: () => pick(false),
                ),
                const SizedBox(height: 16),
                Text(
                    '${S.adminWeight}: ${adminWeight.toStringAsFixed(0)}%  /  ${S.hrWeight}: ${(100 - adminWeight).toStringAsFixed(0)}%',
                    style: TextStyle(color: context.colors.textPrimary)),
                Slider(
                  value: adminWeight,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${adminWeight.toStringAsFixed(0)}%',
                  onChanged: (v) => setS(() => adminWeight = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ApiService().startAppraisalCycle(
                    branchId: me.branchId!,
                    branchName: branchName,
                    startDate: DateTime(start.year, start.month, start.day),
                    endDate: DateTime(end.year, end.month, end.day, 23, 59, 59),
                    adminWeight: adminWeight,
                    hrWeight: 100 - adminWeight,
                    createdBy: me.id,
                    createdByName: me.name,
                  );
                  await _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('$e'),
                          backgroundColor: AppTheme.checkOutRed),
                    );
                  }
                }
              },
              child: Text(S.start),
            ),
          ],
        );
      }),
    );
  }
}
