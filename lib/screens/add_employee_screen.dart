import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/branch.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'location_picker_screen.dart';
import '../l10n/app_localizations.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _positionController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _radiusController = TextEditingController(text: '200');
  LatLng? _pickedLocation;
  String _selectedRole = 'employee';
  String _selectedType = 'general';
  String _selectedDepartment = 'sales';
  bool _loading = false;
  bool _enableGeofence = false;
  bool _obscurePassword = true;
  File? _referenceImage;

  // Branch selection
  List<Branch> _branches = [];
  String? _selectedBranchId;
  String? _selectedBranchName;
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final auth = context.read<AuthProvider>();
    final myRole = auth.employee?.role ?? UserRole.employee;

    if (myRole == UserRole.superAdmin) {
      try {
        _branches = await ApiService().getBranches();
        if (_branches.isNotEmpty) {
          _selectedBranchId = _branches.first.id;
          _selectedBranchName = _branches.first.name;
        }
      } catch (_) {}
    } else {
      // branchAdmin / HR — auto-assign own branch
      _selectedBranchId = auth.employee?.branchId;
      _selectedBranchName = auth.employee?.branchName;
      // Pre-populate geofence from BA's own location
      final ba = auth.employee;
      if (ba?.allowedLatitude != null && ba?.allowedLongitude != null) {
        _enableGeofence = true;
        _latitudeController.text = ba!.allowedLatitude!.toString();
        _longitudeController.text = ba.allowedLongitude!.toString();
        if (ba.allowedRadius != null) {
          _radiusController.text = ba.allowedRadius!.toString();
        }
        _pickedLocation = LatLng(ba.allowedLatitude!, ba.allowedLongitude!);
      }
    }
    if (mounted) setState(() => _loadingBranches = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _captureReferenceImage() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    if (!mounted) return;
    final File? result = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _ReferenceCaptureScreen(camera: frontCamera),
      ),
    );

    if (result != null && mounted) {
      setState(() => _referenceImage = result);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_referenceImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.captureReferenceImage), backgroundColor: AppTheme.checkOutRed),
      );
      return;
    }


    setState(() => _loading = true);
    try {
      await ApiService().createEmployee(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        department: _selectedDepartment,
        referenceImage: _referenceImage!,
        password: _passwordController.text.trim(),
        role: _selectedRole,
        employeeType: _selectedType,
        branchId: _selectedBranchId,
        branchName: _selectedBranchName,
        position: _positionController.text.trim().isNotEmpty ? _positionController.text.trim() : null,
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        allowedLatitude: _enableGeofence && _latitudeController.text.isNotEmpty
            ? double.tryParse(_latitudeController.text.trim())
            : null,
        allowedLongitude: _enableGeofence && _longitudeController.text.isNotEmpty
            ? double.tryParse(_longitudeController.text.trim())
            : null,
        allowedRadius: _enableGeofence && _radiusController.text.isNotEmpty
            ? double.tryParse(_radiusController.text.trim())
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.employeeAdded), backgroundColor: AppTheme.accentGreen),
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
      appBar: AppBar(title: Text(S.addEmployeeTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Reference image capture
              _buildImageCapture(),
              const SizedBox(height: 16),
              _buildField(_nameController, S.fullName, Icons.person_outline, validator: (v) => v!.isEmpty ? S.required : null),
              const SizedBox(height: 12),
              _buildField(_emailController, S.email, Icons.email_outlined, keyboardType: TextInputType.emailAddress, validator: (v) {
                if (v == null || v.isEmpty) return S.required;
                if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$').hasMatch(v)) return S.invalidEmail;
                return null;
              }),
              SizedBox(height: 12),
              // Password field with eye icon
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                validator: (v) => (v == null || v.isEmpty) ? S.passwordRequired : null,
                style: TextStyle(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText: S.password,
                  prefixIcon: Icon(Icons.lock_outline, color: context.colors.textSecondary),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: context.colors.textSecondary),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Department dropdown
              _dropdownField(S.department, _selectedDepartment, {
                'HR': 'HR',
                'sales': S.sales,
                'accountant': S.accountant,
                'warehouse': S.warehouse,
                'IT': S.itDepartment,
                'Management': S.management,
                'other': S.other,
              }, (v) => setState(() => _selectedDepartment = v!)),
              const SizedBox(height: 12),
              _buildField(_positionController, S.positionOptional, Icons.badge_outlined),
              const SizedBox(height: 12),
              _buildField(_phoneController, S.phone, Icons.phone_outlined, keyboardType: TextInputType.phone, validator: (v) {
                if (v == null || v.isEmpty) return S.phoneRequired;
                return null;
              }),
              const SizedBox(height: 16),
              // Role dropdown — hierarchy enforced
              Builder(builder: (ctx) {
                final myRole = ctx.read<AuthProvider>().employee?.role ?? UserRole.employee;
                final Map<String, String> roleOptions;
                if (myRole == UserRole.superAdmin) {
                  roleOptions = {'employee': S.employee, 'hr': S.hrManagerRole, 'branchAdmin': S.branchAdminRole};
                } else if (myRole == UserRole.branchAdmin) {
                  roleOptions = {'employee': S.employee, 'hr': S.hrManagerRole};
                } else {
                  roleOptions = {'employee': S.employee};
                }
                // Reset if current selection not in allowed options
                if (!roleOptions.containsKey(_selectedRole)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedRole = roleOptions.keys.first);
                  });
                }
                return _dropdownField(S.role, roleOptions.containsKey(_selectedRole) ? _selectedRole : roleOptions.keys.first, roleOptions, (v) => setState(() => _selectedRole = v!));
              }),
              const SizedBox(height: 12),
              // Branch selection
              Builder(builder: (ctx) {
                final myRole = ctx.read<AuthProvider>().employee?.role ?? UserRole.employee;
                if (myRole == UserRole.superAdmin) {
                  if (_loadingBranches) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (_branches.isEmpty) {
                    return Text(S.noBranchesAvailable, style: TextStyle(color: context.colors.textSecondary));
                  }
                  final branchOptions = <String, String>{
                    for (final b in _branches) b.id: b.name,
                  };
                  return _dropdownField(
                    S.branch,
                    _selectedBranchId != null && branchOptions.containsKey(_selectedBranchId) ? _selectedBranchId! : branchOptions.keys.first,
                    branchOptions,
                    (v) => setState(() {
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
              const SizedBox(height: 12),
              if (_selectedRole == 'employee')
                _dropdownField(S.employeeTypeLabel, _selectedType, {
                  'general': S.general,
                  'sales': S.sales,
                  'accountant': S.accountant,
                  'warehouse': S.warehouse,
                }, (v) => setState(() => _selectedType = v!)),
              const SizedBox(height: 16),
              // Geofence section
              _buildGeofenceSection(),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(S.addEmployeeTitle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageCapture() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.referenceImageLabel,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        GestureDetector(
          onTap: _captureReferenceImage,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.surfaceBorder),
            ),
            child: _referenceImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_referenceImage!, fit: BoxFit.cover),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.refresh, color: Colors.white, size: 16),
                                const SizedBox(width: 4),
                                Text(S.retake, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, color: AppTheme.primaryBlue, size: 48),
                        SizedBox(height: 8),
                        Text(S.tapToCaptureFace, style: TextStyle(color: context.colors.textSecondary)),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
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

  Widget _buildGeofenceSection() {
    return Container(
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
                child: Text(S.locationGeofence, style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600)),
              ),
              Switch(
                value: _enableGeofence,
                activeColor: AppTheme.primaryBlue,
                onChanged: (v) => setState(() => _enableGeofence = v),
              ),
            ],
          ),
          if (_enableGeofence) ...[
            SizedBox(height: 8),
            Text(
              S.geofenceDescription,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildField(_latitudeController, S.latitude, Icons.my_location,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: _enableGeofence ? (v) => v!.isEmpty ? S.required : null : null)),
                const SizedBox(width: 12),
                Expanded(child: _buildField(_longitudeController, S.longitude, Icons.my_location,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: _enableGeofence ? (v) => v!.isEmpty ? S.required : null : null)),
              ],
            ),
            const SizedBox(height: 12),
            _buildField(_radiusController, S.radiusMeters, Icons.radar,
                keyboardType: TextInputType.number,
                validator: _enableGeofence ? (v) => v!.isEmpty ? S.required : null : null),
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
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: TextStyle(color: context.colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: context.colors.textSecondary),
      ),
    );
  }

  Widget _dropdownField(String label, String value, Map<String, String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: context.colors.cardBgLighter,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: context.colors.cardBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.colors.surfaceBorder)),
      ),
      style: TextStyle(color: context.colors.textPrimary),
      items: items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: onChanged,
    );
  }
}

