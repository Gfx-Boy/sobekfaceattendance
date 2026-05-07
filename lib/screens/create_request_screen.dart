import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/request.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _emailFieldController = TextEditingController();
  final _phoneFieldController = TextEditingController();
  final _actionController = TextEditingController();
  late String _category;
  late String _type;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _permissionDuration; // '2' or '4'
  TimeOfDay? _permissionTime;
  String? _leaveReason;
  String? _applicationType;
  String? _equipmentType;
  bool _loading = false;
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    _category = 'hr';
    _type = 'vacation';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initDone) {
      _initDone = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final cat = args['category'] as String?;
        final typ = args['type'] as String?;
        if (cat != null) _category = cat.toLowerCase();
        if (typ != null) _type = typ;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _emailFieldController.dispose();
    _phoneFieldController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startDate = picked;
        else _endDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _permissionTime = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate type-specific required fields
    if (_type == 'vacation' && (_startDate == null || _endDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.vacationDatesRequired), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'permission' && _permissionDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectPermissionDuration), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'permission' && _permissionTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectPermissionTime), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'leave' && _leaveReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectLeaveReason), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'leave' && _startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.dateRequiredForLeave), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'businessMission' && (_startDate == null || _endDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.missionDatesRequired), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'applications' && _applicationType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectApplicationType), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'equipment' && _equipmentType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.selectEquipmentType), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }
    if (_type == 'emailAndUserAccount') {
      if (_emailFieldController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.emailRequiredForType), backgroundColor: AppTheme.checkOutRed),
        );
        return;
      }
      if (_phoneFieldController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.phoneRequired), backgroundColor: AppTheme.checkOutRed),
        );
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final employee = context.read<AuthProvider>().employee;

      // Build extra fields based on type
      final extra = <String, dynamic>{};
      if (_type == 'permission') {
        extra['permission_hours'] = _permissionDuration;
        if (_permissionTime != null) {
          extra['permission_time'] = '${_permissionTime!.hour.toString().padLeft(2, '0')}:${_permissionTime!.minute.toString().padLeft(2, '0')}';
        }
      }
      if (_type == 'leave') {
        extra['leave_reason'] = _leaveReason;
      }
      if (_type == 'businessMission') {
        extra['required_action'] = _actionController.text.trim();
      }
      if (_type == 'applications') {
        extra['application_type'] = _applicationType;
      }
      if (_type == 'equipment') {
        extra['equipment_type'] = _equipmentType;
      }
      if (_type == 'emailAndUserAccount') {
        extra['contact_email'] = _emailFieldController.text.trim();
        extra['contact_phone'] = _phoneFieldController.text.trim();
      }

      await ApiService().createRequest(
        employeeId: employee?.id ?? '',
        employeeName: employee?.name ?? '',
        employeeEmail: employee?.email ?? '',
        branchName: employee?.branchName ?? '',
        category: _category,
        type: _type,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        startDate: _startDate?.toIso8601String(),
        endDate: _endDate?.toIso8601String(),
        extraFields: extra.isNotEmpty ? extra : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.requestSubmitted), backgroundColor: AppTheme.accentGreen),
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
      appBar: AppBar(title: Text(S.newRequest)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Request date (read-only, today)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, color: AppTheme.primaryBlue, size: 18),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.requestDate, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('EEEE dd-MM-yyyy', S.locale.languageCode).format(DateTime.now()),
                          style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Category
              DropdownButtonFormField<String>(
                value: _category,
                dropdownColor: context.colors.cardBgLighter,
                decoration: _dropDecoration(S.category),
                style: TextStyle(color: context.colors.textPrimary),
                items: [
                  DropdownMenuItem(value: 'hr', child: Text(S.hrRequest)),
                  DropdownMenuItem(value: 'it', child: Text(S.itRequest)),
                ],
                onChanged: (v) => setState(() {
                  _category = v!;
                  _type = _category == 'hr' ? 'vacation' : 'emailAndUserAccount';
                }),
              ),
              SizedBox(height: 12),
              // Type
              DropdownButtonFormField<String>(
                value: _type,
                dropdownColor: context.colors.cardBgLighter,
                decoration: _dropDecoration(S.requestType),
                style: TextStyle(color: context.colors.textPrimary),
                items: _category == 'hr'
                    ? [
                        DropdownMenuItem(value: 'vacation', child: Text(S.vacation)),
                        DropdownMenuItem(value: 'leave', child: Text(S.leave)),

                        DropdownMenuItem(value: 'permission', child: Text(S.permission)),
                        DropdownMenuItem(value: 'businessMission', child: Text(S.businessMission)),
                        DropdownMenuItem(value: 'other', child: Text(S.other)),
                      ]
                    : [
                        DropdownMenuItem(value: 'emailAndUserAccount', child: Text(S.emailUserAccount)),
                        DropdownMenuItem(value: 'accessRight', child: Text(S.accessRight)),
                        DropdownMenuItem(value: 'equipment', child: Text(S.equipment)),
                        DropdownMenuItem(value: 'applications', child: Text(S.applications)),
                      ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                validator: (v) => (v ?? '').trim().isEmpty ? S.titleRequired : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: '${S.title} *', prefixIcon: Icon(Icons.title, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                validator: (v) => (v ?? '').trim().isEmpty ? S.descriptionRequired : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.description,
                  alignLabelWithHint: true,
                  prefixIcon: Padding(padding: EdgeInsets.only(bottom: 60), child: Icon(Icons.description, color: context.colors.textSecondary)),
                ),
              ),
              const SizedBox(height: 16),
              // ── Type-specific fields ──
              ..._buildTypeSpecificFields(),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(S.submitRequest),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTypeSpecificFields() {
    switch (_type) {
      case 'vacation':
        return [
          Row(
            children: [
              Expanded(child: _dateButton(S.startDate, _startDate, () => _pickDate(true))),
              const SizedBox(width: 12),
              Expanded(child: _dateButton(S.endDate, _endDate, () => _pickDate(false))),
            ],
          ),
        ];

      case 'permission':
        return [
          DropdownButtonFormField<String>(
            value: _permissionDuration,
            dropdownColor: context.colors.cardBgLighter,
            decoration: _dropDecoration(S.duration),
            style: TextStyle(color: context.colors.textPrimary),
            items: [
              DropdownMenuItem(value: '2', child: Text(S.twoHours)),
              DropdownMenuItem(value: '4', child: Text(S.fourHours)),
            ],
            onChanged: (v) => setState(() => _permissionDuration = v),
          ),
          const SizedBox(height: 12),
          _timeButton(S.permissionTime, _permissionTime, _pickTime),
        ];

      case 'businessMission':
        return [
          Row(
            children: [
              Expanded(child: _dateButton(S.fromDate, _startDate, () => _pickDate(true))),
              const SizedBox(width: 12),
              Expanded(child: _dateButton(S.toDate, _endDate, () => _pickDate(false))),
            ],
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _actionController,
            validator: (v) => v!.isEmpty ? S.required : null,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: S.requiredAction,
              prefixIcon: Icon(Icons.assignment, color: context.colors.textSecondary),
            ),
          ),
        ];

      case 'leave':
        return [
          DropdownButtonFormField<String>(
            value: _leaveReason,
            dropdownColor: context.colors.cardBgLighter,
            decoration: _dropDecoration(S.leaveReason),
            style: TextStyle(color: context.colors.textPrimary),
            items: [
              DropdownMenuItem(value: 'sick', child: Text(S.sickLeave)),
              DropdownMenuItem(value: 'personal', child: Text(S.personal)),
              DropdownMenuItem(value: 'family', child: Text(S.familyEmergency)),
              DropdownMenuItem(value: 'bereavement', child: Text(S.bereavement)),
              DropdownMenuItem(value: 'other', child: Text(S.other)),
            ],
            onChanged: (v) => setState(() => _leaveReason = v),
          ),
          const SizedBox(height: 12),
          _dateButton('${S.date} *', _startDate, () => _pickDate(true)),
        ];

      case 'applications':
        return [
          DropdownButtonFormField<String>(
            value: _applicationType,
            dropdownColor: context.colors.cardBgLighter,
            decoration: _dropDecoration(S.applicationType),
            style: TextStyle(color: context.colors.textPrimary),
            items: [
              DropdownMenuItem(value: 'sales', child: Text(S.sales)),
              DropdownMenuItem(value: 'accountant', child: Text(S.accountant)),
              DropdownMenuItem(value: 'warehouse', child: Text(S.warehouse)),
              DropdownMenuItem(value: 'other', child: Text(S.other)),
            ],
            onChanged: (v) => setState(() => _applicationType = v),
          ),
        ];

      case 'equipment':
        return [
          DropdownButtonFormField<String>(
            value: _equipmentType,
            dropdownColor: context.colors.cardBgLighter,
            decoration: _dropDecoration(S.equipmentType),
            style: TextStyle(color: context.colors.textPrimary),
            items: [
              DropdownMenuItem(value: 'laptop', child: Text(S.laptop)),
              DropdownMenuItem(value: 'usb', child: Text(S.usb)),
              DropdownMenuItem(value: 'printer', child: Text(S.printer)),
              DropdownMenuItem(value: 'other', child: Text(S.other)),
            ],
            onChanged: (v) => setState(() => _equipmentType = v),
          ),
        ];

      case 'emailAndUserAccount':
        return [
          TextFormField(
            controller: _emailFieldController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: '${S.email} *',
              prefixIcon: Icon(Icons.email_outlined, color: context.colors.textSecondary),
            ),
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _phoneFieldController,
            keyboardType: TextInputType.phone,
            validator: (v) => (v ?? '').trim().isEmpty ? S.phoneRequired : null,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              labelText: '${S.phoneNumber} *',
              prefixIcon: Icon(Icons.phone_outlined, color: context.colors.textSecondary),
            ),
          ),
        ];

      default:
        return [];
    }
  }

  InputDecoration _dropDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true, fillColor: context.colors.cardBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
    );
  }

  Widget _dateButton(String label, DateTime? date, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
            SizedBox(height: 4),
            Text(
              date != null ? '${date.day}/${date.month}/${date.year}' : S.selectDate,
              style: TextStyle(color: date != null ? context.colors.textPrimary : context.colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeButton(String label, TimeOfDay? time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
            SizedBox(height: 4),
            Text(
              time != null ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : S.selectTime,
              style: TextStyle(color: time != null ? context.colors.textPrimary : context.colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
