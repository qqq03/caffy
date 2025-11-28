import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class LearningService {
  static const String baseUrl = "http://localhost:8080/api";

  /// 체감 피드백 제출 (실시간 학습)
  /// senseLevel: 1(졸림) ~ 5(매우 각성)
  static Future<Map<String, dynamic>> submitFeedback({
    required int senseLevel,
    String? actualFeeling,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/learning/feedback'),
      headers: AuthService.authHeaders,
      body: jsonEncode({
        "sense_level": senseLevel,
        "actual_feeling": actualFeeling ?? "",
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('피드백 제출 실패');
    }
  }

  /// 학습 통계 조회
  static Future<Map<String, dynamic>> getStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/learning/stats'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('통계 조회 실패');
    }
  }

  /// 배치 학습 트리거
  static Future<Map<String, dynamic>> triggerBatchLearning() async {
    final response = await http.post(
      Uri.parse('$baseUrl/learning/train'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('학습 실패');
    }
  }

  /// 개인화된 예측 조회
  static Future<Map<String, dynamic>> getPrediction() async {
    final response = await http.get(
      Uri.parse('$baseUrl/learning/prediction'),
      headers: AuthService.authHeaders,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('예측 조회 실패');
    }
  }
}
