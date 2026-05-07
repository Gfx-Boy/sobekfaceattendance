import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/app_config.dart';
import '../models/attendance_record.dart';
import '../models/auth_session.dart';
import '../models/employee.dart';
import '../models/verification_result.dart';
import '../models/request.dart';
import '../models/notification_model.dart';
import '../models/task.dart';
import '../models/branch.dart';
import '../models/appraisal.dart';
import '../models/appraisal_cycle.dart';
import '../models/payslip.dart';
import '../models/dashboard_stats.dart';
import '../models/system_settings.dart';

class ApiService {
  final String baseUrl;
  final http.Client _client;
  String? _accessToken;

  /// Shared across all instances so that screens calling ApiService() directly
  /// still send the Authorization header after AuthProvider has logged in.
  static String? _sharedToken;

  /// Invoked when the backend reports the active session has been
  /// invalidated (e.g. the account logged in on another device).
  /// Consumers (like [AuthProvider]) should register a handler that
  /// signs the user out and routes back to the login screen.
  static void Function()? onSessionInvalidated;
  static const _sessionInvalidatedMarker = 'another device';

  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _client = _SessionAwareClient(client ?? http.Client());

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = _accessToken ?? _sharedToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  void setAccessToken(String? token) {
    _accessToken = token;
    _sharedToken = token;
  }

