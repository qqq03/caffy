import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  static bool _initialized = false;
  
  // 알림 ID 상수
  static const int dailySummaryId = 0;
  static const int sleepReminderId = 1;
  static const int caffeineWarningId = 2;
  
  // SharedPreferences 키
  static const String _lastDailyNotifKey = 'last_daily_notification_date';

  // 초기화
  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return; // 웹에서는 지원 안함
    
    tzdata.initializeTimeZones();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    _initialized = true;
  }

  // 알림 탭 시 콜백
  static void _onNotificationTapped(NotificationResponse response) {
    // 알림 탭 시 처리 (필요시 구현)
    print('Notification tapped: ${response.payload}');
  }

  // 권한 요청
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } else if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  // 특정 ID의 활성 알림이 있는지 확인
  static Future<bool> hasActiveNotification(int id) async {
    if (kIsWeb) return false;
    if (!_initialized) await initialize();
    
    final activeNotifications = await _notifications.getActiveNotifications();
    return activeNotifications.any((n) => n.id == id);
  }
  
  // 특정 ID의 예약된 알림이 있는지 확인
  static Future<bool> hasPendingNotification(int id) async {
    if (kIsWeb) return false;
    if (!_initialized) await initialize();
    
    final pendingNotifications = await _notifications.pendingNotificationRequests();
    return pendingNotifications.any((n) => n.id == id);
  }

  // 즉시 알림 보내기 (오늘의 카페인 요약) - 기존 알림 없을 때만
  static Future<bool> showDailySummary({
    required int todayTotal,
    required int currentMg,
    required int availableBeforeSleep,
  }) async {
    if (kIsWeb) return false;
    if (!_initialized) await initialize();
    
    // 이미 활성 알림이 있으면 보내지 않음
    const notificationId = 0;
    if (await hasActiveNotification(notificationId)) {
      print('Daily summary notification already exists, skipping...');
      return false;
    }

    String body;
    if (availableBeforeSleep > 0) {
      body = '오늘 섭취: ${todayTotal}mg | 현재 잔류: ${currentMg}mg\n'
             '수면 전 ${availableBeforeSleep}mg 더 마실 수 있어요 ☕';
    } else {
      body = '오늘 섭취: ${todayTotal}mg | 현재 잔류: ${currentMg}mg\n'
             '수면을 위해 카페인을 자제하세요 😴';
    }

    const androidDetails = AndroidNotificationDetails(
      'caffy_daily',
      '오늘의 카페인',
      channelDescription: '일일 카페인 섭취 요약',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      notificationId,
      '☕ 오늘의 카페인',
      body,
      details,
      payload: 'daily_summary',
    );
    
    return true;
  }

  // 수면 전 알림 예약 (수면 1시간 전) - 기존 예약 없을 때만
  static Future<bool> scheduleSleepReminder({
    required int hour,
    required int minute,
    required int currentMg,
    required int threshold,
  }) async {
    if (kIsWeb) return false;
    if (!_initialized) await initialize();
    
    // 이미 예약된 알림이 있으면 스킵
    const notificationId = 1;
    if (await hasPendingNotification(notificationId)) {
      print('Sleep reminder already scheduled, skipping...');
      return false;
    };

    // 수면 1시간 전 시간 계산
    final now = DateTime.now();
    var reminderTime = DateTime(now.year, now.month, now.day, hour, minute)
        .subtract(const Duration(hours: 1));
    
    // 이미 지났으면 내일로
    if (reminderTime.isBefore(now)) {
      reminderTime = reminderTime.add(const Duration(days: 1));
    }

    final scheduledDate = tz.TZDateTime.from(reminderTime, tz.local);

    String body;
    if (currentMg > threshold) {
      body = '현재 체내 카페인 ${currentMg}mg\n'
             '수면 기준(${threshold}mg)을 초과했어요. 수면에 영향이 있을 수 있습니다 😴';
    } else {
      body = '현재 체내 카페인 ${currentMg}mg\n'
             '수면 기준(${threshold}mg) 이하입니다. 편안한 수면 되세요! 🌙';
    }

    const androidDetails = AndroidNotificationDetails(
      'caffy_sleep',
      '수면 알림',
      channelDescription: '수면 전 카페인 상태 알림',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      notificationId,
      '🌙 수면 1시간 전',
      body,
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'sleep_reminder',
    );
    
    return true;
  }

  // 모든 예약된 알림 취소
  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _notifications.cancelAll();
  }

  // 특정 알림 취소
  static Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _notifications.cancel(id);
  }
  
  // ========== 자동 알림 시스템 ==========
  
  // 오늘 이미 일일 요약 알림을 보냈는지 확인
  static Future<bool> _hasSentDailyNotificationToday() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_lastDailyNotifKey);
    if (lastDate == null) return false;
    
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    return lastDate == todayStr;
  }
  
  // 일일 요약 알림 발송 기록 저장
  static Future<void> _markDailyNotificationSent() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    await prefs.setString(_lastDailyNotifKey, todayStr);
  }
  
  /// 앱 시작 시 호출 - 자동 알림 설정
  /// 1. 오늘 첫 접속이면 일일 요약 알림 전송
  /// 2. 수면 1시간 전 알림 자동 예약
  static Future<void> setupAutoNotifications({
    required int todayTotal,
    required int currentMg,
    required int availableBeforeSleep,
    required int bedtimeHour,
    required int bedtimeMinute,
    required int sleepThreshold,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    
    // 1. 오늘 첫 접속이면 일일 요약 알림 (하루 1회)
    if (!await _hasSentDailyNotificationToday()) {
      final sent = await showDailySummary(
        todayTotal: todayTotal,
        currentMg: currentMg,
        availableBeforeSleep: availableBeforeSleep,
      );
      if (sent) {
        await _markDailyNotificationSent();
        print('📱 일일 요약 알림 자동 전송됨');
      }
    }
    
    // 2. 수면 1시간 전 알림 예약 (없으면)
    await scheduleSleepReminder(
      hour: bedtimeHour,
      minute: bedtimeMinute,
      currentMg: currentMg,
      threshold: sleepThreshold,
    );
  }
  
  /// 카페인 섭취 시 호출 - 경고 알림 (수면 전 추가 불가능할 때)
  static Future<void> showCaffeineWarningIfNeeded({
    required int currentMg,
    required int threshold,
    required int hoursUntilSleep,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();
    
    // 수면 3시간 이내이고, 기준치 초과 시 경고
    if (hoursUntilSleep <= 3 && currentMg > threshold) {
      const androidDetails = AndroidNotificationDetails(
        'caffy_warning',
        '카페인 경고',
        channelDescription: '수면 전 카페인 초과 경고',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        caffeineWarningId,
        '⚠️ 카페인 주의',
        '수면까지 ${hoursUntilSleep}시간 남았는데 ${currentMg}mg이에요!\n수면에 영향이 있을 수 있습니다.',
        details,
        payload: 'caffeine_warning',
      );
    }
  }
}
