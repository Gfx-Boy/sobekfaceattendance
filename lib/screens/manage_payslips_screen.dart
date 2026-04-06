import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../models/payslip.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class ManagePayslipsScreen extends StatefulWidget {
  const ManagePayslipsScreen({super.key});

  @override
  State<ManagePayslipsScreen> createState() => _ManagePayslipsScreenState();
}

class _ManagePayslipsScreenState extends State<ManagePayslipsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _basicController = TextEditingController();
  final _bonusController = TextEditingController(text: '0');
  final _deductionsController = TextEditingController(text: '0');
  final _overtimeController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _periodController = TextEditingController();
  List<Employee> _employees = [];
  List<Payslip> _payslips = [];
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  bool _loading = false;
  bool _loadingEmployees = true;
  bool _loadingPayslips = true;

  @override
  void initState() {
    super.initState();
    final role = context.read<AuthProvider>().employee?.role;
    final isSA = role == UserRole.superAdmin;
    _tabController = TabController(length: isSA ? 1 : 2, vsync: this);
    final now = DateTime.now();
    _periodController.text = '${_monthName(now.month)} ${now.year}';
    _loadEmployees();
    _loadPayslips();
  }

  String _monthName(int m) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];

  @override
  void dispose() {
    _tabController.dispose();
    _basicController.dispose();
    _bonusController.dispose();
    _deductionsController.dispose();
    _overtimeController.dispose();
    _notesController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final me = context.read<AuthProvider>().employee;
      final branchId = (me?.role == UserRole.branchAdmin || me?.role == UserRole.hr)
          ? me?.branchId
          : null;
      List<Employee> employees = await ApiService().getAllEmployees(branchId: branchId);
      // BA cannot create payslip for himself
      // HR cannot create payslip for BA or for himself
      if (me != null) {
        if (me.role == UserRole.branchAdmin) {
          employees = employees.where((e) => e.id != me.id).toList();
        } else if (me.role == UserRole.hr) {
          employees = employees.where((e) =>
            e.id != me.id && e.role != UserRole.branchAdmin
          ).toList();
        }
      }
      if (mounted) setState(() { _employees = employees; _loadingEmployees = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  Future<void> _loadPayslips() async {
    setState(() => _loadingPayslips = true);
    try {
      final me = context.read<AuthProvider>().employee;
      if (me == null) return;
      if (me.role == UserRole.superAdmin) {
        _payslips = await ApiService().getAllPayslips();
      } else {
        // BA/HR: load payslips for all employees in branch
        final branchEmployees = _employees.isNotEmpty ? _employees : await ApiService().getAllEmployees(branchId: me.branchId);
        final List<Payslip> all = [];
        for (final emp in branchEmployees) {
          try {
            final empPayslips = await ApiService().getPayslips(emp.id);
            all.addAll(empPayslips);
          } catch (_) {}
        }
        all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _payslips = all;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPayslips = false);
  }

  double get _net {
    final basic = double.tryParse(_basicController.text) ?? 0;
    final bonus = double.tryParse(_bonusController.text) ?? 0;
    final ded = double.tryParse(_deductionsController.text) ?? 0;
    final ot = double.tryParse(_overtimeController.text) ?? 0;
    return basic + bonus + ot - ded;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedEmployeeId == null) return;
    setState(() => _loading = true);
    try {
      await ApiService().createPayslip(
        employeeId: _selectedEmployeeId!,
        employeeName: _selectedEmployeeName ?? '',
        period: _periodController.text.trim(),
        basicSalary: double.tryParse(_basicController.text) ?? 0,
        bonuses: double.tryParse(_bonusController.text) ?? 0,
        deductions: double.tryParse(_deductionsController.text) ?? 0,
        overtimePay: double.tryParse(_overtimeController.text) ?? 0,
        notes: _notesController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payslip created'), backgroundColor: AppTheme.accentGreen),
        );
        // Clear form and switch to list
        _basicController.clear();
        _bonusController.text = '0';
        _deductionsController.text = '0';
        _overtimeController.text = '0';
        _notesController.clear();
        _selectedEmployeeId = null;
        _selectedEmployeeName = null;
        setState(() => _loading = false);
        _loadPayslips();
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().employee?.role;
    final isSA = role == UserRole.superAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.payslips),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPayslips),
        ],
        bottom: isSA
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primaryBlue,
                tabs: [
                  Tab(text: S.allPayslips),
                  Tab(text: S.createNew),
                ],
              ),
      ),
      body: isSA
          ? _buildPayslipsList()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPayslipsList(),
                _buildCreateForm(),
              ],
            ),
    );
  }

  Widget _buildPayslipsList() {
    if (_loadingPayslips) {
      return Center(child: CircularProgressIndicator());
    }
    if (_payslips.isEmpty) {
      return Center(child: Text(S.noPayslipsFound, style: TextStyle(color: context.colors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _loadPayslips,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _payslips.length,
        itemBuilder: (ctx, i) => _payslipCard(_payslips[i]),
      ),
    );
  }

  Widget _buildCreateForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _loadingEmployees
                ? Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    value: _selectedEmployeeId,
                    dropdownColor: context.colors.cardBgLighter,
                    decoration: _dec(S.selectEmployee),
                    style: TextStyle(color: context.colors.textPrimary),
                    items: _employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                    onChanged: (v) => setState(() {
                      _selectedEmployeeId = v;
                      _selectedEmployeeName = _employees.firstWhere((e) => e.id == v).name;
                    }),
                    validator: (v) => v == null ? S.required : null,
                  ),
            SizedBox(height: 12),
            TextFormField(
              controller: _periodController,
              validator: (v) => v!.isEmpty ? S.required : null,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: _dec(S.period).copyWith(prefixIcon: Icon(Icons.calendar_month, color: context.colors.textSecondary)),
            ),
            SizedBox(height: 16),
            Text(S.salaryBreakdown, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
            SizedBox(height: 12),
            TextFormField(
              controller: _basicController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) => v!.isEmpty ? S.required : null,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: _dec(S.basicSalary).copyWith(prefixIcon: Icon(Icons.attach_money, color: context.colors.textSecondary)),
            ),
            SizedBox(height: 10),
            TextFormField(
              controller: _bonusController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: context.colors.textPrimary),
              decoration: _dec(S.bonuses).copyWith(prefixIcon: Icon(Icons.card_giftcard, color: AppTheme.accentGreen)),
            ),
            SizedBox(height: 10),
            TextFormField(
              controller: _overtimeController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: context.colors.textPrimary),
              decoration: _dec(S.overtimePay).copyWith(prefixIcon: Icon(Icons.access_time, color: AppTheme.primaryBlue)),
            ),
            SizedBox(height: 10),
            TextFormField(
              controller: _deductionsController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: context.colors.textPrimary),
              decoration: _dec(S.deductions).copyWith(prefixIcon: const Icon(Icons.remove_circle_outline, color: AppTheme.checkOutRed)),
            ),
            SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.accentGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(S.netSalary, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
                  Text('\$${_net.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.accentGreen, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: _dec(S.notesOptional),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(S.createPayslip),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payslipCard(Payslip p) {
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
            Expanded(child: Text(p.employeeName, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15))),
            Text(p.period, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
          ]),
          SizedBox(height: 6),
          Row(children: [
            Icon(Icons.attach_money, size: 14, color: AppTheme.accentGreen),
            SizedBox(width: 4),
            Text('Net: \$${p.netSalary.toStringAsFixed(2)}', style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.w600)),
            SizedBox(width: 16),
            Text('Basic: \$${p.basicSalary.toStringAsFixed(2)}', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
          ]),
          if (p.notes.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(p.notes, style: TextStyle(color: context.colors.textMuted, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          SizedBox(height: 4),
          Text(DateFormat('MMM d, y').format(p.createdAt), style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true, fillColor: context.colors.cardBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
      );
}
