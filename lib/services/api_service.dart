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
import '../models/payslip.dart';
import '../models/dashboard_stats.dart';
import '../models/system_settings.dart';

class ApiService {
  final String baseUrl;
  final http.Client _client;
  String? _accessToken;

  ApiService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _client = client ?? http.Client();

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  /// Wraps any network call and converts low-level exceptions into friendly
  /// [ApiException] messages.
  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException {
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
                }))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return Task.fromJson(json.decode(response.body) as Map<String, dynamic>);
        }
        throw ApiException('Failed to create task (${response.statusCode})');
      });

  Future<Task> updateTaskStatus(String taskId, String status, {String? comment}) => _call(() async {
        final body = <String, dynamic>{'status': status};
        if (comment != null && comment.isNotEmpty) body['comment'] = comment;
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

  Future<void> updateEmployee(String id, Map<String, dynamic> updates) => _call(() async {
        final response = await _client
            .put(Uri.parse('$baseUrl/employees/$id'),
                headers: _headers, body: json.encode(updates))
            .timeout(AppConfig.apiTimeout);
        if (response.statusCode != 200) {
          throw ApiException('Failed to update employee (${response.statusCode})');
        }
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

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
