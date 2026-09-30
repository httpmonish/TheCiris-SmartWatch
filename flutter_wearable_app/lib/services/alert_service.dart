import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'storage_service.dart';

class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal() {
    _initNotifications();
  }

  final StorageService _storage = StorageService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Telephony _telephony = Telephony.instance;

  bool isAlertActive = false;

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  /// Multi-tier escalation chain:
  /// 1. Trigger local system high-priority notification with alarm sound
  /// 2. Fetch high-precision GPS coordinates via Geolocator
  /// 3. Direct automated SMS dispatch via Telephony to all emergency contacts
  Future<void> triggerEscalationChain({
    required String emergencyReason,
    double? lat,
    double? lng,
  }) async {
    if (isAlertActive) return;
    isAlertActive = true;

    // Step 1: Fire Local Notification
    await _fireLocalNotification(emergencyReason);

    // Step 2: Acquire GPS Fix
    double currentLat = lat ?? 0.0;
    double currentLng = lng ?? 0.0;
    try {
      final locPermission = await Geolocator.checkPermission();
      if (locPermission == LocationPermission.always || locPermission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 4),
        );
        currentLat = position.latitude;
        currentLng = position.longitude;
      }
    } catch (_) {}

    // Step 3: Direct SMS Dispatch
    await _sendSmsDispatch(emergencyReason, currentLat, currentLng);
  }

  Future<void> _fireLocalNotification(String reason) async {
    const androidDetails = AndroidNotificationDetails(
      'aegis_emergency_channel',
      'Aegis Emergency Alarms',
      channelDescription: 'High-priority emergency alerts triggered by wearable risk engine',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      999,
      '🚨 CRITICAL HEALTH / FALL ALERT',
      reason,
      details,
    );
  }

  Future<void> _sendSmsDispatch(String reason, double lat, double lng) async {
    final contacts = _storage.getContacts();
    final smsPermission = await Permission.sms.request();
    
    final mapsUrl = (lat != 0.0 && lng != 0.0)
        ? "https://maps.google.com/?q=$lat,$lng"
        : "GPS Acquired Offline";

    final message = "EMERGENCY ALERT: Wearable wearer triggered alarm.\nReason: $reason\nLocation: $mapsUrl";

    for (final contact in contacts) {
      if (smsPermission.isGranted && contact.phone.isNotEmpty) {
        try {
          await _telephony.sendSms(
            to: contact.phone,
            message: message,
          );
        } catch (_) {}
      }
    }
  }

  void resetAlert() {
    isAlertActive = false;
    _notificationsPlugin.cancel(999);
  }
}
