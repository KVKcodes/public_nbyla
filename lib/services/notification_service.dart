import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final String lambdaEndpoint = 'lamdaEndpoint'
  
  Future<void> initialize() async {
    // Request permission and print result
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('Notification permission status: ${settings.authorizationStatus}');

    // Print FCM token for debugging
    final token = await _messaging.getToken();
    print('FCM Token: $token');

    // Initialize local notifications
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initializationSettings);

    // Get token and store it
    await updateTokenInFirestore();

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  Future<void> updateTokenInFirestore() async {
    final token = await _messaging.getToken();
    final user = FirebaseAuth.instance.currentUser;
    if (token != null && user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': token});
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Show local notification
    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          'Chat Messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> sendNotification(String recipientEmail, String message) async {
    try {
      print('Sending notification to: $recipientEmail');
      print('Message content: $message');
      
      final response = await http.post(
        Uri.parse(lambdaEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'recipientId': recipientEmail,
          'content': message
        }),
      );
      
      print('Lambda response status: ${response.statusCode}');
      print('Lambda response body: ${response.body}');
      
      if (response.statusCode != 200) {
        print('Notification failed: ${response.body}');
      }
    } catch (e) {
      print('Error sending notification: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }
}

// Must be top-level function
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background message
  print('Handling background message: ${message.messageId}');
} 