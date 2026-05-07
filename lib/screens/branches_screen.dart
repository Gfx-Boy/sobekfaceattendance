import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  List<Branch> _branches = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      setState(() => _loading = true);
      final all = await ApiService().getBranches();
      final me = context.read<AuthProvider>().employee;
      // Branch admin only sees own branch (#14).
      List<Branch> visible;
      if (me?.role == UserRole.branchAdmin && me?.branchId != null) {
        visible = all.where((b) => b.id == me!.branchId).toList();
      } else {
        visible = all;
      }
      if (mounted) setState(() { _branches = visible; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isSuperAdmin {
    final role = context.read<AuthProvider>().employee?.role;
    return role == UserRole.superAdmin;
  }

  void _showBranchDialog({Branch? branch}) {
    final isEdit = branch != null;
    final nameController = TextEditingController(text: branch?.name ?? '');
    final addressController = TextEditingController(text: branch?.address ?? '');
    String selectedStatus = branch?.status ?? 'work';
    DateTime? validityStart = branch?.validityStart;
    DateTime? validityEnd = branch?.validityEnd;
    final breakController = TextEditingController(text: '${branch?.breakDurationMinutes ?? 60}');
    String? nameError;

    // Deduction controllers
    final lateDeductionCtl = TextEditingController(text: '${branch?.deductionLate ?? 0}');
    final earlyOutDeductionCtl = TextEditingController(text: '${branch?.deductionEarlyOut ?? 0}');
    final absentDeductionCtl = TextEditingController(text: '${branch?.deductionAbsent ?? 0}');

    // Parse existing working days (default Mon-Fri)
    List<String> selectedDays = List<String>.from(branch?.workingDays ?? Branch.defaultWorkingDays);

    // Parse existing working hours into TimeOfDay
    TimeOfDay? workStart;
    TimeOfDay? workEnd;
    if (branch?.workingHoursStart != null) {
      final parts = branch!.workingHoursStart.split(':');
      workStart = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
    }
    if (branch?.workingHoursEnd != null) {
      final parts = branch!.workingHoursEnd.split(':');
      workEnd = TimeOfDay(hour: int.tryParse(parts[0]) ?? 18, minute: int.tryParse(parts[1]) ?? 0);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickDate(bool isStart) async {
            final initial = isStart ? validityStart : validityEnd;
            final picked = await showDatePicker(
              context: ctx,
              initialDate: initial ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              setDialogState(() {
                if (isStart) {
                  validityStart = picked;
                  validityEnd ??= DateTime(picked.year, picked.month + 1, picked.day);
                } else {
                  validityEnd = picked;
                }
              });
            }
          }

          Future<void> pickTime(bool isStart) async {
            final initial = isStart
                ? (workStart ?? const TimeOfDay(hour: 9, minute: 0))
                : (workEnd ?? const TimeOfDay(hour: 18, minute: 0));
            final picked = await showTimePicker(context: ctx, initialTime: initial);
            if (picked != null) {
              setDialogState(() {
                if (isStart) workStart = picked;
                else workEnd = picked;
              });
            }
          }

          String fmtTime(TimeOfDay? t) => t == null
              ? S.selectTime
              : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

          void validateName() {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              setDialogState(() => nameError = S.required);
              return;
            }
            final duplicate = _branches.any((b) =>
                b.name.toLowerCase() == name.toLowerCase() &&
                (!isEdit || b.id != branch!.id));
            setDialogState(() => nameError = duplicate ? S.branchNameUnique : null);
          }

          return AlertDialog(
            backgroundColor: context.colors.cardBg,
            title: Text(isEdit ? S.editBranch : S.addBranch),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    enabled: !isEdit, // Branch name cannot be edited (unique identifier)
                    style: TextStyle(color: isEdit ? context.colors.textMuted : context.colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: '${S.branchName} *',
                      errorText: nameError,
                    ),
                    onChanged: (_) => validateName(),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: addressController,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(labelText: S.address),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: context.colors.cardBg,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(labelText: S.status),
                    items: [
                      DropdownMenuItem(value: 'work', child: Text(S.statusWorking)),
                      DropdownMenuItem(value: 'hold', child: Text(S.statusOnHold)),
                      DropdownMenuItem(value: 'closed', child: Text(S.statusClosed)),
                    ],
                    onChanged: (v) => setDialogState(() => selectedStatus = v ?? 'work'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => pickDate(true),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: S.validityStart),
                            child: Text(
                              validityStart != null ? DateFormat('MMM d, y', S.locale.languageCode).format(validityStart!) : 'Select date',
                              style: TextStyle(color: validityStart != null ? context.colors.textPrimary : context.colors.textMuted, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => pickDate(false),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: S.validityEnd),
                            child: Text(
                              validityEnd != null ? DateFormat('MMM d, y', S.locale.languageCode).format(validityEnd!) : 'Select date',
                              style: TextStyle(color: validityEnd != null ? context.colors.textPrimary : context.colors.textMuted, fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text(S.workingHours, style: TextStyle(color: context.colors.textSecondary, fontSize: 12))),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => pickTime(true),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: S.start, isDense: true),
                            child: Text(fmtTime(workStart),
                              style: TextStyle(
                                color: workStart != null ? context.colors.textPrimary : context.colors.textMuted,
                                fontSize: 14,
                              )),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => pickTime(false),
                          child: InputDecorator(
                            decoration: InputDecoration(labelText: S.end, isDense: true),
                            child: Text(fmtTime(workEnd),
                              style: TextStyle(
                                color: workEnd != null ? context.colors.textPrimary : context.colors.textMuted,
                                fontSize: 14,
                              )),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: breakController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(labelText: '${S.breakDuration} (${S.minutes})', isDense: true),
                  ),
                  SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text(S.workingDays, style: TextStyle(color: context.colors.textSecondary, fontSize: 12))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: Branch.allDays.map((day) {
                      final isSelected = selectedDays.contains(day);
                      return FilterChip(
                        label: Text(day.substring(0, 3)),
                        selected: isSelected,
                        onSelected: (val) => setDialogState(() {
                          if (val) selectedDays.add(day);
                          else selectedDays.remove(day);
                        }),
                        selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.3),
                        checkmarkColor: AppTheme.primaryBlue,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Deductions section
                  Align(alignment: Alignment.centerLeft, child: Text(S.deductions, style: TextStyle(color: context.colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600))),
                  const SizedBox(height: 4),
                  TextField(
                    controller: lateDeductionCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(labelText: S.deductionLate, isDense: true),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: earlyOutDeductionCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(labelText: S.deductionEarlyOut, isDense: true),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: absentDeductionCtl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(labelText: S.deductionAbsent, isDense: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
              TextButton(
                onPressed: () async {
                  // Validate name
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setDialogState(() => nameError = S.required);
                    return;
                  }
                  if (!isEdit) {
                    final duplicate = _branches.any((b) => b.name.toLowerCase() == name.toLowerCase());
                    if (duplicate) {
                      setDialogState(() => nameError = S.branchNameUnique);
                      return;
                    }
                  }
                  final startStr = workStart != null
                      ? '${workStart!.hour.toString().padLeft(2, '0')}:${workStart!.minute.toString().padLeft(2, '0')}'
                      : '09:00';
                  final endStr = workEnd != null
                      ? '${workEnd!.hour.toString().padLeft(2, '0')}:${workEnd!.minute.toString().padLeft(2, '0')}'
                      : '18:00';
                  Navigator.pop(ctx);
                  try {
                    if (isEdit) {
                      final updated = await ApiService().updateBranch(branch!.id, {
                        'address': addressController.text.trim(),
                        'status': selectedStatus,
                        'validity_start': validityStart?.toIso8601String(),
                        'validity_end': validityEnd?.toIso8601String(),
                        'working_hours_start': startStr,
                        'working_hours_end': endStr,
                        'break_duration_minutes': int.tryParse(breakController.text) ?? 60,
                        'working_days': selectedDays,
                        'deduction_late': double.tryParse(lateDeductionCtl.text) ?? 0,
                        'deduction_early_out': double.tryParse(earlyOutDeductionCtl.text) ?? 0,
                        'deduction_absent': double.tryParse(absentDeductionCtl.text) ?? 0,
                      });
                      // Optimistically update local list — S3 read-after-write can be stale
                      if (mounted) {
                        setState(() {
                          final idx = _branches.indexWhere((b) => b.id == updated.id);
                          if (idx != -1) _branches[idx] = updated;
                        });
                      }
                    } else {
                      final created = await ApiService().createBranch(
                        name: nameController.text.trim(),
                        address: addressController.text.trim(),
                        status: selectedStatus,
                        validityStart: validityStart?.toIso8601String(),
                        validityEnd: validityEnd?.toIso8601String(),
                        workingHoursStart: startStr,
                        workingHoursEnd: endStr,
                        breakDurationMinutes: int.tryParse(breakController.text) ?? 60,
                        workingDays: selectedDays,
                        deductionLate: double.tryParse(lateDeductionCtl.text) ?? 0,
                        deductionEarlyOut: double.tryParse(earlyOutDeductionCtl.text) ?? 0,
                        deductionAbsent: double.tryParse(absentDeductionCtl.text) ?? 0,
                      );
                      if (mounted) {
                        setState(() => _branches.add(created));
                      }
                    }
                    // Background refresh after a short delay so S3 settles
                    Future.delayed(const Duration(seconds: 2), _loadBranches);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isEdit ? S.branchUpdated : S.branchCreated),
                          backgroundColor: AppTheme.accentGreen,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e'), backgroundColor: AppTheme.checkOutRed),
                      );
                    }
                  }
                },
                child: Text(isEdit ? S.save : S.add),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(Branch branch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.cardBg,
        title: Text(S.deleteBranch),
        content: Text(S.deleteConfirmMessage(branch.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService().deleteBranch(branch.id);
                _loadBranches();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
                  );
                }
              }
            },
            child: Text(S.delete, style: TextStyle(color: AppTheme.checkOutRed)),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'work': return AppTheme.accentGreen;
      case 'hold': return AppTheme.warningAmber;
      case 'closed': return AppTheme.checkOutRed;
      default: return context.colors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.branches)),
      floatingActionButton: _isSuperAdmin
          ? FloatingActionButton(
              onPressed: () => _showBranchDialog(),
              backgroundColor: AppTheme.primaryBlue,
              child: Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: context.colors.textPrimary),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: S.search,
                    prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
                    filled: true,
                    fillColor: context.colors.cardBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.colors.surfaceBorder)),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadBranches,
                  child: Builder(builder: (context) {
                    final list = _query.isEmpty
                        ? _branches
                        : _branches
                            .where((b) =>
                                b.name.toLowerCase().contains(_query) ||
                                b.address.toLowerCase().contains(_query))
                            .toList();
                    if (list.isEmpty) {
                      return Center(child: Text(S.noBranchesYet, style: TextStyle(color: context.colors.textSecondary)));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final branch = list[index];
                        final sColor = _statusColor(branch.status);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
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
                                decoration: BoxDecoration(
                                  color: sColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.business, color: sColor, size: 26),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(branch.name, style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                                    if (branch.address.isNotEmpty)
                                      Text(branch.address, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: sColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            branch.statusDisplayName,
                                            style: TextStyle(color: sColor, fontSize: 10, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        if (branch.validityEnd != null) ...[
                                          SizedBox(width: 8),
                                          Text(
                                            S.untilDate(DateFormat('MMM d, y', S.locale.languageCode).format(branch.validityEnd!)),
                                            style: TextStyle(color: context.colors.textMuted, fontSize: 10),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryBlue, size: 20),
                                onPressed: () => _showBranchDialog(branch: branch),
                                tooltip: S.edit,
                              ),
                              if (_isSuperAdmin)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.checkOutRed, size: 20),
                                  onPressed: () => _confirmDelete(branch),
                                  tooltip: S.delete,
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
            ]),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