  /// Wraps any network call and converts low-level exceptions into friendly
  /// [ApiException] messages.
  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException catch (e) {
      if (e.message.contains(_sessionInvalidatedMarker)) {
        onSessionInvalidated?.call();
      }
      rethrow;
    } on TimeoutException {
      throw ApiException(
          'Request timed out. Check your internet connection and make sure the server is running.');
    } on SocketException catch (e) {
      throw ApiException(
          'Cannot reach server.\n\nURL: $baseUrl\nDetails: ${e.message}\n\nMake sure:\n• Your phone has internet access\n• The tunnel is running on your Mac');
    } on HandshakeException {
      throw ApiException('SSL error connecting to server.');
    } on HttpException catch (e) {
      throw ApiException('HTTP error: ${e.message}');
    } catch (e) {
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Pings the health endpoint. Returns null on success, error string on failure.
  Future<String?> checkConnection() async {
    try {
      final response = await _client
          .get(Uri.parse('${baseUrl.replaceAll('/api', '')}/api/health'),
              headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return null;
      return 'Server responded with status ${response.statusCode}';
    } on TimeoutException {
      return 'Connection timed out (8s). Server URL: $baseUrl';
    } on SocketException catch (e) {
      return 'Cannot reach server.\nURL: $baseUrl\nError: ${e.message}';
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  // ---------- Employee ----------

  Future<Employee> getEmployee(String employeeId) => _call(() async {
        final response = await _client
            .get(
              Uri.parse('$baseUrl/employees/$employeeId'),
              headers: _headers,
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200) {
          return Employee.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Employee not found (${response.statusCode})');
      });

  Future<AuthSession> loginEmployee(String email, {String? password}) => _call(() async {
        final bodyMap = <String, dynamic>{'email': email};
        if (password != null && password.isNotEmpty) {
          bodyMap['password'] = password;
        }
        final response = await _client
            .post(
              Uri.parse('$baseUrl/employees/login'),
              headers: _headers,
              body: json.encode(bodyMap),
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200) {
          final body = json.decode(response.body) as Map<String, dynamic>;
          final session = AuthSession.fromJson(body);
          setAccessToken(session.accessToken);
          return session;
        }
        if (response.statusCode == 404) {
          throw ApiException(
              'No account found for "$email". Contact your administrator.');
        }
        // Extract the error message from the backend body
        String detail = response.body;
        try {
          final body = json.decode(response.body) as Map<String, dynamic>;
          detail = body['error']?.toString() ?? response.body;
        } catch (_) {}
        throw ApiException('Login error (${response.statusCode}): $detail');
      });

  Future<AuthSession> refreshLoginToken(String refreshToken) => _call(() async {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/employees/refresh-token'),
              headers: _headers,
              body: json.encode({'refresh_token': refreshToken}),
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200) {
          final body = json.decode(response.body) as Map<String, dynamic>;
          final session = AuthSession.fromJson(body);
          setAccessToken(session.accessToken);
          return session;
        }

        String detail = response.body;
        try {
          final body = json.decode(response.body) as Map<String, dynamic>;
          detail = body['error']?.toString() ?? response.body;
        } catch (_) {}

        throw ApiException(
            'Token refresh failed (${response.statusCode}): $detail');
      });

  // ---------- Attendance ----------

  Future<VerificationResult> markAttendance({
    required String employeeId,
    required File imageFile,
    required double latitude,
    required double longitude,
    String type = 'sign_in',
  }) =>
      _call(() async {
        final uri = Uri.parse('$baseUrl/attendance/mark');

        final request = http.MultipartRequest('POST', uri)
          ..fields['employee_id'] = employeeId
          ..fields['latitude'] = latitude.toString()
          ..fields['longitude'] = longitude.toString()
          ..fields['type'] = type
          ..files.add(
            await http.MultipartFile.fromPath(
              'image',
              imageFile.path,
              contentType: MediaType('image', 'jpeg'),
            ),
          );

        final streamedResponse =
            await _client.send(request).timeout(AppConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          return VerificationResult.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException(
            'Attendance failed (${response.statusCode}): ${response.body}');
      });

  Future<List<AttendanceRecord>> getAttendanceHistory(
          String employeeId) =>
      _call(() async {
        final response = await _client
            .get(
              Uri.parse('$baseUrl/attendance/history/$employeeId'),
              headers: _headers,
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200) {
          final List<dynamic> data =
              json.decode(response.body) as List<dynamic>;
          return data
              .map((item) =>
                  AttendanceRecord.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        throw ApiException(
            'Failed to load history (${response.statusCode})');
      });

  Future<void> setDayStatus({
    required String employeeId,
    required String date,
    required String status,
  }) =>
      _call(() async {
        final response = await _client
            .put(
              Uri.parse('$baseUrl/attendance/day-status'),
              headers: _headers,
              body: json.encode({
                'employee_id': employeeId,
                'date': date,
                'status': status,
              }),
            )
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to set day status (${response.statusCode})');
        }
      });

  // ---------- Employee Registration ----------

  Future<Employee> registerEmployee({
    required String name,
    required String email,
    required String department,
    required File referenceImage,
  }) =>
      _call(() async {
        final uri = Uri.parse('$baseUrl/employees/register');

        final request = http.MultipartRequest('POST', uri)
          ..fields['name'] = name
          ..fields['email'] = email
          ..fields['department'] = department
          ..files.add(
            await http.MultipartFile.fromPath(
                'reference_image', referenceImage.path),
          );

        final streamedResponse =
            await _client.send(request).timeout(AppConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          return Employee.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException(
            'Registration failed (${response.statusCode}): ${response.body}');
      });

  // ---------- Requests ----------

  Future<AppRequest> createRequest({
    required String employeeId,
    required String employeeName,
    required String category,
    required String type,
    required String title,
    required String description,
    String? startDate,
    String? endDate,
    String? employeeEmail,
    String? branchName,
    Map<String, dynamic>? extraFields,
  }) =>
      _call(() async {
        final body = <String, dynamic>{
          'employee_id': employeeId,
          'employee_name': employeeName,
          'employee_email': employeeEmail ?? '',
          'branch_name': branchName ?? '',
          'category': category,
          'type': type,
          'title': title,
          'description': description,
          'start_date': startDate,
          'end_date': endDate,
          if (extraFields != null) ...extraFields,
        };

        final response = await _client
            .post(
              Uri.parse('$baseUrl/requests'),
              headers: _headers,
              body: json.encode(body),
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200 || response.statusCode == 201) {
          return AppRequest.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException(
            'Failed to create request (${response.statusCode})');
      });

  Future<List<AppRequest>> getRequests(String employeeId) =>
      _call(() async {
        final response = await _client
            .get(
              Uri.parse('$baseUrl/requests/employee/$employeeId'),
              headers: _headers,
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200) {
          final List<dynamic> data =
              json.decode(response.body) as List<dynamic>;
          return data
              .map((item) =>
                  AppRequest.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        throw ApiException(
            'Failed to load requests (${response.statusCode})');
      });

  // ---------- Notifications ----------

  Future<List<AppNotification>> getNotifications(String employeeId) =>
      _call(() async {
        final response = await _client
            .get(
              Uri.parse('$baseUrl/notifications/$employeeId'),
              headers: _headers,
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode == 200) {
          final List<dynamic> data =
              json.decode(response.body) as List<dynamic>;
          return data
              .map((item) =>
                  AppNotification.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        throw ApiException(
            'Failed to load notifications (${response.statusCode})');
      });

  Future<void> markNotificationRead(
          String employeeId, String notificationId) =>
      _call(() async {
        final response = await _client
            .patch(
              Uri.parse(
                  '$baseUrl/notifications/$employeeId/$notificationId/read'),
              headers: _headers,
            )
            .timeout(AppConfig.apiTimeout);

        if (response.statusCode != 200) {
          throw ApiException(
              'Failed to mark notification read (${response.statusCode})');
        }
      });

  // ---------- Tasks ----------

  Future<List<Task>> getTasks(String employeeId) => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/tasks/employee/$employeeId'),
                headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Task.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load tasks (${response.statusCode})');
      });

  Future<List<Task>> getAllTasks() => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/tasks/all'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Task.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load all tasks (${response.statusCode})');
      });

  Future<List<Task>> getAssignedTasks(String employeeId) => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/tasks/assigned-by/$employeeId'),
                headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Task.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load tasks (${response.statusCode})');
      });

  Future<Task> createTask({
    required String title,
    required String description,
    required String assignedTo,
    required String assignedBy,
    required String dueDate,
    String? assignedToName,
    String? assignedByName,
    List<String>? attachments,
    String? taskType,
    String? itemCode,
  }) =>
      _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/tasks'),
                headers: _headers,
                body: json.encode({
                  'title': title,
                  'description': description,
                  'assigned_to': assignedTo,
                  'assigned_by': assignedBy,
                  'due_date': dueDate,
                  if (assignedToName != null) 'assigned_to_name': assignedToName,
                  if (assignedByName != null) 'assigned_by_name': assignedByName,
                  if (attachments != null) 'attachments': attachments,
                  if (taskType != null) 'task_type': taskType,
                  if (itemCode != null) 'item_code': itemCode,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return Task.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to create task (${response.statusCode})');
      });

  Future<Task> updateTaskStatus(String taskId, String status,
          {String? comment, List<String>? attachments, int? countedTotal}) =>
      _call(() async {
        final body = <String, dynamic>{'status': status};
        if (comment != null && comment.isNotEmpty) body['comment'] = comment;
        if (attachments != null && attachments.isNotEmpty) {
          body['attachments'] = attachments;
        }
        if (countedTotal != null) body['counted_total'] = countedTotal;
        final response = await _client
            .patch(Uri.parse('$baseUrl/tasks/$taskId'),
                headers: _headers,
                body: json.encode(body))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          return Task.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to update task (${response.statusCode})');
      });

  /// Self password reset for an employee whose password_reset_pending flag is
  /// set (i.e. their password-change request has been approved).
  Future<void> selfChangePassword({
    required String employeeId,
    required String newPassword,
  }) =>
      _call(() async {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/employees/$employeeId/self-password'),
              headers: _headers,
              body: json.encode({'new_password': newPassword}),
            )
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) return;
        final msg = _tryExtractError(response.body) ??
            'Failed to update password (${response.statusCode})';
        throw ApiException(msg);
      });

  /// Uploads a file as a task attachment. Returns the descriptor map
  /// with `url`, `name`, `size`, etc. as returned by the server.
  Future<Map<String, dynamic>> uploadTaskAttachment(File file) => _call(() async {
        final uri = Uri.parse('$baseUrl/tasks/upload');
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(Map.of(_headers)..remove('Content-Type'))
          ..files.add(await http.MultipartFile.fromPath('file', file.path));
        final streamed =
            await _client.send(request).timeout(AppConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
        throw ApiException(
            'Failed to upload attachment (${response.statusCode})');
      });

  // ---------- Branches ----------

  Future<List<Branch>> getBranches() => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/branches'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Branch.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load branches (${response.statusCode})');
      });

  Future<Branch> createBranch({
    required String name,
    String? address,
    String? adminId,
    String? adminName,
    String status = 'work',
    String? validityStart,
    String? validityEnd,
    String workingHoursStart = '09:00',
    String workingHoursEnd = '18:00',
    int breakDurationMinutes = 60,
    List<String> workingDays = Branch.defaultWorkingDays,
    double deductionLate = 0,
    double deductionEarlyOut = 0,
    double deductionAbsent = 0,
  }) =>
      _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/branches'),
                headers: _headers,
                body: json.encode({
                  'name': name,
                  'address': address,
                  'admin_id': adminId,
                  'admin_name': adminName,
                  'status': status,
                  'validity_start': validityStart,
                  'validity_end': validityEnd,
                  'working_hours_start': workingHoursStart,
                  'working_hours_end': workingHoursEnd,
                  'break_duration_minutes': breakDurationMinutes,
                  'working_days': workingDays,
                  'deduction_late': deductionLate,
                  'deduction_early_out': deductionEarlyOut,
                  'deduction_absent': deductionAbsent,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return Branch.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        if (response.statusCode == 409) {
          throw ApiException('A branch with this name already exists');
        }
        throw ApiException('Failed to create branch (${response.statusCode})');
      });

  Future<Branch> updateBranch(String id, Map<String, dynamic> updates) =>
      _call(() async {
        final response = await _client
            .put(Uri.parse('$baseUrl/branches/$id'),
                headers: _headers,
                body: json.encode(updates))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          return Branch.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        if (response.statusCode == 409) {
          throw ApiException('A branch with this name already exists');
        }
        throw ApiException('Failed to update branch (${response.statusCode})');
      });

  /// Apply a day status to every active employee in a branch for the given date.
  /// Used by Branch Admin to mark a holiday/vacation across the whole branch.
  Future<int> setBranchDayStatus({
    required String branchId,
    required String date,
    required String status,
    String? appliedBy,
  }) =>
      _call(() async {
        final response = await _client
            .post(
              Uri.parse('$baseUrl/branches/$branchId/day-status'),
              headers: _headers,
              body: json.encode({
                'date': date,
                'status': status,
                'applied_by': appliedBy,
              }),
            )
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final body = json.decode(response.body) as Map<String, dynamic>;
          return (body['employees_updated'] as num?)?.toInt() ?? 0;
        }
        throw ApiException(
            'Failed to apply branch day status (${response.statusCode})');
      });

