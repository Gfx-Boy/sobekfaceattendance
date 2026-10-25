import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace_models.dart';
import '../services/workspace_api_service.dart';

/// Holds the employee's session on the web SaaS and the data the mirrored
/// screens show: messenger, CRM and shifts (review points 12, 18, 20, 25).
///
/// Deliberately independent of [AuthProvider]: if the web side is unreachable,
/// misconfigured, or the employee has no account there yet, attendance carries
/// on exactly as before and these screens simply report why they are empty.
class WorkspaceProvider extends ChangeNotifier {
  static const _tokenKey = 'workspace_token';

  final WorkspaceApiService _api;

  WorkspaceProvider({WorkspaceApiService? api})
      : _api = api ?? WorkspaceApiService();

  bool _isLinking = false;
  String? _linkError;

  bool get isLinked => WorkspaceApiService.hasSession;
  bool get isLinking => _isLinking;

  /// Why the workspace is unavailable, if it is. Shown on the feature screens
  /// instead of a misleading empty state.
  String? get linkError => _linkError;

  // --- messenger -------------------------------------------------------------
  List<WorkspaceContact> _contacts = const [];
  List<WorkspaceContact> get contacts => _contacts;
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  // --- crm -------------------------------------------------------------------
  List<WorkspaceStage<WorkspaceDeal>> _deals = const [];
  List<WorkspaceStage<WorkspaceDeal>> get deals => _deals;
  List<WorkspaceStage<WorkspaceLead>> _leads = const [];
  List<WorkspaceStage<WorkspaceLead>> get leads => _leads;

  // --- shifts ----------------------------------------------------------------
  List<WorkspaceShift> _shifts = const [];
  List<WorkspaceShift> get shifts => _shifts;

  /// Restores a previously linked session. Called on start-up.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token != null && token.isNotEmpty) {
      WorkspaceApiService.setToken(token);
      notifyListeners();
    }
  }

  /// Links this employee to the web app using the credentials they just signed
  /// in with. Their password hash was migrated across, so the same password
  /// works on both sides.
  ///
  /// Only the returned token is stored - never the password. Failure is
  /// swallowed into [linkError]: signing in to attendance must succeed even
  /// when the web app is down or the employee was never imported.
  Future<bool> link(String email, String password) async {
    _isLinking = true;
    _linkError = null;
    notifyListeners();

    try {
      final token = await _api.login(email, password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      _linkError = null;
      return true;
    } catch (e) {
      _linkError = e.toString();
      if (kDebugMode) {
        debugPrint('Workspace link failed: $e');
      }
      return false;
    } finally {
      _isLinking = false;
      notifyListeners();
    }
  }

  Future<void> unlink() async {
    await _api.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _contacts = const [];
    _deals = const [];
    _leads = const [];
    _shifts = const [];
    _unreadCount = 0;
    _linkError = null;
    notifyListeners();
  }

  /// Runs a load, recording a readable reason on failure rather than leaving
  /// the screen looking empty. Returns null when it failed.
  Future<T?> _guard<T>(Future<T> Function() fn) async {
    if (!isLinked) {
      // Keep whatever link() reported. Overwriting it with the generic
      // 'not-linked' threw away the only useful part - the server's own
      // reason, e.g. "Staff members are the only ones allowed to log in" -
      // and left every failure looking like a missing account.
      _linkError ??= 'not-linked';
      notifyListeners();
      return null;
    }
    try {
      final result = await fn();
      _linkError = null;
      return result;
    } catch (e) {
      _linkError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> loadContacts() async {
    final result = await _guard(() => _api.getContacts());
    if (result != null) {
      _contacts = result;
      _unreadCount = result.fold(0, (sum, c) => sum + c.unreadCount);
    }
    notifyListeners();
  }

  Future<List<WorkspaceMessage>> loadConversation(int userId) async {
    final result = await _guard(() => _api.getConversation(userId));
    return result ?? const [];
  }

  Future<WorkspaceMessage?> sendMessage(int toId, String body) async {
    return _guard(() => _api.sendMessage(toId, body));
  }

  Future<void> refreshUnreadCount() async {
    final result = await _guard(() => _api.getUnreadCount());
    if (result != null) {
      _unreadCount = result;
      notifyListeners();
    }
  }

  Future<void> loadDeals() async {
    final result = await _guard(() => _api.getDealBoard());
    if (result != null) _deals = result;
    notifyListeners();
  }

  Future<void> loadLeads() async {
    final result = await _guard(() => _api.getLeadBoard());
    if (result != null) _leads = result;
    notifyListeners();
  }

  Future<void> loadShifts() async {
    final result = await _guard(() => _api.getShifts());
    if (result != null) _shifts = result;
    notifyListeners();
  }
}
