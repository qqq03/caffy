import 'dart:math';

class CaffeineCalculator {
  static const double absorptionTimeMinutes = 45.0; // 흡수 시간 45분

  /// 단일 섭취 기록에 대한 특정 시점의 잔여량 계산
  static double calculateAtTime(double amount, DateTime intakeAt, DateTime targetTime, double halfLife) {
    final elapsedMinutes = targetTime.difference(intakeAt).inMinutes.toDouble();
    final elapsedHours = elapsedMinutes / 60.0;

    double currentAmount = 0.0;

    if (elapsedMinutes < 0) {
      // 미래의 섭취
      currentAmount = 0.0;
    } else {
      // 1. 대사 (Elimination): 섭취 직후부터 분해 시작 (반감기 적용)
      final eliminationFactor = pow(0.5, elapsedHours / halfLife);

      // 2. 흡수 (Absorption): 0~45분 동안 혈중 농도 상승
      double absorptionFactor = 1.0;
      if (elapsedMinutes < absorptionTimeMinutes) {
        final ratio = elapsedMinutes / absorptionTimeMinutes;
        absorptionFactor = sin(ratio * pi / 2);
      }

      // 최종 잔여량 = 섭취량 * 흡수율 * 대사잔존율
      // (흡수되는 동안에도 대사는 계속 일어나므로 두 팩터를 곱함)
      currentAmount = amount * absorptionFactor * eliminationFactor;
    }

    // // 극소량이거나 24시간 지났으면 0 처리
    // if (elapsedHours > 24 || currentAmount < 1.0) {
    //   return 0.0;
    // }

    return currentAmount;
  }

  /// 현재 시점의 잔여량 계산 (편의 함수)
  static double calculateRemaining(double amount, DateTime intakeAt, double halfLife) {
    return calculateAtTime(amount, intakeAt, DateTime.now(), halfLife);
  }

  /// 전체 기록을 합산하여 현재 총 잔여량 계산
  static double calculateTotalRemaining(List<dynamic> logs, double halfLife) {
    double total = 0.0;
    final now = DateTime.now();
    
    for (var log in logs) {
      double amount = (log['amount'] as num).toDouble();
      DateTime intakeAt = DateTime.parse(log['intake_at']);
      
      total += calculateAtTime(amount, intakeAt, now, halfLife);
    }
    return (total * 10).round() / 10.0;
  }

  /// 그래프 데이터 생성
  static List<Map<String, dynamic>> generateGraphPoints(List<dynamic> logs, double halfLife, int periodDays) {
    final now = DateTime.now();
    List<Map<String, dynamic>> points = [];
    
    // 과거 periodDays * 24시간 ~ 미래 periodDays * 12시간
    // 30분 단위로 포인트 생성
    int intervalsBack = periodDays * 48;
    int intervalsForward = periodDays * 24;

    for (int i = -intervalsBack; i <= intervalsForward; i++) {
      final targetTime = now.add(Duration(minutes: i * 30));
      double totalCaffeine = 0.0;

      for (var log in logs) {
        double amount = (log['amount'] as num).toDouble();
        DateTime intakeAt = DateTime.parse(log['intake_at']);
        
        totalCaffeine += calculateAtTime(amount, intakeAt, targetTime, halfLife);
      }

      points.add({
        "hour": i / 2.0,
        "time": targetTime.toIso8601String(),
        "caffeine": totalCaffeine.round(),
      });
    }
    
    return points;
  }
}
