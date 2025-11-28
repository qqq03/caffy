import 'dart:math';
import 'package:caffy_app/services/api_service.dart';
import 'package:caffy_app/services/auth_service.dart';
import 'package:caffy_app/screens/login_screen.dart';
import 'package:caffy_app/widgets/feedback_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentMg = 0;
  String statusMsg = "데이터 불러오는 중...";
  bool isLoading = true;
  bool isPersonalized = false;
  double halfLife = 5.0;
  double learningConfidence = 0.0;
  int viewPeriodDays = 7; // 기본 7일
  List<dynamic> logs = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // 서버에서 데이터 땡겨오기
  Future<void> _fetchData() async {
    try {
      final data = await ApiService.getMyStatus();
      final logsData = await ApiService.getMyLogs();
      setState(() {
        currentMg = data['current_caffeine_mg'];
        statusMsg = data['status_message'];
        isPersonalized = data['is_personalized'] ?? false;
        halfLife = (data['half_life_used'] ?? 5.0).toDouble();
        learningConfidence = (data['learning_confidence'] ?? 0.0).toDouble();
        viewPeriodDays = AuthService.currentUser?['view_period_days'] ?? 7;
        logs = logsData;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        statusMsg = "서버 연결 실패 ㅠㅠ";
        isLoading = false;
      });
      print(e);
    }
  }

  // 조회 기간 변경
  Future<void> _changeViewPeriod(int days) async {
    try {
      await ApiService.setViewPeriod(days);
      setState(() {
        viewPeriodDays = days;
      });
      _fetchData(); // 기간 변경 후 다시 로드
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정 변경 실패')),
      );
    }
  }

  // 커피 마시기 버튼 눌렀을 때
  Future<void> _onDrink(int amount) async {
    await ApiService.drinkCoffee("Americano", amount);
    _fetchData();
  }

  // 로그아웃
  void _logout() {
    AuthService.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // 피드백 다이얼로그
  void _showFeedback() {
    showFeedbackDialog(context, onFeedbackSubmitted: _fetchData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900], // 다크 모드 간지
      appBar: AppBar(
        title: Text('안녕, ${AuthService.currentUser?['nickname'] ?? 'Caffy'} ☕️'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 상태 텍스트
            Text(
              "현재 체내 잔류량",
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              "$currentMg mg",
              style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 48,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              statusMsg,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            
            // 학습 상태 표시
            if (isPersonalized)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '개인화됨 (반감기 ${halfLife.toStringAsFixed(1)}h, 신뢰도 ${(learningConfidence * 100).toInt()}%)',
                      style: const TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 40),

            // 기간 선택 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPeriodButton(1, '1일'),
                const SizedBox(width: 8),
                _buildPeriodButton(3, '3일'),
                const SizedBox(width: 8),
                _buildPeriodButton(7, '1주일'),
              ],
            ),
            const SizedBox(height: 20),

            // 2. 그래프 영역 (fl_chart)
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 10, // 향후 10시간 예측
                  minY: 0,
                  maxY: 300,
                  lineBarsData: [
                    LineChartBarData(
                      spots: _generateSpots(currentMg), // 곡선 데이터 생성
                      isCurved: true,
                      color: Colors.amber,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.amber.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const Spacer(),

            // 3. 피드백 버튼
            Center(
              child: TextButton.icon(
                onPressed: _showFeedback,
                icon: const Icon(Icons.psychology, color: Colors.amber),
                label: const Text(
                  '지금 기분은 어때요? (학습에 도움돼요)',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 4. 마시기 버튼들
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDrinkButton("샷 추가 (+75mg)", 75),
                _buildDrinkButton("아아 한잔 (+150mg)", 150),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 개인화된 반감기를 사용한 그래프 데이터 생성
  List<FlSpot> _generateSpots(int initial) {
    List<FlSpot> spots = [];
    for (int i = 0; i <= 10; i++) {
      // y = initial * (0.5)^(x/halfLife)
      double y = initial * pow(0.5, i / halfLife).toDouble();
      spots.add(FlSpot(i.toDouble(), y));
    }
    return spots;
  }

  Widget _buildDrinkButton(String label, int amount) {
    return ElevatedButton(
      onPressed: () => _onDrink(amount),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
      child: Text(label),
    );
  }

  Widget _buildPeriodButton(int days, String label) {
    final isSelected = viewPeriodDays == days;
    return GestureDetector(
      onTap: () => _changeViewPeriod(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.grey[600]!,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}