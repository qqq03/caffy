import 'package:caffy_app/screens/login_screen.dart';
import 'package:caffy_app/config/env_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  
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
      home: const LoginScreen(),
    );
  }
}