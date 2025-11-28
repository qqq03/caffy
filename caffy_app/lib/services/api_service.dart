import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ApiService {
  // ⚠️ 에뮬레이터 사용 시: 10.0.2.2, 아이폰 시뮬레이터: 127.0.0.1
  // ⚠️ 실물 기기 사용 시: PC의 내부 IP (예: 192.168.0.x)
  // ⚠️ Windows 데스크톱: localhost
  static const String baseUrl = "http://localhost:8080/api"; 

  // 내 상태(남은 카페인 양) 가져오기 - 토큰 기반
  static Future<Map<String, dynamic>> getMyStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/status'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('서버 통신 실패');
    }
  }

  // 커피 마시기 (로그 추가) - 토큰 기반
  static Future<void> drinkCoffee(String name, int amount, {int? beverageId}) async {
    final body = {
      "drink_name": name,
      "amount": amount,
    };
    if (beverageId != null) {
      body["beverage_id"] = beverageId;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/logs'),
      headers: AuthService.authHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('기록 추가 실패');
    }
  }

  // 섭취 기록 히스토리 가져오기
  static Future<List<dynamic>> getMyLogs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/logs'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['logs'] ?? [];
    } else {
      throw Exception('기록 조회 실패');
    }
  }

  // 조회 기간 설정 (1, 3, 7일)
  static Future<void> setViewPeriod(int days) async {
    final response = await http.put(
      Uri.parse('$baseUrl/settings/period'),
      headers: AuthService.authHeaders,
      body: jsonEncode({"days": days}),
    );

    if (response.statusCode != 200) {
      throw Exception('설정 변경 실패');
    }
  }

  // ========== 레거시 API (하위 호환용) ==========
  
  // 내 상태(남은 카페인 양) 가져오기 - ID 기반 (레거시)
  static Future<Map<String, dynamic>> getStatus(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/status/$userId'));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('서버 통신 실패');
    }
  }
}