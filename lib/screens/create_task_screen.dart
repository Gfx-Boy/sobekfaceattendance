import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../l10n/app_localizations.dart';
import '../widgets/blocking_overlay.dart';

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
  File? _attachment;
  String? _attachmentUrl;
  bool _uploadingAttachment = false;
  final _itemCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _itemCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    try {
      final me = context.read<AuthProvider>().employee;
      final branchId = (me?.role == UserRole.branchAdmin || me?.role == UserRole.hr)
          ? me?.branchId
          : null;
      final employees = await ApiService().getAllEmployees(branchId: branchId);

      // Apply role restrictions:
      //  - HR cannot assign to branch admin or to themselves
      //  - Branch admin cannot assign to themselves
      //  - Super admin can assign to anyone (except themselves)
      final filtered = employees.where((e) {
        if (me == null) return true;
        if (e.id == me.id) return false; // never self-assign
        if (me.role == UserRole.hr && e.role == UserRole.branchAdmin) return false;
        if (e.role == UserRole.superAdmin) return false;
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _employees = filtered;
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

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _attachment = File(picked.path);
      _attachmentUrl = null;
      _uploadingAttachment = true;
    });
    try {
      final res = await ApiService().uploadTaskAttachment(File(picked.path));
      if (mounted) {
        setState(() {
          _attachmentUrl = res['url'] as String?;
          _uploadingAttachment = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _attachment = null;
          _uploadingAttachment = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.checkOutRed),
        );
      }
    }
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
      final assignee = _employees.firstWhere(
        (e) => e.id == _selectedEmployeeId,
        orElse: () => _employees.first,
      );
      final isWarehouse = assignee.employeeType == EmployeeType.warehouse;
      await ApiService().createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        assignedTo: _selectedEmployeeId!,
        assignedBy: me?.id ?? '',
        assignedToName: assignee.name,
        assignedByName: me?.name,
        dueDate: _dueDate.toIso8601String(),
        attachments: _attachmentUrl != null ? [_attachmentUrl!] : null,
        taskType: isWarehouse ? 'warehouse' : 'general',
        itemCode: isWarehouse && _itemCodeController.text.trim().isNotEmpty
            ? _itemCodeController.text.trim()
            : null,
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
      body: BlockingOverlay(
        blocking: _loading || _uploadingAttachment,
        message: _uploadingAttachment ? S.uploading : S.pleaseWait,
        child: SingleChildScrollView(
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
                      isExpanded: true,
                      dropdownColor: context.colors.cardBgLighter,
                      decoration: InputDecoration(
                        labelText: S.assignTo,
                        filled: true, fillColor: context.colors.cardBg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                      ),
                      style: TextStyle(color: context.colors.textPrimary),
                      items: _employees
                          .map((e) => DropdownMenuItem(
                                value: e.id,
                                child: Text(
                                  '${e.name} (${e.email})',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ))
                          .toList(),
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
              // Warehouse item code (only for warehouse-type employees)
              Builder(builder: (context) {
                final assignee = _employees.firstWhere(
                  (e) => e.id == _selectedEmployeeId,
                  orElse: () => Employee(
                      id: '', name: '', email: '', department: ''),
                );
                if (assignee.employeeType != EmployeeType.warehouse) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    controller: _itemCodeController,
                    style: TextStyle(color: context.colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: S.itemCode,
                      helperText: S.itemCodeHelp,
                      prefixIcon: Icon(Icons.qr_code_2,
                          color: context.colors.textSecondary),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              // Optional attachment
              OutlinedButton.icon(
                onPressed: _uploadingAttachment ? null : _pickAttachment,
                icon: _uploadingAttachment
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
                label: Text(_attachment == null
                    ? S.attachFile
                    : (_attachmentUrl != null
                        ? '✓ ${_attachment!.uri.pathSegments.last}'
                        : '${_attachment!.uri.pathSegments.last}')),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_loading || _uploadingAttachment) ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(S.createTask),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
