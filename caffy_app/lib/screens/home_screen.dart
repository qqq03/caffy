import 'dart:math';
import 'dart:typed_data';
import 'package:caffy_app/services/api_service.dart';
import 'package:caffy_app/services/auth_service.dart';
import 'package:caffy_app/screens/login_screen.dart';
import 'package:caffy_app/widgets/feedback_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

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
  
  // 자주 사용하는 음료 (이름, 카페인량)
  List<Map<String, dynamic>> frequentDrinks = [
    {'name': '아메리카노', 'amount': 150, 'icon': Icons.coffee},
    {'name': '에스프레소', 'amount': 75, 'icon': Icons.local_cafe},
    {'name': '라떼', 'amount': 100, 'icon': Icons.coffee_maker},
  ];

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
        viewPeriodDays = data['view_period_days'] ?? 7; // 서버에서 받아온 값 사용
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
  Future<void> _onDrink(int amount, {String name = "Americano"}) async {
    await ApiService.drinkCoffee(name, amount);
    _fetchData();
  }

  // 이미지로 음료 인식
  Future<void> _pickImageAndRecognize(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    
    if (pickedFile != null) {
      // TODO: 이미지를 서버로 보내서 음료 인식
      // 지금은 임시로 다이얼로그로 수동 입력
      _showManualInputDialog(pickedFile);
    }
  }

  // 수동 입력 다이얼로그
  void _showManualInputDialog(XFile? imageFile) {
    final nameController = TextEditingController();
    final amountController = TextEditingController(text: '150');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('음료 추가', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageFile != null && !kIsWeb)
              FutureBuilder<Uint8List>(
                future: imageFile.readAsBytes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Container(
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: MemoryImage(snapshot.data!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '음료 이름',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '카페인 (mg)',
                labelStyle: TextStyle(color: Colors.grey[400]),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.amber),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.isNotEmpty ? nameController.text : 'Coffee';
              final amount = int.tryParse(amountController.text) ?? 150;
              Navigator.pop(ctx);
              _onDrink(amount, name: name);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('추가', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // 이미지 소스 선택 다이얼로그
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[850],
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.amber),
              title: const Text('카메라로 촬영', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageAndRecognize(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.amber),
              title: const Text('갤러리에서 선택', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageAndRecognize(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.amber),
              title: const Text('직접 입력', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _showManualInputDialog(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 섭취 기록 수정/삭제 다이얼로그
  void _showLogEditDialog(Map<String, dynamic> log) {
    final logId = log['ID'] ?? log['id'];
    final originalAmount = (log['amount'] ?? 0).toDouble();
    final drinkName = log['drink_name'] ?? 'Coffee';
    double selectedPercentage = 1.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(drinkName, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 현재 카페인량 표시
              Text(
                '${(originalAmount * selectedPercentage).toInt()} mg',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '원래: ${originalAmount.toInt()} mg',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 16),
              
              // 비율 슬라이더
              Text(
                '실제로 마신 양: ${(selectedPercentage * 100).toInt()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Slider(
                value: selectedPercentage,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                activeColor: Colors.amber,
                inactiveColor: Colors.grey[700],
                label: '${(selectedPercentage * 100).toInt()}%',
                onChanged: (value) {
                  setDialogState(() {
                    selectedPercentage = value;
                  });
                },
              ),
              
              // 빠른 선택 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPercentButton('25%', 0.25, selectedPercentage, (p) {
                    setDialogState(() => selectedPercentage = p);
                  }),
                  _buildPercentButton('50%', 0.5, selectedPercentage, (p) {
                    setDialogState(() => selectedPercentage = p);
                  }),
                  _buildPercentButton('75%', 0.75, selectedPercentage, (p) {
                    setDialogState(() => selectedPercentage = p);
                  }),
                  _buildPercentButton('100%', 1.0, selectedPercentage, (p) {
                    setDialogState(() => selectedPercentage = p);
                  }),
                ],
              ),
            ],
          ),
          actions: [
            // 삭제 버튼
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _deleteLog(logId);
              },
              child: const Text('삭제', style: TextStyle(color: Colors.red)),
            ),
            // 취소 버튼
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: TextStyle(color: Colors.grey[400])),
            ),
            // 저장 버튼
            ElevatedButton(
              onPressed: selectedPercentage != 1.0
                  ? () async {
                      Navigator.pop(ctx);
                      await _updateLog(logId, selectedPercentage);
                    }
                  : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('저장', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPercentButton(String label, double value, double current, Function(double) onTap) {
    final isSelected = (current - value).abs() < 0.01;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.grey[700],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // 섭취 기록 수정
  Future<void> _updateLog(int logId, double percentage) async {
    try {
      await ApiService.updateLog(logId, percentage: percentage);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록이 수정되었습니다')),
      );
      _fetchData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정 실패: $e')),
      );
    }
  }

  // 섭취 기록 삭제
  Future<void> _deleteLog(int logId) async {
    try {
      await ApiService.deleteLog(logId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록이 삭제되었습니다')),
      );
      _fetchData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. 수면 권장 대시보드
            _buildSleepRecommendationCard(),
            const SizedBox(height: 16),
            
            // 1. 상태 텍스트
            Text(
              "현재 체내 잔류량",
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              "$currentMg mg",
              style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 40,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              statusMsg,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
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
            
            const SizedBox(height: 20),

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
            const SizedBox(height: 16),

            // 2. 그래프 영역 (fl_chart) - 기간별 과거/미래 표시
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 50,
                    verticalInterval: _getGraphInterval(),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey[800]!,
                      strokeWidth: 1,
                    ),
                    getDrawingVerticalLine: (value) => FlLine(
                      color: Colors.grey[800]!,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: _getGraphInterval(),
                        getTitlesWidget: (value, meta) {
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              _getTimeLabel(value),
                              style: TextStyle(color: Colors.grey[500], fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: _getMinX(),
                  maxX: _getMaxX(),
                  minY: 0,
                  maxY: max(300, currentMg.toDouble() + 50),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      // 수면 권장 라인 (50mg 이하)
                      HorizontalLine(
                        y: 50,
                        color: Colors.green.withOpacity(0.7),
                        strokeWidth: 2,
                        dashArray: [8, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: const TextStyle(color: Colors.green, fontSize: 10),
                          labelResolver: (line) => '수면 권장 50mg',
                        ),
                      ),
                    ],
                    verticalLines: [
                      // 22시 수면 시간 라인
                      if (_getHoursUntilBedtime() >= _getMinX() && _getHoursUntilBedtime() <= _getMaxX())
                        VerticalLine(
                          x: _getHoursUntilBedtime(),
                          color: Colors.purple.withOpacity(0.7),
                          strokeWidth: 2,
                          dashArray: [8, 4],
                          label: VerticalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            style: const TextStyle(color: Colors.purple, fontSize: 10),
                            labelResolver: (line) => '22시 수면',
                          ),
                        ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _generateSpots(currentMg),
                      isCurved: true,
                      color: Colors.amber,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.amber.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. 최근 섭취 기록 - 좌우 스크롤 카드 형태
            Text(
              '최근 섭취 기록',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        '아직 기록이 없어요 ☕️',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: logs.length > 10 ? 10 : logs.length,
                      itemBuilder: (ctx, i) {
                        final log = logs[i];
                        final intakeAt = DateTime.parse(log['intake_at']);
                        final timeStr = DateFormat('MM/dd\nHH:mm').format(intakeAt);
                        final drinkName = log['drink_name'] ?? 'Coffee';
                        
                        return GestureDetector(
                          onTap: () => _showLogEditDialog(log),
                          child: Container(
                            width: 100,
                            margin: EdgeInsets.only(
                              right: 12,
                              left: i == 0 ? 0 : 0,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 음료 아이콘/이미지
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.coffee,
                                    color: Colors.amber,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 음료 이름
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    drinkName,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // 카페인량
                                Text(
                                  '${log['amount']?.toInt() ?? 0}mg',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // 시간
                                Text(
                                  timeStr,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),

            // 3. 피드백 버튼
            Center(
              child: TextButton.icon(
                onPressed: _showFeedback,
                icon: const Icon(Icons.psychology, color: Colors.amber, size: 18),
                label: const Text(
                  '지금 기분은 어때요?',
                  style: TextStyle(color: Colors.amber, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 4. 자주 마시는 음료
            Text(
              '빠른 추가',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ...frequentDrinks.map((drink) => _buildQuickButton(
                  "${drink['name']}\n+${drink['amount']}mg",
                  drink['icon'] as IconData,
                  () => _onDrink(drink['amount'] as int, name: drink['name'] as String),
                )),
              ],
            ),
            const SizedBox(height: 12),
            
            // 5. 추가 버튼들 (사진/갤러리/직접)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAddButton('카메라', Icons.camera_alt, () => _pickImageAndRecognize(ImageSource.camera)),
                _buildAddButton('갤러리', Icons.photo_library, () => _pickImageAndRecognize(ImageSource.gallery)),
                _buildAddButton('직접 입력', Icons.edit, () => _showManualInputDialog(null)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // 기간별 X축 범위 설정
  double _getMinX() {
    switch (viewPeriodDays) {
      case 1: return -12; // -12시간
      case 3: return -24; // -1일
      case 7: return -72; // -3일
      default: return -72;
    }
  }

  double _getMaxX() {
    switch (viewPeriodDays) {
      case 1: return 12; // +12시간
      case 3: return 24; // +1일
      case 7: return 72; // +3일
      default: return 72;
    }
  }

  double _getGraphInterval() {
    switch (viewPeriodDays) {
      case 1: return 6; // 6시간 간격
      case 3: return 12; // 12시간 간격
      case 7: return 24; // 24시간 간격
      default: return 24;
    }
  }

  String _getTimeLabel(double value) {
    final hours = value.toInt();
    final now = DateTime.now();
    final targetTime = now.add(Duration(hours: hours));
    
    if (viewPeriodDays == 1) {
      // 1일: 시간만 표시
      return '${targetTime.hour}시';
    } else {
      // 3일, 7일: 날짜/시간
      if (hours == 0) return '지금';
      return '${targetTime.month}/${targetTime.day}';
    }
  }

  // 22시(수면시간)까지 남은 시간 계산
  double _getHoursUntilBedtime() {
    final now = DateTime.now();
    final bedtime = DateTime(now.year, now.month, now.day, 22, 0); // 오늘 22시
    
    if (now.isAfter(bedtime)) {
      // 이미 22시가 지났으면 다음날 22시
      final tomorrowBedtime = bedtime.add(const Duration(days: 1));
      return tomorrowBedtime.difference(now).inMinutes / 60.0;
    }
    return bedtime.difference(now).inMinutes / 60.0;
  }

  // 22시에 50mg 이하가 되려면 지금 최대 얼마나 섭취 가능한지 계산
  int _getMaxAllowedIntake() {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    if (hoursUntilBedtime <= 0) return 0;
    
    // 22시에 50mg가 되려면 현재 얼마까지 가능한가
    // 현재량 + 추가량 = X, X * (0.5)^(hours/halfLife) = 50
    // X = 50 / (0.5)^(hours/halfLife) = 50 * 2^(hours/halfLife)
    final maxTotalAtNow = 50 * pow(2, hoursUntilBedtime / halfLife);
    final maxAdditional = maxTotalAtNow - currentMg;
    
    return max(0, maxAdditional.toInt());
  }

  // 22시에 예상되는 카페인량
  int _getCaffeineAtBedtime() {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    return (currentMg * pow(0.5, hoursUntilBedtime / halfLife)).toInt();
  }

  // 수면 권장 대시보드 카드
  Widget _buildSleepRecommendationCard() {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    final caffeineAtBedtime = _getCaffeineAtBedtime();
    final maxAllowed = _getMaxAllowedIntake();
    final isSafe = caffeineAtBedtime <= 50;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSafe 
            ? [Colors.green.withOpacity(0.2), Colors.green.withOpacity(0.1)]
            : [Colors.orange.withOpacity(0.2), Colors.red.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSafe ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSafe ? Icons.bedtime : Icons.warning_amber,
                color: isSafe ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '22시 수면 기준',
                style: TextStyle(
                  color: isSafe ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '${hoursUntilBedtime.toStringAsFixed(1)}시간 후',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 22시 예상량
              Column(
                children: [
                  Text(
                    '$caffeineAtBedtime mg',
                    style: TextStyle(
                      color: isSafe ? Colors.green : Colors.orange,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '22시 예상량',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey[700],
              ),
              // 추가 섭취 가능량
              Column(
                children: [
                  Text(
                    maxAllowed > 0 ? '+$maxAllowed mg' : '섭취 자제',
                    style: TextStyle(
                      color: maxAllowed > 0 ? Colors.amber : Colors.red,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '추가 가능량',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          if (!isSafe)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '⚠️ 현재 상태로는 수면에 영향을 줄 수 있어요',
                style: TextStyle(color: Colors.orange[300], fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // 개인화된 반감기를 사용한 그래프 데이터 생성 (과거 + 미래)
  List<FlSpot> _generateSpots(int initial) {
    List<FlSpot> spots = [];
    final minX = _getMinX().toInt();
    final maxX = _getMaxX().toInt();
    
    for (int i = minX; i <= maxX; i++) {
      double y;
      if (i <= 0) {
        // 과거: 역으로 계산 (현재 기준으로 과거엔 더 많았음)
        y = initial * pow(2, i.abs() / halfLife).toDouble();
      } else {
        // 미래: 감소 계산
        y = initial * pow(0.5, i / halfLife).toDouble();
      }
      // 최대값 제한 (너무 큰 값 방지)
      y = min(y, 500);
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

  Widget _buildQuickButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 95,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 95,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[600]!, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.amber, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
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