import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:caffy_app/main.dart';
import 'package:caffy_app/services/api_service.dart';
import 'package:caffy_app/screens/status_screen.dart';
import 'package:caffy_app/screens/history_screen.dart';
import 'package:caffy_app/screens/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:caffy_app/config/theme_colors.dart';
import 'package:caffy_app/utils/caffeine_calculator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Data State
  int currentMg = 0;
  String statusMsg = "데이터 불러오는 중...";
  bool isLoading = true;
  bool isRecognizing = false;
  double halfLife = 5.0;
  int viewPeriodDays = 1; // 기본값: 1일 뷰, 6시간 간격
  List<dynamic> logs = [];
  List<dynamic> graphPoints = [];

  // Settings State
  TimeOfDay _bedtime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  int _sleepThresholdMg = 50;

  // Stream & Timer
  Timer? _refreshTimer;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchData();
    _startNotificationTimer();
    
    // 1분마다 데이터 갱신 (실시간 감쇠 반영 - 서버 통신 없이 로컬 계산)
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _recalculateLocal();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final hour = prefs.getInt('bedtime_hour') ?? 22;
      final minute = prefs.getInt('bedtime_minute') ?? 0;
      _bedtime = TimeOfDay(hour: hour, minute: minute);
      
      final wakeHour = prefs.getInt('wakeup_hour') ?? 7;
      final wakeMinute = prefs.getInt('wakeup_minute') ?? 0;
      _wakeUpTime = TimeOfDay(hour: wakeHour, minute: wakeMinute);

      _sleepThresholdMg = prefs.getInt('sleep_threshold') ?? 50;
    });
  }

  Future<void> _updateBedtime(TimeOfDay newTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bedtime_hour', newTime.hour);
    await prefs.setInt('bedtime_minute', newTime.minute);
    setState(() => _bedtime = newTime);
  }

  Future<void> _updateWakeUpTime(TimeOfDay newTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wakeup_hour', newTime.hour);
    await prefs.setInt('wakeup_minute', newTime.minute);
    setState(() => _wakeUpTime = newTime);
  }

  Future<void> _updateSleepThreshold(int newThreshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sleep_threshold', newThreshold);
    setState(() => _sleepThresholdMg = newThreshold);
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startNotificationTimer() {
    if (kIsWeb) return;
    _notificationTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      _setupAutoNotifications();
    });
  }

  Future<void> _setupAutoNotifications() async {
    // Implementation omitted for brevity
  }

  // 로컬 데이터로 화면 갱신 (서버 통신 X)
  void _recalculateLocal() {
    if (logs.isEmpty) return;
    
    final newCurrentMg = CaffeineCalculator.calculateTotalRemaining(logs, halfLife);
    final newGraphPoints = CaffeineCalculator.generateGraphPoints(logs, halfLife, viewPeriodDays);
    
    if (mounted) {
      setState(() {
        currentMg = newCurrentMg.round();
        graphPoints = newGraphPoints;
      });
    }
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);
    try {
      final data = await ApiService.getMyStatus();
      
      // 이제 getMyStatus가 logs를 포함함
      final logsData = data['logs'] ?? [];
      final hl = (data['half_life_used'] ?? 5.0).toDouble();
      final period = data['view_period_days'] ?? 7;

      // 프론트엔드에서 계산
      final calculatedMg = CaffeineCalculator.calculateTotalRemaining(logsData, hl);
      final calculatedGraph = CaffeineCalculator.generateGraphPoints(logsData, hl, period);
      
      if (mounted) {
        setState(() {
          currentMg = calculatedMg.round();
          statusMsg = data['status_message'] ?? '상태를 불러왔습니다';
          halfLife = hl;
          logs = logsData;
          graphPoints = calculatedGraph;
          viewPeriodDays = period;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          statusMsg = "데이터를 불러오지 못했습니다";
          isLoading = false;
        });
      }
    }
  }

  Future<void> _changeViewPeriod(int days) async {
    try {
      // 서버에 설정 저장 (데이터 리페치 안함)
      await ApiService.setViewPeriod(days);
      
      setState(() {
        viewPeriodDays = days;
      });
      
      // 로컬 데이터로 즉시 갱신
      _recalculateLocal();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('설정 변경 실패: $e')),
      );
    }
  }

  // Image Picking & Recognition
  Future<void> _pickImageAndRecognize(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, maxWidth: 800);
    
    if (image == null) return;

    setState(() => isRecognizing = true);

    try {
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final result = await ApiService.smartRecognizeDrink(base64Image);
      
      if (!mounted) return;
      setState(() => isRecognizing = false);
      
      _showDrinkConfirmationDialog(result, image);
    } catch (e) {
      if (!mounted) return;
      setState(() => isRecognizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인식 실패: $e')),
      );
      // 실패 시 수동 입력 유도
      _showManualInputDialog(image);
    }
  }

  void _showDrinkConfirmationDialog(Map<String, dynamic> result, XFile imageFile) {
    final drinkName = result['drink_name'] ?? '알 수 없는 음료';
    final caffeineAmount = result['caffeine_amount'] ?? 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('음료 인식 결과', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!kIsWeb)
              FutureBuilder<Uint8List>(
                future: imageFile.readAsBytes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Container(
                      height: 150,
                      width: double.infinity,
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
                  return const SizedBox.shrink();
                },
              ),
            Text(
              drinkName,
              style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$caffeineAmount mg',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showManualInputDialog(imageFile);
            },
            child: const Text('수정', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _onDrink(caffeineAmount, name: drinkName);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('마시기', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showManualInputDialog(XFile? imageFile) {
    final nameController = TextEditingController();
    final mlController = TextEditingController(text: '355');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[850],
          title: const Text('직접 입력', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '음료 이름',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: mlController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '용량 (ml)',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                
                try {
                  final result = await ApiService.estimateCaffeineByText(
                    name,
                    sizeML: int.tryParse(mlController.text),
                  );
                  Navigator.pop(ctx);
                  _showDrinkConfirmationDialog(result, imageFile ?? XFile('')); // Dummy XFile if null
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('추정 실패: $e')));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('추정하기', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDrink(dynamic amount, {String name = 'Coffee'}) async {
    try {
      await ApiService.drinkCoffee(name, (amount as num).toInt());
      _fetchData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name 마심! ☕️')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('기록 실패: $e')),
      );
    }
  }

  void _showLogEditDialog(dynamic log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('기록 관리', style: TextStyle(color: Colors.white)),
        content: Text('${log['drink_name']} (${log['amount']}mg)', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ApiService.deleteLog(log['ID']);
                Navigator.pop(ctx);
                _fetchData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MyApp.isDarkMode(context);
    final bgColor = isDark ? ThemeColors.blackBackground : ThemeColors.ivoryBackground;
    final textColor = isDark ? ThemeColors.blackTextPrimary : ThemeColors.ivoryTextPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _selectedIndex == 0 ? '상태' : (_selectedIndex == 1 ? '내역' : '설정'),
          style: TextStyle(color: textColor),
        ),
        // backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          StatusScreen(
            currentMg: currentMg,
            statusMsg: statusMsg,
            halfLife: halfLife,
            graphPoints: graphPoints,
            viewPeriodDays: viewPeriodDays,
            bedtime: _bedtime,
            wakeUpTime: _wakeUpTime,
            sleepThresholdMg: _sleepThresholdMg,
            onViewPeriodChanged: _changeViewPeriod,
            onRefresh: _fetchData,
            onAddCamera: () => _pickImageAndRecognize(ImageSource.camera),
            onAddGallery: () => _pickImageAndRecognize(ImageSource.gallery),
            onAddManual: () => _showManualInputDialog(null),
          ),
          HistoryScreen(
            logs: logs,
            onEditLog: _showLogEditDialog,
            onRefresh: _fetchData,
          ),
          SettingsScreen(
            bedtime: _bedtime,
            wakeUpTime: _wakeUpTime,
            sleepThresholdMg: _sleepThresholdMg,
            onBedtimeChanged: _updateBedtime,
            onWakeUpTimeChanged: _updateWakeUpTime,
            onSleepThresholdChanged: _updateSleepThreshold,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: isDark ? Colors.grey[850] : Colors.white,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '상태'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '내역'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
