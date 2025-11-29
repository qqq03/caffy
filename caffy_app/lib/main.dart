import 'package:caffy_app/screens/login_screen.dart';
import 'package:caffy_app/screens/home_screen.dart';
import 'package:caffy_app/services/auth_service.dart';
import 'package:caffy_app/services/notification_service.dart';
import 'package:caffy_app/config/env_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: EnvConfig.appName,
      debugShowCheckedModeBanner: !EnvConfig.debugMode,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.amber,
        useMaterial3: true,
      ),
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