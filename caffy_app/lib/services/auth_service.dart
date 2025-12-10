import 'dart:convert';
import '../config/env_config.dart';
import 'http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// withCredentials 지원 HTTP 클라이언트 (전역)
final _authClient = createHttpClient();

class AuthService {
  static String get baseUrl => EnvConfig.apiBaseUrl;
  
  static String? _token;
  static Map<String, dynamic>? _currentUser;
  
  // SharedPreferences 키
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';

  // 토큰 getter
  static String? get token => _token;
  static Map<String, dynamic>? get currentUser => _currentUser;
  static bool get isLoggedIn => _token != null;
  static int? get userId => _currentUser?['ID'];

  // 저장된 토큰으로 자동 로그인 시도
  static Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_tokenKey);
      final savedUserJson = prefs.getString(_userKey);
      
      if (savedToken == null || savedUserJson == null) {
        return false;
      }
      
      // 토큰 설정
      _token = savedToken;
      _currentUser = jsonDecode(savedUserJson);
      
      // 토큰 유효성 검증 (서버에 요청)
      try {
        await getMe();
        return true;
      } catch (e) {
        // 토큰이 만료되었으면 저장된 정보 삭제
        await _clearSavedAuth();
        _token = null;
        _currentUser = null;
        return false;
      }
    } catch (e) {
      return false;
    }
  }
  
  // 토큰 및 사용자 정보 저장
  static Future<void> _saveAuth() async {
    if (_token == null || _currentUser == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userKey, jsonEncode(_currentUser));
  }
  
  // 저장된 인증 정보 삭제
  static Future<void> _clearSavedAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  // 회원가입
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
  }) async {
    // 닉네임은 이메일 앞부분으로 자동 설정
    final String defaultNickname = email.split('@')[0];

    final response = await _authClient.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "password": password,
        "nickname": defaultNickname,
        "weight": 70.0,
        "height": 170.0,
        "gender": 0,
        "is_smoker": false,
        "is_pregnant": false,
        "exercise_per_week": 0,
        "metabolism_type": 0,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      _token = data['token'];
      _currentUser = data['user'];
      await _saveAuth(); // 자동 로그인용 저장
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '회원가입 실패');
    }
  }

  // 로그인
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _authClient.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "password": password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _token = data['token'];
      _currentUser = data['user'];
      await _saveAuth(); // 자동 로그인용 저장
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '로그인 실패');
    }
  }

  // 로그아웃
  static Future<void> logout() async {
    _token = null;
    _currentUser = null;
    await _clearSavedAuth(); // 저장된 정보도 삭제
  }

  // 인증된 요청 헤더
  static Map<String, String> get authHeaders => {
    "Content-Type": "application/json",
    if (_token != null) "Authorization": "Bearer $_token",
  };

  // 내 정보 조회
  static Future<Map<String, dynamic>> getMe() async {
    final response = await _authClient.get(
      Uri.parse('$baseUrl/me'),
      headers: authHeaders,
    );

    if (response.statusCode == 200) {
      _currentUser = jsonDecode(response.body);
      return _currentUser!;
    } else {
      throw Exception('사용자 정보 조회 실패');
    }
  }

  // 내 정보 수정
  static Future<Map<String, dynamic>> updateMe({
    String? nickname,
    double? weight,
    double? height,
    int? gender,
    bool? isSmoker,
    bool? isPregnant,
    int? exercisePerWeek,
    int? metabolismType,
  }) async {
    final response = await _authClient.put(
      Uri.parse('$baseUrl/me'),
      headers: authHeaders,
      body: jsonEncode({
        "nickname": nickname ?? _currentUser?['nickname'],
        "weight": weight ?? _currentUser?['weight'],
        "height": height ?? _currentUser?['height'],
        "gender": gender ?? _currentUser?['gender'],
        "is_smoker": isSmoker ?? _currentUser?['is_smoker'],
        "is_pregnant": isPregnant ?? _currentUser?['is_pregnant'],
        "exercise_per_week": exercisePerWeek ?? _currentUser?['exercise_per_week'],
        "metabolism_type": metabolismType ?? _currentUser?['metabolism_type'],
      }),
    );

    if (response.statusCode == 200) {
      _currentUser = jsonDecode(response.body);
      return _currentUser!;
    } else {
      throw Exception('정보 수정 실패');
    }
  }

  // 비밀번호 변경
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _authClient.post(
      Uri.parse('$baseUrl/me/password'),
      headers: authHeaders,
      body: jsonEncode({
        "current_password": currentPassword,
        "new_password": newPassword,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '비밀번호 변경 실패');
    }
  }
}
