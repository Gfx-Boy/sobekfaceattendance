import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_session.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _employeeIdKey = 'employee_id';
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _accessTokenExpiryMsKey = 'access_token_expiry_ms';
  static const _refreshSkew = Duration(minutes: 2);
  static const _minRefreshDelay = Duration(seconds: 30);
  static const _retryRefreshDelay = Duration(minutes: 1);

  final ApiService _apiService;

  Employee? _employee;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessTokenExpiry;
  Timer? _refreshTimer;
  bool _isLoading = false;
  String? _error;

  AuthProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Employee? get employee => _employee;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _employee != null;
  String? get error => _error;
  bool get hasRefreshToken =>
      _refreshToken != null && _refreshToken!.isNotEmpty;
  DateTime? get accessTokenExpiry => _accessTokenExpiry;

  Future<void> checkSavedLogin() async {
    final prefs = await SharedPreferences.getInstance();

    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    final expiryMs = prefs.getInt(_accessTokenExpiryMsKey);
    _accessTokenExpiry =
        expiryMs != null ? DateTime.fromMillisecondsSinceEpoch(expiryMs) : null;
    _apiService.setAccessToken(_accessToken);

    final employeeId = prefs.getString(_employeeIdKey);
    if (employeeId == null && (_refreshToken == null || _refreshToken!.isEmpty)) {
      return;
    }

    try {
      _isLoading = true;
      notifyListeners();

      if (_refreshToken != null && _refreshToken!.isNotEmpty) {
        final session = await _apiService.refreshLoginToken(_refreshToken!);
        await _persistSession(session, prefs);
        _error = null;
        return;
      }

      if (employeeId != null) {
        _employee = await _apiService.getEmployee(employeeId);
        _error = null;
      }
    } catch (e) {
      _error = e.toString();
      await _clearSavedSession(prefs);
      _employee = null;
      _apiService.setAccessToken(null);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, {String? password}) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      final session =
          await _apiService.loginEmployee(email, password: password);
      await _persistSession(session, prefs);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> refreshSession({bool silent = false}) async {
    final prefs = await SharedPreferences.getInstance();
    _refreshToken ??= prefs.getString(_refreshTokenKey);

    if (_refreshToken == null || _refreshToken!.isEmpty) {
      _error = 'No refresh token found. Please log in again.';
      if (!silent) notifyListeners();
      return false;
    }

    try {
      if (!silent) {
        _isLoading = true;
        notifyListeners();
      }

      final session = await _apiService.refreshLoginToken(_refreshToken!);
      await _persistSession(session, prefs);
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      if (!silent) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    // Unregister push token
    try {
      await NotificationService().unregister();
    } catch (e) {
      debugPrint('Notification unregister failed: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await _clearSavedSession(prefs);
    _cancelAutoRefresh();
    _employee = null;
    _accessToken = null;
    _refreshToken = null;
    _accessTokenExpiry = null;
    _error = null;
    _apiService.setAccessToken(null);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Update only the profile image URL on the current employee and notify listeners.
  void updateProfileImageUrl(String url) {
    if (_employee == null) return;
    _employee = Employee(
      id: _employee!.id,
      name: _employee!.name,
      email: _employee!.email,
      department: _employee!.department,
      referenceImageUrl: _employee!.referenceImageUrl,
      role: _employee!.role,
      employeeType: _employee!.employeeType,
      branchId: _employee!.branchId,
      branchName: _employee!.branchName,
      address: _employee!.address,
      phone: _employee!.phone,
      position: _employee!.position,
      lastOnline: _employee!.lastOnline,
      profileImageUrl: url,
      allowedLatitude: _employee!.allowedLatitude,
      allowedLongitude: _employee!.allowedLongitude,
      allowedRadius: _employee!.allowedRadius,
      isOnHold: _employee!.isOnHold,
    );
    notifyListeners();
  }

  Future<void> _persistSession(
    AuthSession session,
    SharedPreferences prefs,
  ) async {
    _employee = session.employee;
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;

    if (session.expiresInSeconds != null) {
      _accessTokenExpiry =
          DateTime.now().add(Duration(seconds: session.expiresInSeconds!));
    } else {
      _accessTokenExpiry = null;
    }

    _apiService.setAccessToken(_accessToken);

    await prefs.setString(_employeeIdKey, _employee!.id);

    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await prefs.setString(_accessTokenKey, _accessToken!);
    } else {
      await prefs.remove(_accessTokenKey);
    }

    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
    } else {
      await prefs.remove(_refreshTokenKey);
    }

    if (_accessTokenExpiry != null) {
      await prefs.setInt(
          _accessTokenExpiryMsKey, _accessTokenExpiry!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(_accessTokenExpiryMsKey);
    }

    _scheduleAutoRefresh();

    // Register for push notifications
    try {
      await NotificationService().init(_employee!.id);
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  Future<void> _clearSavedSession(SharedPreferences prefs) async {
    await prefs.remove(_employeeIdKey);
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_accessTokenExpiryMsKey);
  }

  void _cancelAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _scheduleAutoRefresh() {
    _cancelAutoRefresh();

    if (_refreshToken == null || _refreshToken!.isEmpty) return;
    if (_accessTokenExpiry == null) return;

    var delay = _accessTokenExpiry!
        .difference(DateTime.now()) -
        _refreshSkew;
    if (delay < _minRefreshDelay) {
      delay = _minRefreshDelay;
    }

    _refreshTimer = Timer(delay, () async {
      final ok = await refreshSession(silent: true);
      if (!ok && _refreshToken != null && _refreshToken!.isNotEmpty) {
        _refreshTimer = Timer(_retryRefreshDelay, () {
          refreshSession(silent: true);
        });
      }
    });
  }
}
