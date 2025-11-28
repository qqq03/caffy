import 'package:caffy_app/services/api_service.dart';
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
  
  // 임시로 사용자 ID 1번 고정 (나중에 로그인 붙이면 됩니다)
  final int userId = 1; 

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // 서버에서 데이터 땡겨오기
  Future<void> _fetchData() async {
    try {
      final data = await ApiService.getStatus(userId);
      setState(() {
        currentMg = data['current_caffeine_mg'];
        statusMsg = data['status_message'];
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

  // 커피 마시기 버튼 눌렀을 때
  Future<void> _onDrink(int amount) async {
    // 1. 서버에 전송
    await ApiService.drinkCoffee(userId, "Americano", amount);
    // 2. 화면 갱신
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900], // 다크 모드 간지
      appBar: AppBar(
        title: const Text('Caffy ☕️'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
            
            const SizedBox(height: 40),

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

            // 3. 마시기 버튼들
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

  // 간단한 그래프 데이터 생성 시뮬레이션 (반감기 5시간 가정)
  List<FlSpot> _generateSpots(int initial) {
    List<FlSpot> spots = [];
    for (int i = 0; i <= 10; i++) {
      // y = initial * (0.5)^(x/5)
      double y = initial * (1 / (1 + (i * 0.1))); // 단순화된 감소 곡선
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
}