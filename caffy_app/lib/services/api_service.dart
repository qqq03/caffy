import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:caffy_app/config/env_config.dart';
import 'auth_service.dart';

class ApiService {
  // .env 파일에서 API URL 가져오기
  static String get baseUrl => EnvConfig.apiBaseUrl;


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

  // 섭취 기록 수정 (비율 조절, 시간 수정)
  static Future<void> updateLog(int logId, {double? ratio, String? drinkName, DateTime? drankAt}) async {
    final body = <String, dynamic>{};
    if (ratio != null) body['ratio'] = ratio;  // 원래 양 대비 비율
    if (drinkName != null) body['drink_name'] = drinkName;
    if (drankAt != null) body['drank_at'] = drankAt.toUtc().toIso8601String();

    print('updateLog 요청: logId=$logId, body=$body'); // 디버그 로그

    final response = await http.put(
      Uri.parse('$baseUrl/logs/$logId'),
      headers: AuthService.authHeaders,
      body: jsonEncode(body),
    );

    print('updateLog 응답: ${response.statusCode} ${response.body}'); // 디버그 로그

    if (response.statusCode != 200) {
      throw Exception('기록 수정 실패');
    }
  }

  // 섭취 기록 삭제
  static Future<void> deleteLog(int logId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/logs/$logId'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('기록 삭제 실패');
    }
  }

  // 그래프 데이터 조회 (DB 기반 실제 잔류량)
  static Future<Map<String, dynamic>> getGraphData() async {
    final response = await http.get(
      Uri.parse('$baseUrl/graph'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('그래프 데이터 조회 실패');
    }
  }

  // ========== 스마트 이미지 인식 API ==========

  /// 이미지로 음료 인식 (DB 우선 → LLM 폴백)
  /// 반환: {found, drink_name, caffeine_amount, confidence, source, brand, category, is_new}
  static Future<Map<String, dynamic>> smartRecognizeDrink(String imageBase64) async {
    final response = await http.post(
      Uri.parse('$baseUrl/recognize/smart'),
      headers: AuthService.authHeaders,
      body: jsonEncode({'image_base64': imageBase64}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '음료 인식 실패');
    }
  }

  /// 음료명+사이즈로 카페인 추정 (AI)
  /// size: "short", "tall", "grande", "venti", "trenta" 또는 null
  /// sizeML: 직접 입력한 용량 (ml) 또는 null
  static Future<Map<String, dynamic>> estimateCaffeineByText(String drinkName, {String? size, int? sizeML}) async {
    final body = <String, dynamic>{
      'drink_name': drinkName,
    };
    if (size != null) body['size'] = size;
    if (sizeML != null) body['size_ml'] = sizeML;

    final response = await http.post(
      Uri.parse('$baseUrl/recognize/text'),
      headers: AuthService.authHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? '카페인 추정 실패');
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