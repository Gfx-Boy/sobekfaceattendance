import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  List<Employee> _employees = [];
  String? _selectedEmployeeId;
  bool _loading = false;
  bool _loadingEmployees = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final me = context.read<AuthProvider>().employee;
      final branchId = (me?.role == UserRole.branchAdmin || me?.role == UserRole.hr)
          ? me?.branchId
          : null;
      final employees = await ApiService().getAllEmployees(branchId: branchId);
      if (mounted) {
        setState(() {
          _employees = employees;
          _loadingEmployees = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployeeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectEmployeeError), backgroundColor: AppTheme.warningAmber),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final me = context.read<AuthProvider>().employee;
      await ApiService().createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        assignedTo: _selectedEmployeeId!,
        assignedBy: me?.id ?? '',
        dueDate: _dueDate.toIso8601String(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.taskCreated), backgroundColor: AppTheme.accentGreen),
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
      appBar: AppBar(title: Text(S.createTask)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                validator: (v) => v!.isEmpty ? S.required : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: S.taskTitle, prefixIcon: Icon(Icons.task, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.description,
                  alignLabelWithHint: true,
                  prefixIcon: Padding(padding: EdgeInsets.only(bottom: 60), child: Icon(Icons.description, color: context.colors.textSecondary)),
                ),
              ),
              SizedBox(height: 12),
              // Employee dropdown
              _loadingEmployees
                  ? Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: _selectedEmployeeId,
                      dropdownColor: context.colors.cardBgLighter,
                      decoration: InputDecoration(
                        labelText: S.assignTo,
                        filled: true, fillColor: context.colors.cardBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                      ),
                      style: TextStyle(color: context.colors.textPrimary),
                      items: _employees.map((e) => DropdownMenuItem(value: e.id, child: Text('${e.name} (${e.email})'))).toList(),
                      onChanged: (v) => setState(() => _selectedEmployeeId = v),
                      validator: (v) => v == null ? S.required : null,
                    ),
              SizedBox(height: 16),
              // Due date
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: context.colors.textSecondary, size: 20),
                      SizedBox(width: 12),
                      Text(
                        '${S.dueDate}: ${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                        style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
                      ),
                      Spacer(),
                      Icon(Icons.edit, color: context.colors.textMuted, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(S.createTask),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
