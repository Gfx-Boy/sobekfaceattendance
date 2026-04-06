import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'location_picker_screen.dart';
import '../l10n/app_localizations.dart';

class EditEmployeeScreen extends StatefulWidget {
  final Employee employee;
  const EditEmployeeScreen({super.key, required this.employee});

  @override
  State<EditEmployeeScreen> createState() => _EditEmployeeScreenState();
}

class _EditEmployeeScreenState extends State<EditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _departmentController;
  late TextEditingController _positionController;
  late TextEditingController _phoneController;
  late TextEditingController _passwordController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  late TextEditingController _radiusController;
  late String _selectedRole;
  late String _selectedType;
  late bool _enableGeofence;
  LatLng? _pickedLocation;
  bool _loading = false;

  // Branch selection
  List<Branch> _branches = [];
  String? _selectedBranchId;
  String? _selectedBranchName;
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.employee.name);
    _departmentController = TextEditingController(text: widget.employee.department);
    _positionController = TextEditingController(text: widget.employee.position ?? '');
    _phoneController = TextEditingController(text: widget.employee.phone ?? '');
    _passwordController = TextEditingController();
    _selectedRole = widget.employee.role.name;
    _selectedType = widget.employee.employeeType.name;
    _enableGeofence = widget.employee.allowedLatitude != null;
    if (widget.employee.allowedLatitude != null && widget.employee.allowedLongitude != null) {
      _pickedLocation = LatLng(widget.employee.allowedLatitude!, widget.employee.allowedLongitude!);
    }
    _latitudeController = TextEditingController(text: widget.employee.allowedLatitude?.toStringAsFixed(6) ?? '');
    _longitudeController = TextEditingController(text: widget.employee.allowedLongitude?.toStringAsFixed(6) ?? '');
    _radiusController = TextEditingController(text: (widget.employee.allowedRadius ?? 200).toInt().toString());

    // Pre-populate branch from employee
    _selectedBranchId = widget.employee.branchId;
    _selectedBranchName = widget.employee.branchName;
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final myRole = context.read<AuthProvider>().employee?.role ?? UserRole.employee;
    if (myRole == UserRole.superAdmin) {
      try {
        _branches = await ApiService().getBranches();
      } catch (_) {}
    }
    if (mounted) setState(() => _loadingBranches = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _departmentController.dispose();
    _positionController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  bool get _isEditingSelf {
    final me = context.read<AuthProvider>().employee;
    return me != null && me.id == widget.employee.id;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'department': _departmentController.text.trim(),
        'role': _selectedRole,
        'employee_type': _selectedType,
        'position': _positionController.text.trim(),
        'phone': _phoneController.text.trim(),
        'branch_id': _selectedBranchId,
        'branch_name': _selectedBranchName,
      };
      if (_passwordController.text.trim().isNotEmpty) {
        updates['password'] = _passwordController.text.trim();
      }
      if (_enableGeofence) {
        updates['allowed_latitude'] = double.tryParse(_latitudeController.text.trim());
        updates['allowed_longitude'] = double.tryParse(_longitudeController.text.trim());
        updates['allowed_radius'] = double.tryParse(_radiusController.text.trim());
      } else {
        updates['allowed_latitude'] = null;
        updates['allowed_longitude'] = null;
        updates['allowed_radius'] = null;
      }
      await ApiService().updateEmployee(widget.employee.id, updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.employeeUpdated), backgroundColor: AppTheme.accentGreen),
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

  Future<void> _openMapPicker() async {
    final lat = double.tryParse(_latitudeController.text.trim());
    final lng = double.tryParse(_longitudeController.text.trim());
    final radius = double.tryParse(_radiusController.text.trim()) ?? 200;
    final result = await Navigator.push<LocationPickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: lat,
          initialLongitude: lng,
          initialRadius: radius,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _pickedLocation = LatLng(result.latitude, result.longitude);
        _latitudeController.text = result.latitude.toStringAsFixed(6);
        _longitudeController.text = result.longitude.toStringAsFixed(6);
        _radiusController.text = result.radius.toInt().toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.editEmployeeTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Email (read-only)
              TextFormField(
                initialValue: widget.employee.email,
                readOnly: true,
                style: TextStyle(color: context.colors.textSecondary),
                decoration: InputDecoration(
                  labelText: S.emailCannotChange,
                  prefixIcon: Icon(Icons.email_outlined, color: context.colors.textMuted),
                ),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                validator: (v) => v!.isEmpty ? S.required : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: S.fullName, prefixIcon: Icon(Icons.person_outline, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _departmentController,
                validator: (v) => v!.isEmpty ? S.required : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: S.department, prefixIcon: Icon(Icons.business_outlined, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _positionController,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: S.position, prefixIcon: Icon(Icons.badge_outlined, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: (v) => (v ?? '').trim().isEmpty ? S.phoneRequired : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: S.phone, prefixIcon: Icon(Icons.phone_outlined, color: context.colors.textSecondary)),
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(labelText: S.newPasswordHint, prefixIcon: Icon(Icons.lock_outline, color: context.colors.textSecondary)),
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final currentRole = context.read<AuthProvider>().employee?.role ?? UserRole.employee;
                  final targetRole = widget.employee.role;
                  final isSelf = _isEditingSelf;
                  final List<DropdownMenuItem<String>> roleItems;

                  if (isSelf) {
                    // Cannot change your own role
                    roleItems = [
                      DropdownMenuItem(value: targetRole.name, child: Text(targetRole.name)),
                    ];
                  } else if (currentRole == UserRole.superAdmin) {
                    roleItems = [
                      DropdownMenuItem(value: 'employee', child: Text(S.employee)),
                      DropdownMenuItem(value: 'hr', child: Text(S.hrManagerRole)),
                      DropdownMenuItem(value: 'branchAdmin', child: Text(S.branchAdminRole)),
                    ];
                  } else if (currentRole == UserRole.branchAdmin) {
                    // BA can change employee→hr and hr→employee, but cannot demote a branchAdmin
                    if (targetRole == UserRole.branchAdmin) {
                      // Target is branchAdmin — keep their role read-only
                      roleItems = [
                        DropdownMenuItem(value: 'branchAdmin', child: Text(S.branchAdminRole)),
                      ];
                    } else {
                      roleItems = [
                        DropdownMenuItem(value: 'employee', child: Text(S.employee)),
                        DropdownMenuItem(value: 'hr', child: Text(S.hrManagerRole)),
                      ];
                    }
                  } else {
                    roleItems = [
                      DropdownMenuItem(value: 'employee', child: Text(S.employee)),
                    ];
                  }
                  // Ensure current _selectedRole is valid
                  if (!roleItems.any((item) => item.value == _selectedRole)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedRole = targetRole.name);
                    });
                  }
                  return DropdownButtonFormField<String>(
                    value: roleItems.any((i) => i.value == _selectedRole) ? _selectedRole : roleItems.first.value,
                    dropdownColor: context.colors.cardBgLighter,
                    decoration: InputDecoration(
                      labelText: S.role,
                      filled: true, fillColor: context.colors.cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                    ),
                    style: TextStyle(color: context.colors.textPrimary),
                    items: roleItems,
                    onChanged: (v) => setState(() => _selectedRole = v!),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Branch selection
              Builder(builder: (ctx) {
                final myRole = ctx.read<AuthProvider>().employee?.role ?? UserRole.employee;
                if (myRole == UserRole.superAdmin) {
                  if (_loadingBranches) {
                    return Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
                  }
                  if (_branches.isEmpty) {
                    return Text(S.noBranchesAvailable, style: TextStyle(color: context.colors.textSecondary));
                  }
                  final branchItems = _branches.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList();
                  // Ensure selected is valid
                  if (_selectedBranchId != null && !_branches.any((b) => b.id == _selectedBranchId)) {
                    _selectedBranchId = _branches.first.id;
                    _selectedBranchName = _branches.first.name;
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedBranchId,
                    dropdownColor: context.colors.cardBgLighter,
                    decoration: InputDecoration(
                      labelText: S.branch,
                      filled: true, fillColor: context.colors.cardBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                    ),
                    style: TextStyle(color: context.colors.textPrimary),
                    items: branchItems,
                    onChanged: (v) => setState(() {
                      _selectedBranchId = v;
                      _selectedBranchName = _branches.firstWhere((b) => b.id == v).name;
                    }),
                  );
                } else if (_selectedBranchName != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(Icons.business, color: context.colors.textSecondary, size: 20),
                      SizedBox(width: 8),
                      Text('${S.branch}: $_selectedBranchName', style: TextStyle(color: context.colors.textSecondary)),
                    ]),
                  );
                }
                return const SizedBox.shrink();
              }),
              SizedBox(height: 12),
              if (_selectedRole == 'employee')
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  dropdownColor: context.colors.cardBgLighter,
                  decoration: InputDecoration(
                    labelText: S.employeeTypeLabel,
                    filled: true, fillColor: context.colors.cardBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
                  ),
                  style: TextStyle(color: context.colors.textPrimary),
                  items: [
                    DropdownMenuItem(value: 'general', child: Text(S.general)),
                    DropdownMenuItem(value: 'sales', child: Text(S.sales)),
                    DropdownMenuItem(value: 'accountant', child: Text(S.accountant)),
                    DropdownMenuItem(value: 'warehouse', child: Text(S.warehouse)),
                  ],
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
              SizedBox(height: 16),
              // Geofence section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, color: AppTheme.primaryBlue, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(S.locationRestriction, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: _enableGeofence,
                          activeColor: AppTheme.primaryBlue,
                          onChanged: _isEditingSelf ? null : (v) => setState(() => _enableGeofence = v),
                        ),
                      ],
                    ),
                    if (_enableGeofence) ...[
                      SizedBox(height: 8),
                      Text(
                        S.geofenceAttendanceNote,
                        style: TextStyle(color: context.colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latitudeController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              validator: _enableGeofence ? (v) => v!.isEmpty ? S.required : null : null,
                              style: TextStyle(color: context.colors.textPrimary),
                              decoration: InputDecoration(labelText: S.latitude, prefixIcon: Icon(Icons.my_location, color: context.colors.textSecondary)),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _longitudeController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              validator: _enableGeofence ? (v) => v!.isEmpty ? S.required : null : null,
                              style: TextStyle(color: context.colors.textPrimary),
                              decoration: InputDecoration(labelText: S.longitude, prefixIcon: Icon(Icons.my_location, color: context.colors.textSecondary)),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: _radiusController,
                        keyboardType: TextInputType.number,
                        validator: _enableGeofence ? (v) => v!.isEmpty ? S.required : null : null,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: InputDecoration(labelText: S.radiusMeters, prefixIcon: Icon(Icons.radar, color: context.colors.textSecondary)),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openMapPicker,
                          icon: const Icon(Icons.map_outlined),
                          label: Text(_pickedLocation == null ? S.pickLocationOnMap : S.changeLocation),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryBlue,
                            side: const BorderSide(color: AppTheme.primaryBlue),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(S.saveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
