import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:face_attendance/providers/auth_provider.dart';
import 'package:face_attendance/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final employee = {
    'id': '7',
    'name': 'Company',
    'email': 'company@test.local',
    'department': 'HR',
    'role': 'branchAdmin',
    'profile_image_url': 'storage/media/logo.png',
    'basic_salary': 1250,
  };
  void saved() => SharedPreferences.setMockInitialValues({
    'employee_id': '7',
    'access_token': 'saved-access',
    'refresh_token': 'saved-refresh',
    'saved_employee_data': jsonEncode(employee),
  });

  test(
    'restart keeps saved session and identity during a server outage',
    () async {
      saved();
      final auth = AuthProvider(
        apiService: ApiService(
          client: MockClient((_) async => http.Response('{}', 503)),
        ),
      );
      await auth.checkSavedLogin();
      expect(auth.isLoggedIn, true);
      expect(auth.employee!.basicSalary, 1250);
      expect(
        (await SharedPreferences.getInstance()).getString('refresh_token'),
        'saved-refresh',
      );
      auth.dispose();
    },
  );

  test('revoked refresh token clears cached identity', () async {
    saved();
    final auth = AuthProvider(
      apiService: ApiService(
        client: MockClient(
          (_) async =>
              http.Response('{"error":"Invalid or expired token"}', 401),
        ),
      ),
    );
    await auth.checkSavedLogin();
    expect(auth.isLoggedIn, false);
    expect(
      (await SharedPreferences.getInstance()).getString('refresh_token'),
      isNull,
    );
    auth.dispose();
  });

  test('cached profile without any session token does not sign in', () async {
    SharedPreferences.setMockInitialValues({
      'employee_id': '7',
      'saved_employee_data': jsonEncode(employee),
    });
    var requests = 0;
    final auth = AuthProvider(
      apiService: ApiService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      ),
    );
    await auth.checkSavedLogin();
    expect(auth.isLoggedIn, false);
    expect(requests, 0);
    auth.dispose();
  });
}
