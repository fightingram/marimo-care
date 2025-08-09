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
    required DateTime? lastWaterChangeAt,
    required bool enabled,
    DateTime? nowOverride,
  }) async {
    if (!_initialized) await init();
    // Clear previously scheduled IDs (legacy single id + new range)
    await _plugin.cancel(1001);
    // New range for daily one-shot notifications (includes day 11 death notice)
    const int baseId = 1100;
    const int count = 30; // upper bound; we'll stop at day 11
    for (int i = 0; i < count; i++) {
      await _plugin.cancel(baseId + i);
    }
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

    final now = (nowOverride == null)
        ? tz.TZDateTime.now(tz.local)
        : tz.TZDateTime.from(nowOverride, tz.local);
    final base = (lastWaterChangeAt == null)
        ? now
        : tz.TZDateTime.from(lastWaterChangeAt, tz.local);

    // Earliest day to notify: 4 days after last water (or now if never)
    final thresholdDay = base.add(const Duration(days: 4));

    tz.TZDateTime first;
    // Start from either threshold 10:00 or next 10:00 if past
    final threshold10 = tz.TZDateTime(tz.local, thresholdDay.year, thresholdDay.month, thresholdDay.day, 10);
    if (now.isBefore(threshold10)) {
      first = threshold10;
    } else {
      final today10 = tz.TZDateTime(tz.local, now.year, now.month, now.day, 10);
      first = now.isBefore(today10) ? today10 : today10.add(const Duration(days: 1));
    }

    // Ensure cooling-off: next notification must be >= 24h since last water
    final minAllowed = base.add(const Duration(hours: 24));
    while (first.isBefore(minAllowed)) {
      first = tz.TZDateTime(tz.local, first.year, first.month, first.day + 1, 10);
    }

    // If first is still in the past due to edge cases, push to next day
    if (!first.isAfter(now)) {
      first = tz.TZDateTime(tz.local, now.year, now.month, now.day, 10);
      if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
      while (first.isBefore(minAllowed)) {
        first = tz.TZDateTime(tz.local, first.year, first.month, first.day + 1, 10);
      }
    }

    // Schedule daily one-shot notifications at 10:00
    for (int i = 0; i < count; i++) {
      final when = first.add(Duration(days: i));
      // Determine days since last water for this 'when'
      final baseYmd = tz.TZDateTime(tz.local, base.year, base.month, base.day);
      final whenYmd = tz.TZDateTime(tz.local, when.year, when.month, when.day);
      final daysSinceBase = whenYmd.difference(baseYmd).inDays;
      // Stop scheduling after day 11 (no notifications beyond death)
      if (daysSinceBase > 11) break;
      final bool isDay10Warning = daysSinceBase == 10;
      final bool isDay11Death = daysSinceBase == 11;
      final title = isDay11Death
          ? 'まりもがいなくなってしまいました'
          : isDay10Warning
              ? '明日いなくなってしまうかも…'
              : '水換えの時間です';
      final body = isDay11Death
          ? '長い間お世話がなく、まりもはいなくなりました'
          : isDay10Warning
              ? '水換えしないと明日まりもがいなくなってしまうよ'
              : 'まりもをきれいな水で元気にしましょう';

      await _plugin.zonedSchedule(
        baseId + i,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Debug helper: schedule a single test notification for 1 minute later.
  Future<void> scheduleTestNotificationInOneMinute() async {
    if (!_initialized) await init();
    const int testId = 1200;
    await _plugin.cancel(testId);

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
    final when = now.add(const Duration(minutes: 1));
    await _plugin.zonedSchedule(
      testId,
      'テスト通知',
      'これはデバッグ用の1分後通知です',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
