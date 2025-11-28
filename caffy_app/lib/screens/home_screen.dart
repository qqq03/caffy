import 'dart:convert';
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
  bool isRecognizing = false; // 이미지 인식 중 로딩 상태
  bool isPersonalized = false;
  bool isPeaking = false; // 흡수 중 여부
  String canSleepMessage = ""; // 수면 가능 시간 메시지
  double halfLife = 5.0;
  double learningConfidence = 0.0;
  int viewPeriodDays = 7; // 기본 7일
  int bedtimeHour = 22; // 수면 목표 시간 (기본 22시)
  List<dynamic> logs = [];
  List<dynamic> graphPoints = []; // DB 기반 그래프 데이터
  
  // 그래프 줌 레벨 (1.0 = 전체, 24.0 = 1시간 단위까지 확대)
  double _graphZoomLevel = 1.0;
  double _graphZoomBase = 1.0; // 핀치 줌 시작점
  double _graphOffset = 0.0; // X축 드래그 오프셋 (시간 단위)
  double _graphOffsetBase = 0.0; // 드래그 시작점
  static const double _minZoom = 0.5;
  static const double _maxZoom = 24.0;
  
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
      final graphData = await ApiService.getGraphData();
      setState(() {
        currentMg = data['current_caffeine_mg'];
        statusMsg = data['status_message'];
        isPersonalized = data['is_personalized'] ?? false;
        halfLife = (data['half_life_used'] ?? 5.0).toDouble();
        learningConfidence = (data['learning_confidence'] ?? 0.0).toDouble();
        viewPeriodDays = data['view_period_days'] ?? 7; // 서버에서 받아온 값 사용
        logs = logsData;
        graphPoints = graphData['graph_points'] ?? [];
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

  // 이미지로 음료 인식 (스마트 인식: DB → LLM)
  Future<void> _pickImageAndRecognize(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    
    if (pickedFile != null) {
      setState(() => isRecognizing = true);
      
      try {
        // 이미지를 Base64로 변환
        final bytes = await pickedFile.readAsBytes();
        final base64Image = base64Encode(bytes);
        
        // 스마트 인식 API 호출
        final result = await ApiService.smartRecognizeDrink(base64Image);
        
        setState(() => isRecognizing = false);
        
        if (result['found'] == true) {
          final confidence = (result['confidence'] ?? 0.0).toDouble();
          final source = result['source'] ?? 'unknown';
          final caffeineAmount = result['caffeine_amount'] ?? 0;
          final drinkName = result['drink_name'] ?? '알 수 없는 음료';
          
          // DB 매칭 + 신뢰도 90% 이상이면 자동 등록
          if (source == 'database' && confidence >= 0.9 && caffeineAmount > 0) {
            _onDrink(caffeineAmount, name: drinkName);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ $drinkName ${caffeineAmount}mg 자동 등록!'),
                backgroundColor: Colors.green[700],
              ),
            );
          } else {
            // 신뢰도가 낮거나 AI 분석인 경우 → 확인 다이얼로그
            _showRecognitionResultDialog(result, pickedFile);
          }
        } else {
          // 인식 실패 → 수동 입력
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('음료를 인식하지 못했어요. 직접 입력해주세요.')),
          );
          _showManualInputDialog(pickedFile);
        }
      } catch (e) {
        setState(() => isRecognizing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인식 실패: $e')),
        );
        // 실패 시 수동 입력으로 전환
        _showManualInputDialog(pickedFile);
      }
    }
  }

  // 인식 결과 확인 다이얼로그
  void _showRecognitionResultDialog(Map<String, dynamic> result, XFile imageFile) {
    final drinkName = result['drink_name'] ?? '알 수 없는 음료';
    final caffeineAmount = result['caffeine_amount'] ?? 0;
    final confidence = (result['confidence'] ?? 0.0).toDouble();
    final source = result['source'] ?? 'unknown';
    final brand = result['brand'] ?? '';
    final isNew = result['is_new'] ?? false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Row(
          children: [
            Icon(
              source == 'database' ? Icons.flash_on : Icons.auto_awesome,
              color: source == 'database' ? Colors.green : Colors.amber,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                source == 'database' ? '즉시 인식!' : 'AI 분석 완료',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 이미지 미리보기
            FutureBuilder<Uint8List>(
              future: imageFile.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Container(
                    height: 120,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: MemoryImage(snapshot.data!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 120);
              },
            ),
            // 인식 결과
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand,
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    drinkName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$caffeineAmount mg',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: source == 'database' 
                            ? Colors.green.withOpacity(0.2) 
                            : Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          source == 'database' ? '💾 DB 매칭' : '🤖 AI 분석',
                          style: TextStyle(
                            color: source == 'database' ? Colors.green : Colors.amber,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '신뢰도 ${(confidence * 100).toInt()}%',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                  if (isNew)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '✨ 새로 학습된 음료입니다!',
                        style: TextStyle(color: Colors.purple[300], fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showManualInputDialog(imageFile);
            },
            child: Text('수정', style: TextStyle(color: Colors.grey[400])),
          ),
          ElevatedButton(
            onPressed: caffeineAmount > 0
                ? () {
                    Navigator.pop(ctx);
                    _onDrink(caffeineAmount, name: drinkName);
                  }
                : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('추가', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
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
    return Stack(
      children: [
        Scaffold(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "$currentMg mg",
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 40,
                      fontWeight: FontWeight.bold),
                ),
                if (isPeaking)
                  Container(
                    margin: const EdgeInsets.only(left: 8, bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.trending_up, color: Colors.orange, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '흡수 중',
                          style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Text(
              statusMsg,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            
            // 수면 가능 시간 표시
            if (canSleepMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bedtime, color: Colors.purple, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      canSleepMessage,
                      style: const TextStyle(color: Colors.purple, fontSize: 12),
                    ),
                  ],
                ),
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
            GestureDetector(
              onScaleStart: (details) {
                _graphZoomBase = _graphZoomLevel;
                _graphOffsetBase = _graphOffset;
              },
              onScaleUpdate: (details) {
                setState(() {
                  // 핀치 줌
                  double newZoom = _graphZoomBase * details.scale;
                  _graphZoomLevel = newZoom.clamp(_minZoom, _maxZoom);
                  
                  // 좌우 드래그 (픽셀 단위를 시간으로 변환)
                  final range = _getBaseRange() / _graphZoomLevel;
                  final hourPerPixel = range / 300; // 대략적인 그래프 너비
                  _graphOffset = _graphOffsetBase - (details.focalPointDelta.dx * hourPerPixel);
                  
                  // 오프셋 제한 (데이터 범위 내에서만)
                  final maxOffset = _getBaseRange() - range / 2;
                  _graphOffset = _graphOffset.clamp(-maxOffset, maxOffset);
                });
              },
              child: SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: _getDynamicMaxY() / 6,
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
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 35,
                          interval: _getDynamicMaxY() / 4,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              '${value.toInt()}',
                              style: TextStyle(color: Colors.grey[500], fontSize: 9),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    minX: _getMinX(),
                    maxX: _getMaxX(),
                    minY: 0,
                    maxY: _getDynamicMaxY(),
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
                        curveSmoothness: 0.3,
                        preventCurveOverShooting: true,
                        preventCurveOvershootingThreshold: 0,
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
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => Colors.grey[800]!,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            return LineTooltipItem(
                              '${spot.y.toInt()} mg',
                              const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                  ),
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
              height: 130,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        '아직 기록이 없어요 ☕️',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      itemCount: logs.length > 20 ? 20 : logs.length,
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
        ),
        // 이미지 인식 중 로딩 오버레이
        if (isRecognizing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.amber),
                  SizedBox(height: 16),
                  Text(
                    '음료 인식 중...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // 기간별 X축 범위 설정 (줌 레벨 + 드래그 오프셋 적용)
  double _getBaseRange() {
    switch (viewPeriodDays) {
      case 1: return 24; // 24시간
      case 3: return 48; // 48시간
      case 7: return 144; // 144시간 (6일)
      default: return 144;
    }
  }

  double _getMinX() {
    final baseRange = _getBaseRange();
    final visibleRange = baseRange / _graphZoomLevel;
    return -visibleRange / 2 + _graphOffset;
  }

  double _getMaxX() {
    final baseRange = _getBaseRange();
    final visibleRange = baseRange / _graphZoomLevel;
    return visibleRange / 2 + _graphOffset;
  }

  double _getGraphInterval() {
    double baseInterval;
    switch (viewPeriodDays) {
      case 1: baseInterval = 6; break; // 6시간 간격
      case 3: baseInterval = 12; break; // 12시간 간격
      case 7: baseInterval = 24; break; // 24시간 간격
      default: baseInterval = 24;
    }
    // 줌인하면 간격도 좁아짐
    return max(1, baseInterval / _graphZoomLevel);
  }

  // 동적 그래프 최대값 계산 (현재값의 120%, 최소 100mg)
  double _getDynamicMaxY() {
    // 그래프의 모든 데이터 포인트 중 최대값 계산
    final spots = _generateSpots(currentMg);
    double maxValue = currentMg.toDouble();
    for (final spot in spots) {
      if (spot.y > maxValue) maxValue = spot.y;
    }
    // 최대값의 120%로 설정 (최소 100)
    return max(100, maxValue * 1.2);
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

  // 수면시간까지 남은 시간 계산
  double _getHoursUntilBedtime() {
    final now = DateTime.now();
    final bedtime = DateTime(now.year, now.month, now.day, bedtimeHour, 0);
    
    if (now.isAfter(bedtime)) {
      // 이미 수면 시간이 지났으면 다음날
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

  // 수면 시간 설정 다이얼로그
  void _showBedtimeSettingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('수면 목표 시간 설정', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '언제 주무시나요?',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (int hour in [21, 22, 23, 0, 1, 2])
                  GestureDetector(
                    onTap: () {
                      setState(() => bedtimeHour = hour);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: bedtimeHour == hour ? Colors.amber : Colors.grey[700],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}시',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: bedtimeHour == hour ? Colors.black : Colors.white,
                          fontWeight: bedtimeHour == hour ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: Colors.grey[400])),
          ),
        ],
      ),
    );
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
              GestureDetector(
                onTap: _showBedtimeSettingDialog,
                child: Row(
                  children: [
                    Text(
                      '$bedtimeHour시 수면 기준',
                      style: TextStyle(
                        color: isSafe ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.edit,
                      color: Colors.grey[500],
                      size: 14,
                    ),
                  ],
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
              // 수면 시간 예상량
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
                    '$bedtimeHour시 예상량',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ 현재 상태로는 수면에 영향을 줄 수 있어요',
                    style: TextStyle(color: Colors.orange[300], fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.water_drop, color: Colors.blue[300], size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '💡 물을 많이 마시면 카페인 배출에 도움이 돼요!',
                          style: TextStyle(color: Colors.blue[300], fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // DB 기반 그래프 데이터 생성 (서버에서 받은 실제 데이터)
  List<FlSpot> _generateSpots(int initial) {
    // DB 데이터가 있으면 그것을 사용
    if (graphPoints.isNotEmpty) {
      List<FlSpot> spots = [];
      for (var point in graphPoints) {
        final hour = (point['hour'] as num).toDouble();
        final caffeine = (point['caffeine'] as num).toDouble();
        // 현재 뷰 범위 내의 데이터만 추가
        if (hour >= _getMinX() && hour <= _getMaxX()) {
          spots.add(FlSpot(hour, caffeine));
        }
      }
      return spots;
    }
    
    // 폴백: DB 데이터 없으면 기존 계산 로직 사용
    List<FlSpot> spots = [];
    final minX = _getMinX().toInt();
    final maxX = _getMaxX().toInt();
    
    for (int i = minX; i <= maxX; i++) {
      double y;
      if (i <= 0) {
        y = initial * pow(2, i.abs() / halfLife).toDouble();
      } else {
        y = initial * pow(0.5, i / halfLife).toDouble();
      }
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