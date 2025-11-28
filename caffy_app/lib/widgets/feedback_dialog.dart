import 'package:flutter/material.dart';
import '../services/learning_service.dart';

class FeedbackDialog extends StatefulWidget {
  final VoidCallback? onFeedbackSubmitted;
  
  const FeedbackDialog({super.key, this.onFeedbackSubmitted});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  int _senseLevel = 3;
  bool _isLoading = false;
  final _feelingController = TextEditingController();

  final List<Map<String, dynamic>> _levels = [
    {'level': 1, 'emoji': '😴', 'text': '매우 졸림'},
    {'level': 2, 'emoji': '🥱', 'text': '약간 졸림'},
    {'level': 3, 'emoji': '😐', 'text': '보통'},
    {'level': 4, 'emoji': '⚡', 'text': '각성'},
    {'level': 5, 'emoji': '🔥', 'text': '매우 각성'},
  ];

  Future<void> _submit() async {
    setState(() => _isLoading = true);

    try {
      await LearningService.submitFeedback(
        senseLevel: _senseLevel,
        actualFeeling: _feelingController.text,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ 피드백이 반영되었습니다! 학습에 활용됩니다.'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onFeedbackSubmitted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('피드백 제출 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '지금 어떠세요?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '피드백으로 나만의 카페인 곡선을 학습해요',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 24),

            // 레벨 선택 버튼들
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _levels.map((level) {
                final isSelected = _senseLevel == level['level'];
                return GestureDetector(
                  onTap: () => setState(() => _senseLevel = level['level']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.amber : Colors.grey[700],
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: Colors.amber, width: 2)
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          level['emoji'],
                          style: const TextStyle(fontSize: 28),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          level['text'],
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // 추가 메모 (선택)
            TextField(
              controller: _feelingController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '추가로 느끼는 것이 있다면... (선택)',
                hintStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 버튼들
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '취소',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                        : const Text('제출'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 피드백 다이얼로그 표시 함수
void showFeedbackDialog(BuildContext context, {VoidCallback? onFeedbackSubmitted}) {
  showDialog(
    context: context,
    builder: (context) => FeedbackDialog(onFeedbackSubmitted: onFeedbackSubmitted),
  );
}
