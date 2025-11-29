import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:caffy_app/main.dart';
import 'package:caffy_app/services/api_service.dart';
import 'package:caffy_app/services/auth_service.dart';
import 'package:caffy_app/services/notification_service.dart';
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
  TimeOfDay bedtime = const TimeOfDay(hour: 22, minute: 0); // 수면 목표 시간
  int sleepThresholdMg = 50; // 수면 기준 카페인량 (mg)
  List<dynamic> logs = [];
  List<dynamic> graphPoints = []; // DB 기반 그래프 데이터
  
  // 그래프 줌 레벨 (1.0 = 전체, 48.0 = 30분 단위까지 확대)
  double _graphZoomLevel = 1.0;
  double _graphZoomBase = 1.0; // 핀치 줌 시작점
  double _graphOffset = 0.0; // X축 드래그 오프셋 (시간 단위)
  double _graphOffsetBase = 0.0; // 드래그 시작점
  static const double _minZoom = 0.5;
  static const double _maxZoom = 48.0; // 더 세밀한 줌 가능
  
  // 2시간마다 알림 체크 타이머
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _startNotificationTimer();
  }
  
  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }
  
  // 2시간마다 알림 체크 타이머 시작
  void _startNotificationTimer() {
    if (kIsWeb) return;
    
    // 2시간마다 체크
    _notificationTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      _setupAutoNotifications();
    });
  }

  // 서버에서 데이터 땡겨오기
  Future<void> _fetchData() async {
    try {
      final data = await ApiService.getMyStatus();
      
      // 로그 데이터는 실패해도 계속 진행
      List<dynamic> logsData = [];
      try {
        logsData = await ApiService.getMyLogs();
      } catch (e) {
        print('로그 데이터 로드 실패: $e');
      }
      
      // 그래프 데이터는 실패해도 계속 진행
      List<dynamic> graphData = [];
      try {
        final graphResult = await ApiService.getGraphData();
        graphData = graphResult['graph_points'] ?? [];
      } catch (e) {
        print('그래프 데이터 로드 실패: $e');
      }
      
      setState(() {
        currentMg = data['current_caffeine_mg'] ?? 0;
        statusMsg = data['status_message'] ?? '상태를 불러왔습니다';
        isPersonalized = data['is_personalized'] ?? false;
        isPeaking = data['is_peaking'] ?? false;
        canSleepMessage = data['can_sleep_message'] ?? '';
        halfLife = (data['half_life_used'] as num?)?.toDouble() ?? 5.0;
        learningConfidence = (data['learning_confidence'] as num?)?.toDouble() ?? 0.0;
        viewPeriodDays = data['view_period_days'] ?? 7;
        logs = logsData;
        graphPoints = graphData;
        isLoading = false;
      });
      
      // 자동 알림 설정 (웹 제외)
      _setupAutoNotifications();
    } catch (e) {
      print('서버 연결 : $e');
      setState(() {
        statusMsg = "";
        isLoading = false;
      });
    }
  }
  
  // 자동 알림 설정
  void _setupAutoNotifications() {
    if (kIsWeb) return;
    
    final todayTotal = _getTodayTotalIntake();
    final available = _getAvailableCaffeineBeforeSleep();
    
    NotificationService.setupAutoNotifications(
      todayTotal: todayTotal,
      currentMg: currentMg,
      availableBeforeSleep: available,
      bedtimeHour: bedtime.hour,
      bedtimeMinute: bedtime.minute,
      sleepThreshold: sleepThresholdMg,
    );
  }

  // 조회 기간 변경
  Future<void> _changeViewPeriod(int days) async {
    // 유효 범위 제한 (1~30일)
    final validDays = days.clamp(1, 30);
    if (viewPeriodDays == validDays) return; // 이미 같은 값이면 무시
    
    try {
      await ApiService.setViewPeriod(validDays);
      setState(() {
        viewPeriodDays = validDays;
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
    await _fetchData();
    
    // 카페인 섭취 후 수면 시간까지 과다 섭취 경고 확인
    final todayTotal = _getTodayTotalIntake();
    
    // 수면 시간까지 남은 시간 계산
    final now = DateTime.now();
    DateTime sleepDateTime = DateTime(now.year, now.month, now.day, bedtime.hour, bedtime.minute);
    if (sleepDateTime.isBefore(now)) {
      sleepDateTime = sleepDateTime.add(const Duration(days: 1));
    }
    final hoursUntilSleep = sleepDateTime.difference(now).inHours;
    
    await NotificationService.showCaffeineWarningIfNeeded(
      currentMg: todayTotal,
      threshold: sleepThresholdMg,
      hoursUntilSleep: hoursUntilSleep,
    );
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
          final confidence = ((result['confidence'] ?? 0) as num).toDouble();
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
    final confidence = ((result['confidence'] ?? 0) as num).toDouble();
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

  // 수동 입력 다이얼로그 (AI 기반 카페인 추정)
  void _showManualInputDialog(XFile? imageFile) {
    final nameController = TextEditingController();
    String selectedSizeType = 'cup'; // 'cup' 또는 'ml'
    String selectedCupSize = 'grande'; // short, tall, grande, venti, trenta
    final mlController = TextEditingController(text: '355');
    bool isEstimating = false;
    
    // 컵 사이즈별 용량 (ml)
    final cupSizes = {
      'short': 237,
      'tall': 355,
      'grande': 473,
      'venti': 591,
      'trenta': 887,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text('음료 추가', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  
                // 음료 이름 입력
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: '음료 이름',
                    hintText: '예: 스타벅스 아메리카노, 레드불',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[600]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.amber),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // 사이즈 타입 선택 (컵 / 용량 직접 입력)
                Text('사이즈 선택', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedSizeType = 'cup'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedSizeType == 'cup' ? Colors.amber : Colors.grey[700],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '컵 사이즈',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selectedSizeType == 'cup' ? Colors.black : Colors.white70,
                              fontWeight: selectedSizeType == 'cup' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedSizeType = 'ml'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedSizeType == 'ml' ? Colors.amber : Colors.grey[700],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '용량 직접 입력',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selectedSizeType == 'ml' ? Colors.black : Colors.white70,
                              fontWeight: selectedSizeType == 'ml' ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // 컵 사이즈 선택
                if (selectedSizeType == 'cup')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildCupSizeButton('Short', 'short', cupSizes['short']!, selectedCupSize, (size) {
                        setDialogState(() => selectedCupSize = size);
                      }),
                      _buildCupSizeButton('Tall', 'tall', cupSizes['tall']!, selectedCupSize, (size) {
                        setDialogState(() => selectedCupSize = size);
                      }),
                      _buildCupSizeButton('Grande', 'grande', cupSizes['grande']!, selectedCupSize, (size) {
                        setDialogState(() => selectedCupSize = size);
                      }),
                      _buildCupSizeButton('Venti', 'venti', cupSizes['venti']!, selectedCupSize, (size) {
                        setDialogState(() => selectedCupSize = size);
                      }),
                      _buildCupSizeButton('Trenta', 'trenta', cupSizes['trenta']!, selectedCupSize, (size) {
                        setDialogState(() => selectedCupSize = size);
                      }),
                    ],
                  ),
                
                // 용량 직접 입력
                if (selectedSizeType == 'ml')
                  TextField(
                    controller: mlController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '용량 (ml)',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      suffixText: 'ml',
                      suffixStyle: TextStyle(color: Colors.grey[500]),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[600]!),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.amber),
                      ),
                    ),
                  ),
                  
                const SizedBox(height: 8),
                Text(
                  '💡 AI가 음료와 사이즈를 분석하여 카페인량을 추정합니다',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: isEstimating ? null : () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('음료 이름을 입력해주세요')),
                  );
                  return;
                }
                
                setDialogState(() => isEstimating = true);
                
                try {
                  // AI에게 카페인 추정 요청
                  final result = await ApiService.estimateCaffeineByText(
                    name,
                    size: selectedSizeType == 'cup' ? selectedCupSize : null,
                    sizeML: selectedSizeType == 'ml' ? int.tryParse(mlController.text) : null,
                  );
                  
                  Navigator.pop(ctx);
                  
                  // 결과 확인 다이얼로그 표시
                  _showEstimationResultDialog(result);
                } catch (e) {
                  setDialogState(() => isEstimating = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('추정 실패: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: isEstimating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('추정하기', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
  
  // 컵 사이즈 버튼 위젯
  Widget _buildCupSizeButton(String label, String value, int ml, String current, Function(String) onTap) {
    final isSelected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.grey[700],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            Text(
              '${ml}ml',
              style: TextStyle(
                color: isSelected ? Colors.black54 : Colors.grey[500],
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // AI 추정 결과 확인 다이얼로그
  void _showEstimationResultDialog(Map<String, dynamic> result) {
    final drinkName = result['drink_name'] ?? '음료';
    final caffeineAmount = result['caffeine_amount'] ?? 100;
    final confidence = (result['confidence'] ?? 0.5) * 100;
    final description = result['description'] ?? '';
    final size = result['size'] ?? '';
    final sizeML = result['size_ml'] ?? 0;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            const Text('추정 완료', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 음료 이름
            Text(
              drinkName,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (size.isNotEmpty || sizeML > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  size.isNotEmpty ? '$size ($sizeML ml)' : '$sizeML ml',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
              ),
            const SizedBox(height: 16),
            
            // 카페인량
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$caffeineAmount',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    ' mg',
                    style: TextStyle(color: Colors.amber, fontSize: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // 신뢰도
            Row(
              children: [
                Text('AI 신뢰도: ', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                Text(
                  '${confidence.toInt()}%',
                  style: TextStyle(
                    color: confidence >= 70 ? Colors.green : (confidence >= 40 ? Colors.orange : Colors.red),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  description,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
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
              Navigator.pop(ctx);
              _onDrink(caffeineAmount, name: drinkName);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('추가하기', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // 섭취 기록 수정/삭제 다이얼로그
  void _showLogEditDialog(Map<String, dynamic> log) {
    final logId = log['ID'] ?? log['id'];
    // 원래 양과 현재 비율 사용
    final originalAmount = ((log['original_amount'] ?? log['amount'] ?? 0) as num).toDouble();
    final currentRatio = ((log['consumed_ratio'] ?? 1) as num).toDouble();
    final drinkName = log['drink_name'] ?? 'Coffee';
    // 5% 단위로 반올림하여 슬라이더와 동기화
    double selectedRatio = (currentRatio * 20).round() / 20;
    
    // 원래 시간 파싱
    DateTime originalTime = DateTime.now();
    if (log['intake_at'] != null) {
      originalTime = DateTime.parse(log['intake_at']).toLocal();
    }
    DateTime selectedTime = originalTime;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: Text(drinkName, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 시간 선택
              GestureDetector(
                onTap: () async {
                  // 날짜 선택
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: selectedTime,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Colors.amber,
                            surface: Color(0xFF303030),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (pickedDate != null) {
                    // 시간 선택
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedTime),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Colors.amber,
                              surface: Color(0xFF303030),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (pickedTime != null) {
                      setDialogState(() {
                        selectedTime = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selectedTime != originalTime ? Colors.amber : Colors.grey[600]!,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        color: selectedTime != originalTime ? Colors.amber : Colors.grey[400],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('MM/dd HH:mm').format(selectedTime),
                        style: TextStyle(
                          color: selectedTime != originalTime ? Colors.amber : Colors.white,
                          fontSize: 16,
                          fontWeight: selectedTime != originalTime ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (selectedTime != originalTime)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.edit, color: Colors.amber, size: 16),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // 현재 카페인량 표시
              Text(
                '${(originalAmount * selectedRatio).toInt()} mg',
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
                '실제로 마신 양: ${(selectedRatio * 100).round()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Slider(
                value: (selectedRatio * 20).round() / 20,  // 5% 단위로 반올림
                min: 0.0,
                max: 1.0,
                divisions: 20,
                activeColor: Colors.amber,
                inactiveColor: Colors.grey[700],
                label: '${(selectedRatio * 100).round()}%',
                onChanged: (value) {
                  setDialogState(() {
                    selectedRatio = value;
                  });
                },
              ),
              
              // 빠른 선택 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPercentButton('25%', 0.25, selectedRatio, (p) {
                    setDialogState(() => selectedRatio = p);
                  }),
                  _buildPercentButton('50%', 0.5, selectedRatio, (p) {
                    setDialogState(() => selectedRatio = p);
                  }),
                  _buildPercentButton('75%', 0.75, selectedRatio, (p) {
                    setDialogState(() => selectedRatio = p);
                  }),
                  _buildPercentButton('100%', 1.0, selectedRatio, (p) {
                    setDialogState(() => selectedRatio = p);
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
              onPressed: ((selectedRatio - currentRatio).abs() > 0.01 || selectedTime != originalTime)
                  ? () async {
                      Navigator.pop(ctx);
                      await _updateLog(
                        logId, 
                        selectedRatio,
                        newTime: selectedTime != originalTime ? selectedTime : null,
                      );
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
  Future<void> _updateLog(int logId, double ratio, {DateTime? newTime}) async {
    try {
      // 항상 ratio 전달 (100%로 되돌리는 경우도 포함)
      await ApiService.updateLog(logId, ratio: ratio, drankAt: newTime);
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

  // 오늘 총 섭취량 계산
  int _getTodayTotalIntake() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    
    int total = 0;
    for (final log in logs) {
      final intakeAt = DateTime.parse(log['intake_at']).toLocal();
      if (intakeAt.isAfter(todayStart)) {
        final amount = (log['amount'] ?? 0) as int;
        final ratio = (log['consumed_ratio'] ?? 1.0) as double;
        total += (amount * ratio).round();
      }
    }
    return total;
  }
  
  // 수면 전까지 더 마실 수 있는 카페인량 계산
  int _getAvailableCaffeineBeforeSleep() {
    final now = DateTime.now();
    
    // 오늘 수면 목표 시간
    DateTime targetBedtime = DateTime(now.year, now.month, now.day, bedtime.hour, bedtime.minute);
    if (targetBedtime.isBefore(now)) {
      // 이미 수면 시간이 지났으면 내일로
      targetBedtime = targetBedtime.add(const Duration(days: 1));
    }
    
    // 수면까지 남은 시간
    final hoursUntilSleep = targetBedtime.difference(now).inMinutes / 60.0;
    
    if (hoursUntilSleep <= 0) return 0;
    
    // 현재 체내량이 수면 기준보다 많으면 더 마시면 안됨
    if (currentMg >= sleepThresholdMg) return 0;
    
    // 수면 시간에 sleepThresholdMg 이하가 되려면 지금 얼마까지 마셔도 되는지 계산
    // 반감기 공식: 남은량 = 초기량 * 0.5^(t/halfLife)
    // sleepThresholdMg = (currentMg + X) * 0.5^(hoursUntilSleep/halfLife)
    // X = sleepThresholdMg / 0.5^(hoursUntilSleep/halfLife) - currentMg
    
    final decayFactor = pow(0.5, hoursUntilSleep / halfLife);
    final maxAllowedNow = sleepThresholdMg / decayFactor;
    final available = maxAllowedNow - currentMg;
    
    return available > 0 ? available.round() : 0;
  }

  // 로그아웃
  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 테마별 색상 정의
    final bgColor = isDark ? Colors.grey[900]! : const Color.fromARGB(255, 240, 223, 204);
    final cardColor = isDark ? Colors.grey[850]! : const Color.fromARGB(255, 250, 230, 206);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final dividerColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    
    return Stack(
      children: [
        Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: Text(
              '안녕, ${AuthService.currentUser?['nickname'] ?? 'Caffy'} ☕️',
              style: TextStyle(color: textColor),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            actions: [
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: textColor,
                ),
                onPressed: () {
                  MyApp.setThemeMode(context, !isDark);
                },
                tooltip: isDark ? '라이트 모드' : '다크 모드',
              ),
              IconButton(
                icon: Icon(Icons.logout, color: textColor),
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
              style: TextStyle(color: subTextColor, fontSize: 14),
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
              style: TextStyle(color: subTextColor, fontSize: 14),
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPeriodButton(context, 1, '1일'),
                  const SizedBox(width: 6),
                  _buildPeriodButton(context, 3, '3일'),
                  const SizedBox(width: 6),
                  _buildPeriodButton(context, 7, '1주'),
                  const SizedBox(width: 6),
                  _buildPeriodButton(context, 14, '2주'),
                  const SizedBox(width: 6),
                  _buildPeriodButton(context, 30, '한달'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2. 그래프 영역 (fl_chart) - 기간별 과거/미래 표시
            Stack(
              children: [
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
                      
                      // 오프셋 제한 (과거/미래 범위 내에서만)
                      _graphOffset = _clampOffset(_graphOffset);
                    });
                  },
                  child: SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: true,
                          horizontalInterval: _getDynamicMaxY() / 6,
                          verticalInterval: _getGraphInterval(),
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: dividerColor,
                            strokeWidth: 1,
                          ),
                          getDrawingVerticalLine: (value) => FlLine(
                            color: dividerColor,
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
                                    style: TextStyle(color: subTextColor, fontSize: 9),
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
                                  style: TextStyle(color: subTextColor, fontSize: 9),
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
                            // 수면 권장 라인 (sleepThresholdMg 이하)
                            HorizontalLine(
                              y: sleepThresholdMg.toDouble(),
                              color: Colors.green.withOpacity(0.7),
                              strokeWidth: 2,
                              dashArray: [8, 4],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                style: const TextStyle(color: Colors.green, fontSize: 10),
                                labelResolver: (line) => '수면 권장 ${sleepThresholdMg}mg',
                              ),
                            ),
                          ],
                          verticalLines: [
                            // 수면 시간 라인
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
                                  labelResolver: (line) => '${_formatBedtime()} 수면',
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
                // 줌 컨트롤 (그래프 상단 우측)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildZoomButton(
                        Icons.remove, 
                        () {
                          setState(() {
                            _graphZoomLevel = (_graphZoomLevel / 2).clamp(_minZoom, _maxZoom);
                          });
                        },
                        enabled: _graphZoomLevel > _minZoom,
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _getZoomLabel(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildZoomButton(
                        Icons.add, 
                        () {
                          setState(() {
                            _graphZoomLevel = (_graphZoomLevel * 2).clamp(_minZoom, _maxZoom);
                          });
                        },
                        enabled: _graphZoomLevel < _maxZoom,
                      ),
                      const SizedBox(width: 4),
                      _buildZoomButton(Icons.refresh, () {
                        setState(() {
                          _graphZoomLevel = 1.0;
                          _graphOffset = 0.0;
                        });
                      }),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. 최근 섭취 기록 - 좌우 스크롤 카드 형태
            Text(
              '최근 섭취 기록',
              style: TextStyle(color: subTextColor, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 130,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        '아직 기록이 없어요 ☕️',
                        style: TextStyle(color: subTextColor),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      itemCount: logs.length > 20 ? 20 : logs.length,
                      itemBuilder: (ctx, i) {
                        final log = logs[i];
                        final intakeAt = DateTime.parse(log['intake_at']).toLocal();
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
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: isDark ? null : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
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
                                    style: TextStyle(
                                      color: textColor,
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
                                    color: subTextColor,
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
            const SizedBox(height: 12),
            
            // 4. 추가 버튼들 (사진/갤러리/직접)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAddButton(context, '카메라', Icons.camera_alt, () => _pickImageAndRecognize(ImageSource.camera)),
                _buildAddButton(context, '갤러리', Icons.photo_library, () => _pickImageAndRecognize(ImageSource.gallery)),
                _buildAddButton(context, '직접 입력', Icons.edit, () => _showManualInputDialog(null)),
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

  // 기간별 X축 범위 설정 (과거 + 미래 48시간)
  double _getBaseRange() {
    // 과거 시간 (기간별)
    double pastHours;
    switch (viewPeriodDays) {
      case 1: pastHours = 24; break;
      case 3: pastHours = 72; break;
      case 7: pastHours = 168; break; // 7일
      case 14: pastHours = 336; break; // 14일
      case 30: pastHours = 720; break; // 30일
      default: pastHours = 168;
    }
    
    return pastHours + _getFutureHours();
  }
  
  // 미래 최대값 (48시간 = 2일)
  double _getFutureHours() {
    return 48.0; // 2일 후까지 예측 가능
  }

  double _getMinX() {
    final visibleRange = _getBaseRange() / _graphZoomLevel;
    final clampedOffset = _clampOffset(_graphOffset);
    final minX = -visibleRange / 2 + clampedOffset;
    // 과거 제한 (선택한 기간만큼)
    final pastHours = _getBaseRange() - _getFutureHours();
    return max(minX, -pastHours);
  }

  double _getMaxX() {
    final visibleRange = _getBaseRange() / _graphZoomLevel;
    final clampedOffset = _clampOffset(_graphOffset);
    final maxX = visibleRange / 2 + clampedOffset;
    // 미래 48시간을 넘지 않도록 제한
    return min(maxX, _getFutureHours());
  }
  
  // 오프셋 제한 (과거는 무제한, 미래는 최대 48시간까지만)
  double _clampOffset(double offset) {
    final futureHours = _getFutureHours();
    final pastHours = _getBaseRange() - futureHours;
    final visibleRange = _getBaseRange() / _graphZoomLevel;
    
    // 최대로 갈 수 있는 왼쪽(과거) 오프셋
    double minOffset = -pastHours + visibleRange / 2;
    // 최대로 갈 수 있는 오른쪽(미래) 오프셋
    double maxOffset = futureHours - visibleRange / 2;
    
    // visibleRange가 전체 범위보다 클 경우 중앙에 고정
    if (minOffset > maxOffset) {
      return 0.0;
    }
    
    return offset.clamp(minOffset, maxOffset);
  }

  double _getGraphInterval() {
    double baseInterval;
    switch (viewPeriodDays) {
      case 1: baseInterval = 6; break; // 6시간 간격
      case 3: baseInterval = 12; break; // 12시간 간격
      case 7: baseInterval = 24; break; // 24시간 간격
      case 14: baseInterval = 48; break; // 2일 간격
      case 30: baseInterval = 96; break; // 4일 간격
      default: baseInterval = 24;
    }
    // 줌인하면 간격도 좁아짐
    double interval = baseInterval / _graphZoomLevel;
    // 최소 0.5시간(30분) 간격까지 허용, 깔끔한 값으로 스냅
    if (interval < 0.5) return 0.5;
    if (interval < 1) return 1;
    if (interval < 2) return 2;
    if (interval < 3) return 3;
    if (interval < 6) return 6;
    if (interval < 12) return 12;
    return 24;
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
    final minutes = ((value - hours) * 60).round();
    final now = DateTime.now();
    final targetTime = now.add(Duration(hours: hours, minutes: minutes));
    
    final interval = _getGraphInterval();
    
    if (interval <= 1) {
      // 1시간 이하 간격: 시간:분 표시
      return '${targetTime.hour}:${targetTime.minute.toString().padLeft(2, '0')}';
    } else if (interval <= 6 || viewPeriodDays == 1) {
      // 6시간 이하 간격 또는 1일 보기: 시간만 표시
      return '${targetTime.hour}시';
    } else {
      // 그 외: 날짜/시간
      if (hours == 0) return '지금';
      return '${targetTime.month}/${targetTime.day}';
    }
  }

  // 수면시간까지 남은 시간 계산
  double _getHoursUntilBedtime() {
    final now = DateTime.now();
    final bedtimeDateTime = DateTime(now.year, now.month, now.day, bedtime.hour, bedtime.minute);
    
    if (now.isAfter(bedtimeDateTime)) {
      // 이미 수면 시간이 지났으면 다음날
      final tomorrowBedtime = bedtimeDateTime.add(const Duration(days: 1));
      return tomorrowBedtime.difference(now).inMinutes / 60.0;
    }
    return bedtimeDateTime.difference(now).inMinutes / 60.0;
  }

  // 수면 시간에 sleepThresholdMg 이하가 되려면 지금 최대 얼마나 섭취 가능한지 계산
  int _getMaxAllowedIntake() {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    if (hoursUntilBedtime <= 0) return 0;
    
    // 수면 시간에 sleepThresholdMg가 되려면 현재 얼마까지 가능한가
    final maxTotalAtNow = sleepThresholdMg * pow(2, hoursUntilBedtime / halfLife);
    final maxAdditional = maxTotalAtNow - currentMg;
    
    return max(0, maxAdditional.toInt());
  }

  // 수면 시간에 예상되는 카페인량
  int _getCaffeineAtBedtime() {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    return (currentMg * pow(0.5, hoursUntilBedtime / halfLife)).toInt();
  }

  // 수면 시간 설정 다이얼로그 (TimePicker 사용)
  void _showBedtimeSettingDialog() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: bedtime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber,
              surface: Color(0xFF303030),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() => bedtime = picked);
    }
  }

  // 수면 기준 카페인량 설정 다이얼로그
  void _showSleepThresholdDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('수면 기준 카페인량', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '수면에 영향 없는 카페인량을 설정하세요',
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (int mg in [25, 50, 75, 100])
                  GestureDetector(
                    onTap: () {
                      setState(() => sleepThresholdMg = mg);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: 70,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: sleepThresholdMg == mg ? Colors.amber : Colors.grey[700],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$mg mg',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: sleepThresholdMg == mg ? Colors.black : Colors.white,
                          fontWeight: sleepThresholdMg == mg ? FontWeight.bold : FontWeight.normal,
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

  // 수면 시간 포맷
  String _formatBedtime() {
    final hour = bedtime.hour.toString().padLeft(2, '0');
    final minute = bedtime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // 수면 권장 대시보드 카드
  Widget _buildSleepRecommendationCard() {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    final caffeineAtBedtime = _getCaffeineAtBedtime();
    final maxAllowed = _getMaxAllowedIntake();
    final isSafe = caffeineAtBedtime <= sleepThresholdMg;
    
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
                      '${_formatBedtime()} 수면 기준',
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
                    '${_formatBedtime()} 예상량',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey[700],
              ),
              // 수면 기준량 (클릭해서 변경 가능)
              GestureDetector(
                onTap: _showSleepThresholdDialog,
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$sleepThresholdMg mg',
                          style: TextStyle(
                            color: Colors.green[300],
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.edit, color: Colors.grey[600], size: 14),
                      ],
                    ),
                    Text(
                      '수면 기준량',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
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

  Widget _buildAddButton(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    final isDark = MyApp.isDarkMode(context);
    final buttonColor = isDark ? Colors.grey[800] : Colors.grey[200];
    final borderColor = isDark ? Colors.grey[600]! : Colors.grey[400]!;
    final textColor = isDark ? Colors.white70 : Colors.black87;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 95,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.amber, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodButton(BuildContext context, int days, String label) {
    final isDark = MyApp.isDarkMode(context);
    final isSelected = viewPeriodDays == days;
    final buttonColor = isSelected ? Colors.amber : (isDark ? Colors.grey[800] : Colors.grey[200]);
    final borderColor = isSelected ? Colors.amber : (isDark ? Colors.grey[600]! : Colors.grey[400]!);
    final textColor = isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black87);
    
    return GestureDetector(
      onTap: () => _changeViewPeriod(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 줌 버튼 위젯
  Widget _buildZoomButton(IconData icon, VoidCallback? onTap, {bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: enabled ? Colors.orange.withOpacity(0.8) : Colors.grey.withOpacity(0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: enabled ? Colors.white : Colors.grey, size: 14),
      ),
    );
  }

  // 줌 레벨 라벨
  String _getZoomLabel() {
    final interval = _getGraphInterval();
    if (interval <= 0.5) return '30분';
    if (interval <= 1) return '1시간';
    if (interval <= 2) return '2시간';
    if (interval <= 3) return '3시간';
    if (interval <= 6) return '6시간';
    return '12시간';
  }
}