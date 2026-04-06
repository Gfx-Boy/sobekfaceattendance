import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class CreateAppraisalScreen extends StatefulWidget {
  const CreateAppraisalScreen({super.key});

  @override
  State<CreateAppraisalScreen> createState() => _CreateAppraisalScreenState();
}

class _CreateAppraisalScreenState extends State<CreateAppraisalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _commentsController = TextEditingController();
  final _periodController = TextEditingController();
  List<Employee> _employees = [];
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  bool _loading = false;
  bool _loadingEmployees = true;

  // Score categories
  double _qualityScore = 70;
  double _productivityScore = 70;
  double _attendanceScore = 70;
  double _teamworkScore = 70;
  double _initiativeScore = 70;

  @override
  void initState() {
    super.initState();
    _periodController.text = _currentPeriod();
    _loadEmployees();
  }

  String _currentPeriod() {
    final now = DateTime.now();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    return 'Q$quarter ${now.year}';
  }

  @override
  void dispose() {
    _commentsController.dispose();
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
      // HR cannot evaluate themselves
      if (me != null && me.role == UserRole.hr) {
        employees = employees.where((e) => e.id != me.id).toList();
      }
      if (mounted) setState(() { _employees = employees; _loadingEmployees = false; });
    } catch (e) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  double get _overallScore => (_qualityScore + _productivityScore + _attendanceScore + _teamworkScore + _initiativeScore) / 5;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedEmployeeId == null) return;
    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      await ApiService().createAppraisal(
        employeeId: _selectedEmployeeId!,
        employeeName: _selectedEmployeeName ?? '',
        evaluatorId: me?.id ?? '',
        evaluatorName: me?.name ?? '',
        period: _periodController.text.trim(),
        scores: {
          'quality': _qualityScore,
          'productivity': _productivityScore,
          'attendance': _attendanceScore,
          'teamwork': _teamworkScore,
          'initiative': _initiativeScore,
        },
        comments: _commentsController.text.trim(),
        overallScore: _overallScore,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evaluation submitted'), backgroundColor: AppTheme.accentGreen),
        );
        Navigator.pop(context, true);
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
    return Scaffold(
      appBar: AppBar(title: Text(S.newEvaluation)),
      body: SingleChildScrollView(
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
                      decoration: _dropDecoration(S.selectEmployee),
                      style: TextStyle(color: context.colors.textPrimary),
                      items: _employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
                      onChanged: (v) => setState(() {
                        _selectedEmployeeId = v;
                        _selectedEmployeeName = _employees.firstWhere((e) => e.id == v).name;
                      }),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
              SizedBox(height: 12),
              TextFormField(
                controller: _periodController,
                validator: (v) => v!.isEmpty ? 'Required' : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: 'Period (e.g. Q1 2026)', prefixIcon: Icon(Icons.date_range, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 20),
              Text(S.scores, style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _scoreSlider(S.qualityOfWork, _qualityScore, (v) => setState(() => _qualityScore = v)),
              _scoreSlider(S.productivity, _productivityScore, (v) => setState(() => _productivityScore = v)),
              _scoreSlider(S.attendanceLabel, _attendanceScore, (v) => setState(() => _attendanceScore = v)),
              _scoreSlider(S.teamwork, _teamworkScore, (v) => setState(() => _teamworkScore = v)),
              _scoreSlider(S.initiative, _initiativeScore, (v) => setState(() => _initiativeScore = v)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(S.overallScore, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
                    Text('${_overallScore.toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _commentsController,
                maxLines: 4,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.comments,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(S.submitEvaluation),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreSlider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
              Text('${value.toInt()}%', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value,
            min: 0, max: 100,
            divisions: 20,
            activeColor: AppTheme.primaryBlue,
            inactiveColor: context.colors.surfaceBorder,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  InputDecoration _dropDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true, fillColor: context.colors.cardBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
      );
}
