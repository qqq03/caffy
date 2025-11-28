import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = "http://localhost:8080/api";
  
  static String? _token;
  static Map<String, dynamic>? _currentUser;

  // 토큰 getter
  static String? get token => _token;
  static Map<String, dynamic>? get currentUser => _currentUser;
  static bool get isLoggedIn => _token != null;
  static int? get userId => _currentUser?['ID'];

  // 회원가입
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String nickname,
    double? weight,
    int metabolismType = 0,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "password": password,
        "nickname": nickname,
        "weight": weight ?? 70.0,
        "metabolism_type": metabolismType,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      _token = data['token'];
      _currentUser = data['user'];
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
    final response = await http.post(
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
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '로그인 실패');
    }
  }

  // 로그아웃
  static void logout() {
    _token = null;
    _currentUser = null;
  }

  // 인증된 요청 헤더
  static Map<String, String> get authHeaders => {
    "Content-Type": "application/json",
    if (_token != null) "Authorization": "Bearer $_token",
  };

  // 내 정보 조회
  static Future<Map<String, dynamic>> getMe() async {
    final response = await http.get(
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
    int? metabolismType,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/me'),
      headers: authHeaders,
      body: jsonEncode({
        "nickname": nickname ?? _currentUser?['nickname'],
        "weight": weight ?? _currentUser?['weight'],
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
    final response = await http.post(
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
