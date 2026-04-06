import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/attendance_record.dart';
import '../models/verification_result.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../services/location_service.dart';

enum AttendanceStep {
  idle,
  initializingCamera,
  cameraReady,
  capturing,
  captured,
  gettingLocation,
  locationReady,
  uploading,
  verifying,
  success,
  failed,
}

class AttendanceProvider extends ChangeNotifier {
  final ApiService _apiService;
  final CameraService _cameraService;
  final LocationService _locationService;

  AttendanceStep _currentStep = AttendanceStep.idle;
  File? _capturedImage;
  Position? _currentPosition;
  VerificationResult? _verificationResult;
  List<AttendanceRecord> _attendanceHistory = [];
  String? _error;
  bool _isLoading = false;
  String _attendanceType = 'sign_in';

  AttendanceProvider({
    ApiService? apiService,
    CameraService? cameraService,
    LocationService? locationService,
  })  : _apiService = apiService ?? ApiService(),
        _cameraService = cameraService ?? CameraService(),
        _locationService = locationService ?? LocationService();

  // Getters
  AttendanceStep get currentStep => _currentStep;
  File? get capturedImage => _capturedImage;
  Position? get currentPosition => _currentPosition;
  VerificationResult? get verificationResult => _verificationResult;
  List<AttendanceRecord> get attendanceHistory => _attendanceHistory;
  String? get error => _error;
  bool get isLoading => _isLoading;
  CameraService get cameraService => _cameraService;
  String get attendanceType => _attendanceType;

  void setAttendanceType(String type) {
    _attendanceType = type;
    notifyListeners();
  }

  String get stepMessage {
    switch (_currentStep) {
      case AttendanceStep.idle:
        return _attendanceType == 'sign_out' ? 'Ready to sign out'
            : _attendanceType == 'break_start' ? 'Ready to start break'
            : _attendanceType == 'break_end' ? 'Ready to end break'
            : 'Ready to sign in';
      case AttendanceStep.initializingCamera:
        return 'Initializing camera...';
      case AttendanceStep.cameraReady:
        return 'Position your face in the frame';
      case AttendanceStep.capturing:
        return 'Capturing image...';
      case AttendanceStep.captured:
        return 'Image captured successfully';
      case AttendanceStep.gettingLocation:
        return 'Getting your location...';
      case AttendanceStep.locationReady:
        return 'Location acquired';
      case AttendanceStep.uploading:
        return 'Uploading image for verification...';
      case AttendanceStep.verifying:
        return 'Verifying identity...';
      case AttendanceStep.success:
        return _attendanceType == 'sign_out' ? 'Signed out successfully!'
            : _attendanceType == 'break_start' ? 'Break started!'
            : _attendanceType == 'break_end' ? 'Break ended!'
            : 'Signed in successfully!';
      case AttendanceStep.failed:
        return _error ?? 'Verification failed';
    }
  }

  // ---------- Camera ----------

  Future<void> initializeCamera() async {
    try {
      _currentStep = AttendanceStep.initializingCamera;
      _error = null;
      notifyListeners();

      await _cameraService.initialize();

      _currentStep = AttendanceStep.cameraReady;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _currentStep = AttendanceStep.failed;
      notifyListeners();
    }
  }

  Future<void> captureImage() async {
    try {
      _currentStep = AttendanceStep.capturing;
      notifyListeners();

      _capturedImage = await _cameraService.captureImage();

      _currentStep = AttendanceStep.captured;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _currentStep = AttendanceStep.failed;
      notifyListeners();
    }
  }

  LocationServiceException? _locationException;
  LocationServiceException? get locationException => _locationException;

  // ---------- Location ----------

  Future<void> getLocation() async {
    try {
      _currentStep = AttendanceStep.gettingLocation;
      _locationException = null;
      notifyListeners();

      _currentPosition = await _locationService.getCurrentLocation();

      _currentStep = AttendanceStep.locationReady;
      notifyListeners();
    } on LocationServiceException catch (e) {
      _locationException = e;
      _error = e.message;
      _currentStep = AttendanceStep.failed;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _currentStep = AttendanceStep.failed;
      notifyListeners();
    }
  }

  // ---------- Attendance Submission ----------

  Future<void> submitAttendance(String employeeId) async {
    if (_capturedImage == null || _currentPosition == null) {
      _error = 'Image or location not available';
      _currentStep = AttendanceStep.failed;
      notifyListeners();
      return;
    }

    try {
      _currentStep = AttendanceStep.uploading;
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));

      _currentStep = AttendanceStep.verifying;
      notifyListeners();

      _verificationResult = await _apiService.markAttendance(
        employeeId: employeeId,
        imageFile: _capturedImage!,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        type: _attendanceType,
      );

      if (_verificationResult!.isVerified) {
        _currentStep = AttendanceStep.success;
      } else {
        _error = _verificationResult!.message;
        _currentStep = AttendanceStep.failed;
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _currentStep = AttendanceStep.failed;
      notifyListeners();
    }
  }

  // ---------- History ----------

  Future<void> loadAttendanceHistory(String employeeId) async {
    try {
      _isLoading = true;
      notifyListeners();

      _attendanceHistory = await _apiService.getAttendanceHistory(employeeId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------- Reset ----------

  void reset() {
    _currentStep = AttendanceStep.idle;
    _capturedImage = null;
    _currentPosition = null;
    _verificationResult = null;
    _error = null;
    _locationException = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }
}
