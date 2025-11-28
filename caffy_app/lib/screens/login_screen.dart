import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLoginMode = true; // true: 로그인, false: 회원가입
  String? _errorMessage;

  // 회원가입 추가 필드
  final _nicknameController = TextEditingController();
  final _weightController = TextEditingController(text: '70');
  final _heightController = TextEditingController(text: '170');
  int _gender = 0; // 0: 남성, 1: 여성
  bool _isSmoker = false;
  bool _isPregnant = false;
  int _exercisePerWeek = 3;
  int _metabolismType = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLoginMode) {
        await AuthService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await AuthService.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          nickname: _nicknameController.text.trim(),
          weight: double.tryParse(_weightController.text) ?? 70,
          height: double.tryParse(_heightController.text) ?? 170,
          gender: _gender,
          isSmoker: _isSmoker,
          isPregnant: _isPregnant,
          exercisePerWeek: _exercisePerWeek,
          metabolismType: _metabolismType,
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 로고/타이틀
                  const Text(
                    '☕️ Caffy',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLoginMode ? '로그인' : '회원가입',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.grey[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // 에러 메시지
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // 이메일
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('이메일', Icons.email),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '이메일을 입력하세요';
                      }
                      if (!value.contains('@')) {
                        return '올바른 이메일 형식이 아닙니다';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // 비밀번호
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration('비밀번호', Icons.lock),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '비밀번호를 입력하세요';
                      }
                      if (value.length < 6) {
                        return '비밀번호는 6자 이상이어야 합니다';
                      }
                      return null;
                    },
                  ),

                  // 회원가입 추가 필드
                  if (!_isLoginMode) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nicknameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('닉네임', Icons.person),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '닉네임을 입력하세요';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // 성별
                    DropdownButtonFormField<int>(
                      initialValue: _gender,
                      dropdownColor: Colors.grey[800],
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('성별', Icons.wc),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('남성')),
                        DropdownMenuItem(value: 1, child: Text('여성')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _gender = value ?? 0;
                          if (_gender == 0) _isPregnant = false;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // 키와 체중 (가로 배치)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('키 (cm)', Icons.height),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration('체중 (kg)', Icons.monitor_weight),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // 흡연 여부
                    SwitchListTile(
                      title: const Text('흡연자', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '흡연은 카페인 대사를 빠르게 합니다',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                      value: _isSmoker,
                      activeThumbColor: Colors.amber,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) => setState(() => _isSmoker = value),
                    ),
                    
                    // 임신 여부 (여성만)
                    if (_gender == 1)
                      SwitchListTile(
                        title: const Text('임신 중', style: TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '임신 중에는 카페인 대사가 느려집니다',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                        value: _isPregnant,
                        activeThumbColor: Colors.amber,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) => setState(() => _isPregnant = value),
                      ),
                    
                    const SizedBox(height: 8),
                    
                    // 주당 운동 횟수
                    Text('주당 운동 횟수: $_exercisePerWeek회',
                        style: const TextStyle(color: Colors.white)),
                    Slider(
                      value: _exercisePerWeek.toDouble(),
                      min: 0,
                      max: 7,
                      divisions: 7,
                      activeColor: Colors.amber,
                      label: '$_exercisePerWeek회',
                      onChanged: (value) => setState(() => _exercisePerWeek = value.toInt()),
                    ),
                    Text(
                      '운동은 카페인 대사에 영향을 줍니다',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    
                    // 대사 유형
                    DropdownButtonFormField<int>(
                      initialValue: _metabolismType,
                      dropdownColor: Colors.grey[800],
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('대사 유형', Icons.speed),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('보통 (반감기 5시간)')),
                        DropdownMenuItem(value: 1, child: Text('빠름 (반감기 3시간)')),
                        DropdownMenuItem(value: 2, child: Text('느림 (반감기 8시간)')),
                      ],
                      onChanged: (value) {
                        setState(() => _metabolismType = value ?? 0);
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 제출 버튼
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            _isLoginMode ? '로그인' : '회원가입',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),

                  const SizedBox(height: 16),

                  // 모드 전환
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLoginMode = !_isLoginMode;
                        _errorMessage = null;
                      });
                    },
                    child: Text(
                      _isLoginMode
                          ? '계정이 없으신가요? 회원가입'
                          : '이미 계정이 있으신가요? 로그인',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[400]),
      prefixIcon: Icon(icon, color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.grey[800],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.amber),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }
}
