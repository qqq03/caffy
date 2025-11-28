import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 웹이 아닐 때만 dart:io import
import 'platform_stub.dart'
    if (dart.library.io) 'dart:io';

class EnvConfig {
  // 플랫폼별 API URL 자동 선택
  static String get apiBaseUrl {
    // 웹은 먼저 체크 (dart:io 사용 불가)
    if (kIsWeb) {
      return dotenv.env['API_URL_WEB'] ?? 'http://localhost:8080/api';
    }
    
    // 네이티브 플랫폼
    if (Platform.isAndroid) {
      return dotenv.env['API_URL_ANDROID'] ?? 'http://10.0.2.2:8080/api';
    }
    if (Platform.isIOS) {
      return dotenv.env['API_URL_IOS'] ?? 'http://127.0.0.1:8080/api';
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return dotenv.env['API_URL_WEB'] ?? 'http://localhost:8080/api';
    }
    
    return 'http://localhost:8080/api';
  }



  // 실물 기기용 URL (수동 사용 시)
  static String get deviceApiUrl => dotenv.env['API_URL_DEVICE'] ?? 'http://192.168.0.100:8080/api';

  static String get appName => dotenv.env['APP_NAME'] ?? 'Caffy';
  static double get defaultHalfLife => double.tryParse(dotenv.env['DEFAULT_HALF_LIFE'] ?? '5.0') ?? 5.0;
  static int get defaultViewPeriodDays => int.tryParse(dotenv.env['DEFAULT_VIEW_PERIOD_DAYS'] ?? '7') ?? 7;
  static bool get debugMode => dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';

  // 현재 플랫폼 정보
  static String get currentPlatform {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }
}
