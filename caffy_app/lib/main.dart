import 'package:caffy_app/screens/login_screen.dart';
import 'package:caffy_app/screens/home_screen.dart';
import 'package:caffy_app/services/auth_service.dart';
import 'package:caffy_app/services/notification_service.dart';
import 'package:caffy_app/config/env_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
  // 알림 서비스 초기화 (웹 제외)
  if (!kIsWeb) {
    await NotificationService.initialize();
    await NotificationService.requestPermission();
  }
  
  // 플랫폼 확인 로그
  print('=== Platform Debug ===');
  print('kIsWeb: $kIsWeb');
  print('Current Platform: ${EnvConfig.currentPlatform}');
  print('Selected API URL: ${EnvConfig.apiBaseUrl}');
  print('======================');
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  
  // 전역 테마 변경 함수
  static void setThemeMode(BuildContext context, bool isDark) {
    final state = context.findAncestorStateOfType<_MyAppState>();
    state?.setThemeMode(isDark);
  }
  
  static bool isDarkMode(BuildContext context) {
    final state = context.findAncestorStateOfType<_MyAppState>();
    return state?._isDarkMode ?? true;
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = true;
  
  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }
  
  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    });
  }
  
  void setThemeMode(bool isDark) {
    setState(() {
      _isDarkMode = isDark;
    });
    // 비동기로 저장 (UI 블로킹 없이)
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('isDarkMode', isDark);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 아이보리 톤 색상
    const ivoryBackground = Color(0xFFFAF8F5);
    const ivoryAppBar = Color(0xFFF5F3F0);
    
    return MaterialApp(
      title: EnvConfig.appName,
      debugShowCheckedModeBanner: !EnvConfig.debugMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.amber,
        useMaterial3: true,
        scaffoldBackgroundColor: ivoryBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: ivoryAppBar,
          foregroundColor: Colors.black87,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.amber,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
        ),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}

// 스플래시 화면 - 자동 로그인 시도
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    // 자동 로그인 시도
    final success = await AuthService.tryAutoLogin();
    
    if (!mounted) return;
    
    // 결과에 따라 화면 이동
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => success ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.coffee, size: 80, color: Colors.amber),
            SizedBox(height: 24),
            Text(
              'Caffy',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.amber),
          ],
        ),
      ),
    );
  }
}