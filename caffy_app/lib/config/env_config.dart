import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8080/api';
  static String get appName => dotenv.env['APP_NAME'] ?? 'Caffy';
  static double get defaultHalfLife => double.tryParse(dotenv.env['DEFAULT_HALF_LIFE'] ?? '5.0') ?? 5.0;
  static int get defaultViewPeriodDays => int.tryParse(dotenv.env['DEFAULT_VIEW_PERIOD_DAYS'] ?? '7') ?? 7;
  static bool get debugMode => dotenv.env['DEBUG_MODE']?.toLowerCase() == 'true';
}
