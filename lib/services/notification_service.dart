import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

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
    // Navigate based on message data if needed
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
