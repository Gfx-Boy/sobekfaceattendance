import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  /// Global navigator key so FCM taps (which arrive outside any widget's
  /// [BuildContext]) can still route to the relevant screen (#17).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentEmployeeId;

  Future<void> init(String employeeId) async {
    _currentEmployeeId = employeeId;

    // Request permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _registerToken();
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((_) => _registerToken());

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background tap (app was in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // Handle initial message (app was terminated)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageTap(initialMessage);
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && _currentEmployeeId != null) {
        await ApiService().registerFcmToken(_currentEmployeeId!, token);
      }
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM foreground: ${message.notification?.title} - ${message.notification?.body}');
    // The notification will be shown automatically by the system on Android
    // For custom handling, you can use flutter_local_notifications
  }

  void _handleMessageTap(RemoteMessage message) {
    debugPrint('FCM tap: ${message.data}');
    final route = _routeForData(message.data);
    if (route == null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushNamed(route);
  }

  /// Maps the data payload of a push notification to an in-app route. The
  /// backend sends either an explicit `route` or a snake_case `type` (the
  /// same strings AppNotification._parseType recognises).
  String? _routeForData(Map<String, dynamic> data) {
    final explicit = data['route']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    switch (data['type']?.toString()) {
      case 'task_assigned':
      case 'task_status':
        return '/tasks';
      case 'request_approved':
      case 'request_review':
      case 'request_rejected':
        return '/my-requests';
      case 'new_request':
        return '/manage-requests';
      case 'payslip_created':
        return '/payslips';
      case 'appraisal_started':
      case 'appraisal_submitted':
        return '/appraisals';
      default:
        return '/notifications';
    }
  }

  Future<void> unregister() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && _currentEmployeeId != null) {
        await ApiService().unregisterFcmToken(_currentEmployeeId!, token);
      }
    } catch (e) {
      debugPrint('FCM token unregistration failed: $e');
    }
    _currentEmployeeId = null;
  }
}

// Top-level handler for background messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background: ${message.notification?.title}');
}
