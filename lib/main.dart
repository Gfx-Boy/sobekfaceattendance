import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/attendance_provider.dart';
import 'models/employee.dart';
import 'screens/login_screen.dart';
// Register screen removed — only admins can create accounts
import 'screens/main_shell.dart';
import 'screens/camera_screen.dart';
import 'screens/verification_screen.dart';
import 'screens/history_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/employees_screen.dart';
import 'screens/add_employee_screen.dart';
import 'screens/edit_employee_screen.dart';
import 'screens/branches_screen.dart';
import 'screens/manage_requests_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/create_task_screen.dart';
import 'screens/create_request_screen.dart';
import 'screens/appraisals_screen.dart';
import 'screens/create_appraisal_screen.dart';
import 'screens/payslips_screen.dart';
import 'screens/manage_payslips_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    // Firebase not configured yet — skip FCM initialization
    debugPrint('Firebase init skipped: $e');
  }
  runApp(const FaceAttendanceApp());
}

class FaceAttendanceApp extends StatelessWidget {
  const FaceAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, child) {
          // Ensure S static locale is always in sync with provider
          S.setLocale(localeProvider.locale);
          return MaterialApp(
        title: 'Sobek',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.mode,
        locale: localeProvider.locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        debugShowCheckedModeBanner: false,
        initialRoute: '/login',
        routes: {
          '/login': (_) => const LoginScreen(),
          '/main': (_) => const MainShell(),
          '/camera': (_) => const CameraScreen(),
          '/verify': (_) => const VerificationScreen(),
          '/history': (_) => const HistoryScreen(),
          '/notifications': (_) => const NotificationsScreen(),
          '/admin-dashboard': (_) => const AdminDashboardScreen(),
          '/employees': (_) => const EmployeesScreen(),
          '/add-employee': (_) => const AddEmployeeScreen(),
          '/branches': (_) => const BranchesScreen(),
          '/manage-requests': (_) => const ManageRequestsScreen(),
          '/tasks': (_) => const TasksScreen(),
          '/create-task': (_) => const CreateTaskScreen(),
          '/create-request': (_) => const CreateRequestScreen(),
          '/appraisals': (_) => const AppraisalsScreen(),
          '/create-appraisal': (_) => const CreateAppraisalScreen(),
          '/payslips': (_) => const PayslipsScreen(),
          '/manage-payslips': (_) => const ManagePayslipsScreen(),
          '/reports': (_) => const ReportsScreen(),
          '/settings': (_) => const SettingsScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/edit-employee') {
            final employee = settings.arguments as Employee;
            return MaterialPageRoute(
              builder: (_) => EditEmployeeScreen(employee: employee),
            );
          }
          return null;
        },
        );
        },
      ),
    );
  }
}