// Standalone camera screen for capturing the reference face photo
class _ReferenceCaptureScreen extends StatefulWidget {
  final CameraDescription camera;
  const _ReferenceCaptureScreen({required this.camera});

  @override
  State<_ReferenceCaptureScreen> createState() => _ReferenceCaptureScreenState();
}

class _ReferenceCaptureScreenState extends State<_ReferenceCaptureScreen> {
  CameraController? _controller;
  bool _isTaking = false;
  File? _preview;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(widget.camera, ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_isTaking || _controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTaking = true);
    try {
      final xFile = await _controller!.takePicture();
      setState(() => _preview = File(xFile.path));
    } finally {
      setState(() => _isTaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_preview != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    Text(S.preview, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.file(_preview!, fit: BoxFit.cover)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: Text(S.retake, style: TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => setState(() => _preview = null),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: Text(S.usePhoto),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: () => Navigator.pop(context, _preview),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: CameraPreview(_controller!)),
            // Face guide
            Center(
              child: Container(
                width: 260, height: 340,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                  borderRadius: BorderRadius.circular(130),
                ),
              ),
            ),
            Positioned(
              top: 60, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Position face in frame', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            Positioned(
              top: 8, left: 8,
              child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context)),
            ),
            Positioned(
              bottom: 50, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _capture,
                  child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: const Icon(Icons.camera_alt, color: Colors.black87, size: 30),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
