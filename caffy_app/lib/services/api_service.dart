import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // ⚠️ 에뮬레이터 사용 시: 10.0.2.2, 아이폰 시뮬레이터: 127.0.0.1
  // ⚠️ 실물 기기 사용 시: PC의 내부 IP (예: 192.168.0.x)
  // ⚠️ Windows 데스크톱: localhost
  static const String baseUrl = "http://localhost:8080/api"; 

  // 내 상태(남은 카페인 양) 가져오기
  static Future<Map<String, dynamic>> getStatus(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/status/$userId'));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('서버 통신 실패');
    }
  }

  // 커피 마시기 (로그 추가)
  static Future<void> drinkCoffee(int userId, String name, int amount) async {
    await http.post(
      Uri.parse('$baseUrl/logs'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "user_id": userId,
        "drink_name": name,
        "amount": amount,
        // intake_at은 서버에서 처리하므로 생략 가능
      }),
    );
  }
}