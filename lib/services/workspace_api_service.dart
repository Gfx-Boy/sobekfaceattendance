import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../models/workspace_models.dart';
import 'api_service.dart' show ApiException;

/// Client for the web SaaS (Laravel + Sanctum).
///
/// Uses the same Laravel backend and database as attendance. This client
/// unwraps the workspace API envelope used by messenger, CRM and shifts.
class WorkspaceApiService {
  final String baseUrl;
  final http.Client _client;

  /// Sanctum personal access token, shared across instances the way
  /// [ApiService] shares its own.
  static String? _token;

  WorkspaceApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.workspaceApiBaseUrl,
        _client = client ?? http.Client();

  static String? get token => _token;

  static bool get hasSession => _token != null && _token!.isNotEmpty;

  static void setToken(String? value) => _token = value;

  static void clearToken() => _token = null;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (hasSession) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  /// Unwraps the API's `{success, message, data}` envelope, turning a failure
  /// into an [ApiException] carrying the server's own message.
  dynamic _unwrap(http.Response response) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      // An HTML error page or a proxy timeout - never surface the raw markup.
      throw ApiException(
        response.statusCode >= 500 ? S.errorServer : S.errorServer,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body['success'] == false) {
        throw ApiException(_message(body));
      }
      return body['data'];
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      // The web session is gone; the caller signs back in rather than
      // showing the employee a bare 401.
      clearToken();
      throw ApiException('${_message(body)} (${response.statusCode})');
    }

    throw ApiException(_message(body));
  }

  String _message(Map<String, dynamic> body) {
    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first is String) return first;
    }
    return S.errorServer;
  }

  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(S.errorNoInternet);
    } on SocketException {
      throw ApiException(S.errorNoInternet);
    } on HandshakeException {
      throw ApiException(S.errorNoInternet);
    } catch (_) {
      throw ApiException(S.errorServer);
    }
  }

  Future<dynamic> _get(String path) => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/$path'), headers: _headers)
            .timeout(AppConfig.workspaceTimeout);
        return _unwrap(response);
      });

  Future<dynamic> _post(String path, Map<String, dynamic> body) =>
      _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/$path'),
                headers: _headers, body: jsonEncode(body))
            .timeout(AppConfig.workspaceTimeout);
        return _unwrap(response);
      });

  List<Map<String, dynamic>> _list(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Signs in to the web app with the employee's existing credentials.
  ///
  /// Their bcrypt hash was migrated across from the attendance backend, so the
  /// password they already use on this phone is the one that works here.
  /// Returns the Sanctum token.
  Future<String> login(String email, String password) async {
    final data = await _post('login', {
      'email': email,
      'password': password,
      // NO 'module' parameter. Sending module=Hrm looked like sensible
      // defence-in-depth, but the web side rejects every type in
      // $not_emp_type for that module - superadmin and company included - so
      // an administrator signing in got "Staff members are the only ones
      // allowed to log in to this application" and no workspace at all. It
      // also fails when the Hrm add-on is not activated for that company.
      //
      // The check was redundant anyway: this call only happens after the user
      // has already authenticated against the attendance backend, and the web
      // side still enforces is_enable_login and the validity period.
    });

    final token = (data is Map && data['token'] is String)
        ? data['token'] as String
        : null;

    if (token == null || token.isEmpty) {
      throw ApiException(S.errorServer);
    }

    setToken(token);
    return token;
  }

  Future<void> logout() async {
    if (!hasSession) return;
    try {
      await _post('logout', const {});
    } catch (_) {
      // Signing out locally matters more than telling the server about it.
    } finally {
      clearToken();
    }
  }

  // ---------------------------------------------------------------------------
  // Messenger - review point 18
  // ---------------------------------------------------------------------------

  Future<List<WorkspaceContact>> getContacts() async {
    final data = await _get('messenger/contacts');
    return _list(data).map(WorkspaceContact.fromJson).toList();
  }

  Future<List<WorkspaceMessage>> getConversation(int userId) async {
    final data = await _get('messenger/conversation/$userId');
    return _list(data).map(WorkspaceMessage.fromJson).toList();
  }

  Future<WorkspaceMessage> sendMessage(int toId, String body) async {
    final data = await _post('messenger/send', {'to_id': toId, 'body': body});
    if (data is Map<String, dynamic>) {
      return WorkspaceMessage.fromJson(data);
    }
    throw ApiException(S.errorServer);
  }

  Future<int> getUnreadCount() async {
    final data = await _get('messenger/unread-count');
    if (data is Map && data['unread_count'] != null) {
      return int.tryParse(data['unread_count'].toString()) ?? 0;
    }
    return 0;
  }

  // ---------------------------------------------------------------------------
  // CRM - review point 20
  // ---------------------------------------------------------------------------

  Future<List<WorkspaceStage<WorkspaceDeal>>> getDealBoard() async {
    final data = await _get('lead/dealboard');
    return _list(data).map((stage) {
      final name = (stage['name'] ?? '').toString();
      final deals = _list(stage['deals'])
          .map((d) => WorkspaceDeal.fromJson(d, stage: name))
          .toList();
      return WorkspaceStage<WorkspaceDeal>(
        id: int.tryParse('${stage['id']}') ?? 0,
        name: name,
        items: deals,
      );
    }).toList();
  }

  Future<List<WorkspaceStage<WorkspaceLead>>> getLeadBoard() async {
    // The leads board is a POST on the web side.
    final data = await _post('lead/leadboard', const {});
    return _list(data).map((stage) {
      final name = (stage['name'] ?? '').toString();
      final leads = _list(stage['leads'])
          .map((l) => WorkspaceLead.fromJson(l, stage: name))
          .toList();
      return WorkspaceStage<WorkspaceLead>(
        id: int.tryParse('${stage['id']}') ?? 0,
        name: name,
        items: leads,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Shifts - review point 25
  // ---------------------------------------------------------------------------

  Future<List<WorkspaceShift>> getShifts() async {
    final data = await _get('hrm/shifts');
    return _list(data).map(WorkspaceShift.fromJson).toList();
  }
}