  Future<void> deleteBranch(String id) => _call(() async {
        final response = await _client
            .delete(Uri.parse('$baseUrl/branches/$id'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to delete branch (${response.statusCode})');
        }
      });

  // ---------- Employees (admin) ----------

  Future<List<Employee>> getAllEmployees({String? branchId}) => _call(() async {
        final uri = branchId != null
            ? Uri.parse('$baseUrl/employees?branch_id=$branchId')
            : Uri.parse('$baseUrl/employees');
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Employee.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load employees (${response.statusCode})');
      });

  Future<Employee> createEmployee({
    required String name,
    required String email,
    required String department,
    required File referenceImage,
    String? password,
    String role = 'employee',
    String employeeType = 'general',
    String? branchId,
    String? branchName,
    String? position,
    String? phone,
    double? allowedLatitude,
    double? allowedLongitude,
    double? allowedRadius,
  }) =>
      _call(() async {
        final uri = Uri.parse('$baseUrl/employees/register');
        final request = http.MultipartRequest('POST', uri)
          ..fields['name'] = name
          ..fields['email'] = email
          ..fields['department'] = department
          ..fields['role'] = role
          ..fields['employee_type'] = employeeType;

        if (password != null && password.isNotEmpty) request.fields['password'] = password;
        if (branchId != null) request.fields['branch_id'] = branchId;
        if (branchName != null) request.fields['branch_name'] = branchName;
        if (position != null && position.isNotEmpty) request.fields['position'] = position;
        if (phone != null && phone.isNotEmpty) request.fields['phone'] = phone;
        if (allowedLatitude != null) request.fields['allowed_latitude'] = allowedLatitude.toString();
        if (allowedLongitude != null) request.fields['allowed_longitude'] = allowedLongitude.toString();
        if (allowedRadius != null) request.fields['allowed_radius'] = allowedRadius.toString();

        request.files.add(await http.MultipartFile.fromPath(
          'reference_image',
          referenceImage.path,
          contentType: MediaType('image', 'jpeg'),
        ));

        final streamedResponse = await _client.send(request).timeout(AppConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200 || response.statusCode == 201) {
          return Employee.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to create employee (${response.statusCode}): ${response.body}');
      });

  Future<Employee> updateEmployee(String id, Map<String, dynamic> updates) => _call(() async {
        final response = await _client
            .put(Uri.parse('$baseUrl/employees/$id'),
                headers: _headers, body: json.encode(updates))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to update employee (${response.statusCode})');
        }
        try {
          final body = json.decode(response.body);
          if (body is Map<String, dynamic>) {
            final empJson = body['employee'] is Map<String, dynamic>
                ? body['employee'] as Map<String, dynamic>
                : body;
            return Employee.fromJson(empJson);
          }
        } catch (_) {}
        // Fallback: re-fetch
        return await getEmployee(id);
      });

  Future<String> uploadProfileImage(String employeeId, File imageFile) => _call(() async {
        final uri = Uri.parse('$baseUrl/employees/$employeeId/profile-image');
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(_headers..remove('Content-Type'))
          ..files.add(await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: MediaType('image', 'jpeg'),
          ));
        final streamedResponse = await _client.send(request).timeout(AppConfig.uploadTimeout);
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode == 200) {
          final body = json.decode(response.body) as Map<String, dynamic>;
          return body['profile_image_url'] as String;
        }
        throw ApiException('Failed to upload profile image (${response.statusCode})');
      });

  Future<void> deleteEmployee(String id) => _call(() async {
        final response = await _client
            .delete(Uri.parse('$baseUrl/employees/$id'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to delete employee (${response.statusCode})');
        }
      });

  // ---------- FCM Notifications ----------

  Future<void> registerFcmToken(String employeeId, String token) => _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/notifications/register-token'),
                headers: _headers,
                body: json.encode({'employee_id': employeeId, 'token': token}))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to register FCM token (${response.statusCode})');
        }
      });

  Future<void> unregisterFcmToken(String employeeId, String token) => _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/notifications/unregister-token'),
                headers: _headers,
                body: json.encode({'employee_id': employeeId, 'token': token}))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to unregister FCM token (${response.statusCode})');
        }
      });

  // ---------- Appraisals ----------

  Future<List<Appraisal>> getAppraisals(String employeeId) => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/appraisals/employee/$employeeId'),
                headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Appraisal.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load appraisals (${response.statusCode})');
      });

  Future<Appraisal> createAppraisal({
    required String employeeId,
    required String employeeName,
    required String evaluatorId,
    required String evaluatorName,
    required String period,
    required Map<String, dynamic> scores,
    required String comments,
    required double overallScore,
  }) =>
      _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/appraisals'),
                headers: _headers,
                body: json.encode({
                  'employee_id': employeeId,
                  'employee_name': employeeName,
                  'evaluator_id': evaluatorId,
                  'evaluator_name': evaluatorName,
                  'period': period,
                  'scores': scores,
                  'comments': comments,
                  'overall_score': overallScore,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return Appraisal.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to create appraisal (${response.statusCode})');
      });

  Future<List<Appraisal>> getAllAppraisals() => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/appraisals/all'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Appraisal.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load all appraisals (${response.statusCode})');
      });

  /// Lists appraisal cycles, optionally filtered by branch.
  Future<List<AppraisalCycle>> getAppraisalCycles({String? branchId}) =>
      _call(() async {
        final uri = branchId != null
            ? Uri.parse('$baseUrl/appraisals/cycles?branch_id=$branchId')
            : Uri.parse('$baseUrl/appraisals/cycles');
        final response =
            await _client.get(uri, headers: _headers).timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data
              .map((e) => AppraisalCycle.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        throw ApiException('Failed to load cycles (${response.statusCode})');
      });

  /// Starts a new appraisal cycle for [branchId].
  Future<AppraisalCycle> startAppraisalCycle({
    required String branchId,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
    required double adminWeight,
    required double hrWeight,
    String? createdBy,
    String? createdByName,
  }) =>
      _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/appraisals/cycles'),
                headers: _headers,
                body: json.encode({
                  'branch_id': branchId,
                  'branch_name': branchName,
                  'start_date': startDate.toIso8601String(),
                  'end_date': endDate.toIso8601String(),
                  'admin_weight': adminWeight,
                  'hr_weight': hrWeight,
                  'created_by': createdBy,
                  'created_by_name': createdByName,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return AppraisalCycle.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
        }
        final msg = _tryExtractError(response.body) ??
            'Failed to start cycle (${response.statusCode})';
        throw ApiException(msg);
      });

  /// Closes an active appraisal cycle.
  Future<AppraisalCycle> closeAppraisalCycle(String cycleId,
          {String? reason}) =>
      _call(() async {
        final response = await _client
            .patch(Uri.parse('$baseUrl/appraisals/cycles/$cycleId/close'),
                headers: _headers,
                body: json.encode({'reason': reason ?? 'manual'}))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          return AppraisalCycle.fromJson(
              json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to close cycle (${response.statusCode})');
      });

  String? _tryExtractError(String body) {
    try {
      final m = json.decode(body);
      if (m is Map && m['error'] is String) return m['error'] as String;
    } catch (_) {}
    return null;
  }

  // ---------- Payslips ----------

  Future<List<Payslip>> getPayslips(String employeeId) => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/payslips/employee/$employeeId'),
                headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Payslip.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load payslips (${response.statusCode})');
      });

  Future<List<Payslip>> getAllPayslips() => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/payslips/all'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => Payslip.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load all payslips (${response.statusCode})');
      });

  Future<Payslip> createPayslip({
    required String employeeId,
    required String employeeName,
    required String period,
    required double basicSalary,
    double bonuses = 0,
    double deductions = 0,
    double overtimePay = 0,
    String? paymentDate,
    String? notes,
  }) =>
      _call(() async {
        final netSalary = basicSalary + bonuses + overtimePay - deductions;
        final response = await _client
            .post(Uri.parse('$baseUrl/payslips'),
                headers: _headers,
                body: json.encode({
                  'employee_id': employeeId,
                  'employee_name': employeeName,
                  'period': period,
                  'basic_salary': basicSalary,
                  'bonuses': bonuses,
                  'deductions': deductions,
                  'overtime_pay': overtimePay,
                  'net_salary': netSalary,
                  'payment_date': paymentDate,
                  'notes': notes,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return Payslip.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to create payslip (${response.statusCode})');
      });

  /// Auto-compute a payslip for [employeeId] in [period] (YYYY-MM).
  /// When [save] is false, returns a preview Map (not persisted).
  /// When true, persists and returns the saved Payslip JSON.
  Future<Map<String, dynamic>> generatePayslip({
    required String employeeId,
    required String period,
    bool save = false,
  }) =>
      _call(() async {
        final response = await _client
            .post(Uri.parse('$baseUrl/payslips/generate'),
                headers: _headers,
                body: json.encode({
                  'employee_id': employeeId,
                  'period': period,
                  'save': save,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
        throw ApiException(
            'Failed to generate payslip (${response.statusCode})');
      });

  // ---------- Dashboard ----------

  Future<DashboardStats> getDashboardStats() => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/dashboard/stats'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          return DashboardStats.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to load stats (${response.statusCode})');
      });

  Future<List<AppRequest>> getAllRequests({String? branchId}) => _call(() async {
        final uri = branchId != null
            ? Uri.parse('$baseUrl/dashboard/all-requests?branch_id=$branchId')
            : Uri.parse('$baseUrl/dashboard/all-requests');
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body) as List<dynamic>;
          return data.map((item) => AppRequest.fromJson(item as Map<String, dynamic>)).toList();
        }
        throw ApiException('Failed to load requests (${response.statusCode})');
      });

  Future<void> reviewRequest(String requestId, String status, {String? comment, String? reviewedBy}) =>
      _call(() async {
        final response = await _client
            .patch(Uri.parse('$baseUrl/requests/$requestId/review'),
                headers: _headers,
                body: json.encode({
                  'status': status,
                  'comment': comment,
                  'reviewed_by': reviewedBy,
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to review request (${response.statusCode})');
        }
      });

  // ---------- Settings ----------

  Future<SystemSettings> getSettings() => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/settings'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          return SystemSettings.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to load settings (${response.statusCode})');
      });

  Future<SystemSettings> updateSettings(Map<String, dynamic> updates) => _call(() async {
        final response = await _client
            .put(Uri.parse('$baseUrl/settings'),
                headers: _headers,
                body: json.encode(updates))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          return SystemSettings.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to update settings (${response.statusCode})');
      });

  // ---------- Today's Status ----------

  Future<TodaySummary> getTodayStatus(String employeeId) => _call(() async {
        final response = await _client
            .get(Uri.parse('$baseUrl/attendance/today/$employeeId'), headers: _headers)
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          return TodaySummary.fromJson(data['summary'] as Map<String, dynamic>);
        }
        throw ApiException('Failed to load today status (${response.statusCode})');
      });

  void dispose() {
    _client.close();
  }
}

/// HTTP client wrapper that inspects every response and, when a 401 status
/// is returned with the "logged in on another device" marker, invokes
/// [ApiService.onSessionInvalidated] so the app can sign the user out.
class _SessionAwareClient extends http.BaseClient {
  _SessionAwareClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      // Peek at the response body without consuming the stream for callers.
      final bodyBytes = await response.stream.toBytes();
      try {
        final decoded = utf8.decode(bodyBytes);
        if (decoded.contains(ApiService._sessionInvalidatedMarker)) {
          ApiService.onSessionInvalidated?.call();
        }
      } catch (_) {/* non-utf8 body, ignore */}
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        response.statusCode,
        contentLength: bodyBytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
