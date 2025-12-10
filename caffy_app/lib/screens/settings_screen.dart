import 'package:caffy_app/main.dart';
import 'package:caffy_app/services/api_service.dart';
import 'package:caffy_app/services/auth_service.dart';
import 'package:caffy_app/screens/login_screen.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final TimeOfDay bedtime;
  final TimeOfDay wakeUpTime;
  final int sleepThresholdMg;
  final Function(TimeOfDay) onBedtimeChanged;
  final Function(TimeOfDay) onWakeUpTimeChanged;
  final Function(int) onSleepThresholdChanged;

  const SettingsScreen({
    super.key,
    required this.bedtime,
    required this.wakeUpTime,
    required this.sleepThresholdMg,
    required this.onBedtimeChanged,
    required this.onWakeUpTimeChanged,
    required this.onSleepThresholdChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _userProfile;

  // Controllers
  final _nicknameController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _sleepThresholdController = TextEditingController();
  int _gender = 0;
  bool _isSmoker = false;
  bool _isPregnant = false;
  int _exercisePerWeek = 0;
  int _metabolismType = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _sleepThresholdController.text = widget.sleepThresholdMg.toString();
    _sleepThresholdController.addListener(_onSleepThresholdChanged);
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sleepThresholdMg != oldWidget.sleepThresholdMg) {
      final val = int.tryParse(_sleepThresholdController.text);
      if (val != widget.sleepThresholdMg) {
        _sleepThresholdController.text = widget.sleepThresholdMg.toString();
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _sleepThresholdController.dispose();
    super.dispose();
  }

  void _onSleepThresholdChanged() {
    final val = int.tryParse(_sleepThresholdController.text);
    if (val != null) {
      widget.onSleepThresholdChanged(val);
    }
  }

  Future<void> _fetchUserProfile() async {
    setState(() => _isLoading = true);
    try {
      // AuthService.currentUser might be stale, but let's use it for initial display if available
      // Or fetch fresh data
      // Since we don't have a dedicated getUserProfile API other than getMe (which is used for auth check),
      // we can use AuthService.currentUser if it's updated.
      // But better to fetch fresh data.
      // Assuming ApiService.getMyStatus returns some info, but maybe not full profile.
      // Let's assume AuthService.currentUser is kept up to date or we can refresh it.
      // Actually, let's just use AuthService.currentUser for now as we don't have a separate getProfile API exposed in ApiService yet (except getMe which is internal to AuthService usually).
      // Wait, AuthService.tryAutoLogin calls getMe.
      // Let's add getMe to ApiService or just use AuthService.currentUser.
      
      // For now, I'll use AuthService.currentUser.
      final user = AuthService.currentUser;
      if (user != null) {
        _userProfile = user;
        _nicknameController.text = user['nickname'] ?? '';
        _weightController.text = (user['weight'] ?? 70).toString();
        _heightController.text = (user['height'] ?? 170).toString();
        _gender = user['gender'] ?? 0;
        _isSmoker = user['is_smoker'] ?? false;
        _isPregnant = user['is_pregnant'] ?? false;
        _exercisePerWeek = user['exercise_per_week'] ?? 0;
        _metabolismType = user['metabolism_type'] ?? 0;
      }
    } catch (e) {
      print('Error fetching profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final updatedUser = await ApiService.updateProfile(
        nickname: _nicknameController.text,
        weight: double.tryParse(_weightController.text),
        height: double.tryParse(_heightController.text),
        gender: _gender,
        isSmoker: _isSmoker,
        isPregnant: _isPregnant,
        exercisePerWeek: _exercisePerWeek,
        metabolismType: _metabolismType,
      );
      
      // Update local user info if needed (AuthService should probably update its state)
      // But AuthService._currentUser is private.
      // We might need to re-login or just show success.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MyApp.isDarkMode(context);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    if (_isLoading && _userProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Theme Setting
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('화면 모드', style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
              subtitle: Text(isDark ? '다크 모드' : '라이트 모드', style: TextStyle(color: subTextColor)),
              trailing: Switch(
                value: isDark,
                activeColor: Colors.amber,
                onChanged: (value) {
                  MyApp.setThemeMode(value);
                },
              ),
            ),
            const Divider(height: 32),

            // Sleep Settings
            Text('수면 설정', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            // Bedtime
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('수면 시작 시간', style: TextStyle(color: textColor)),
              subtitle: Text('${widget.bedtime.hour.toString().padLeft(2, '0')}:${widget.bedtime.minute.toString().padLeft(2, '0')}', style: TextStyle(color: subTextColor)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () async {
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: widget.bedtime,
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
                  widget.onBedtimeChanged(picked);
                }
              },
            ),
            
            // Wake Up Time
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('기상 시간', style: TextStyle(color: textColor)),
              subtitle: Text('${widget.wakeUpTime.hour.toString().padLeft(2, '0')}:${widget.wakeUpTime.minute.toString().padLeft(2, '0')}', style: TextStyle(color: subTextColor)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () async {
                final TimeOfDay? picked = await showTimePicker(
                  context: context,
                  initialTime: widget.wakeUpTime,
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
                  widget.onWakeUpTimeChanged(picked);
                }
              },
            ),

            // Sleep Threshold
            const SizedBox(height: 12),
            _buildTextField('수면 기준 카페인량 (mg)', _sleepThresholdController, textColor, subTextColor, isNumber: true),
            const Divider(height: 32),

            Text('사용자 정보', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _buildTextField('닉네임', _nicknameController, textColor, subTextColor),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildTextField('체중 (kg)', _weightController, textColor, subTextColor, isNumber: true)),
                const SizedBox(width: 12),
                Expanded(child: _buildTextField('키 (cm)', _heightController, textColor, subTextColor, isNumber: true)),
              ],
            ),
            const SizedBox(height: 12),
            
            // Gender
            Text('성별', style: TextStyle(color: subTextColor, fontSize: 12)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<int>(
                    title: Text('남성', style: TextStyle(color: textColor)),
                    value: 0,
                    groupValue: _gender,
                    activeColor: Colors.amber,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _gender = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<int>(
                    title: Text('여성', style: TextStyle(color: textColor)),
                    value: 1,
                    groupValue: _gender,
                    activeColor: Colors.amber,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _gender = val!),
                  ),
                ),
              ],
            ),

            // Smoker
            SwitchListTile(
              title: Text('흡연 여부', style: TextStyle(color: textColor)),
              value: _isSmoker,
              activeColor: Colors.amber,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) => setState(() => _isSmoker = val),
            ),

            // Pregnant (only for female)
            if (_gender == 1)
              SwitchListTile(
                title: Text('임신 여부', style: TextStyle(color: textColor)),
                value: _isPregnant,
                activeColor: Colors.amber,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _isPregnant = val),
              ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('저장하기', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 32),
            Center(
              child: TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('로그아웃', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, Color textColor, Color subTextColor, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: subTextColor),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: subTextColor),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.amber),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
