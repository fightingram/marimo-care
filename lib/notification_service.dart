import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(initSettings);
    // Timezone setup
    tz.initializeTimeZones();
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fallback to UTC if timezone fetch fails
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    // Request platform-specific permissions
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  Future<void> scheduleWaterChangeReminders({
    required DateTime lastWaterChangeAt,
    required bool enabled,
  }) async {
    if (!_initialized) await init();
    await _plugin.cancel(1001); // clear previous daily schedule id 1001
    if (!enabled) return;

    const androidDetails = AndroidNotificationDetails(
      'water_change_channel',
      'Water Change Reminder',
      channelDescription: 'Reminds you to change water at 10:00',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    final now = tz.TZDateTime.now(tz.local);
    final last = tz.TZDateTime.from(lastWaterChangeAt, tz.local);
    final thresholdDay = last.add(const Duration(days: 4));
    // first eligible 10:00 at or after threshold
    tz.TZDateTime first = tz.TZDateTime(tz.local, thresholdDay.year, thresholdDay.month, thresholdDay.day, 10);
    if (now.isAfter(first)) {
      final today10 = tz.TZDateTime(tz.local, now.year, now.month, now.day, 10);
      first = now.isBefore(today10) ? today10 : today10.add(const Duration(days: 1));
    }

    if (!now.isBefore(first) && now.difference(last).inDays < 4) {
      // If under threshold, don't schedule yet
      return;
    }

    await _plugin.zonedSchedule(
      1001,
      '水換えの時間です',
      'まりもをきれいな水で元気にしましょう',
      first,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
