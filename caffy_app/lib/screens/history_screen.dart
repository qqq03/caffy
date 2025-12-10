import 'package:caffy_app/main.dart';
import 'package:caffy_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:caffy_app/config/theme_colors.dart';

class HistoryScreen extends StatefulWidget {
  final List<dynamic> logs; // HomeScreen에서 전달받은 초기 로그 (최근 30일)
  final Function(dynamic) onEditLog;
  final Function() onRefresh;

  const HistoryScreen({
    super.key,
    required this.logs,
    required this.onEditLog,
    required this.onRefresh,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isGridView = false; // false: List, true: Grid
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  
  // 로컬 로그 데이터 (월별 조회 시 업데이트됨)
  List<dynamic> _currentLogs = [];
  bool _isLoading = false;
  
  // 월별 데이터 캐시
  final Map<String, List<dynamic>> _monthlyCache = {};

  @override
  void initState() {
    super.initState();
    // 초기 데이터는 props로 받은 logs 사용
    _currentLogs = widget.logs;
    
    // 현재 달의 데이터를 캐시에 저장 (초기값)
    final now = DateTime.now();
    _monthlyCache['${now.year}-${now.month}'] = widget.logs;
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 부모로부터 새로운 로그가 들어오면 업데이트
    if (widget.logs != oldWidget.logs) {
      final now = DateTime.now();
      // 최신 데이터로 캐시 업데이트
      _monthlyCache['${now.year}-${now.month}'] = widget.logs;
      
      // 현재 보고 있는 달이 이번 달이면 화면도 갱신
      if (_focusedDay.year == now.year && _focusedDay.month == now.month) {
        setState(() {
          _currentLogs = widget.logs;
        });
      }
    }
  }

  // 월 변경 시 데이터 페치
  Future<void> _fetchMonthlyLogs(DateTime focusedDay) async {
    final key = '${focusedDay.year}-${focusedDay.month}';
    
    // 캐시에 있으면 사용
    if (_monthlyCache.containsKey(key)) {
      setState(() {
        _currentLogs = _monthlyCache[key]!;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final logs = await ApiService.getMyLogs(
        year: focusedDay.year,
        month: focusedDay.month,
      );
      
      // 캐시에 저장
      _monthlyCache[key] = logs;
      
      if (mounted) {
        setState(() {
          _currentLogs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
    }
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    return _currentLogs.where((log) {
      final intakeAt = DateTime.parse(log['intake_at']).toLocal();
      return isSameDay(intakeAt, day);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = MyApp.isDarkMode(context);
    final textColor = isDark ? ThemeColors.blackTextPrimary : ThemeColors.ivoryTextPrimary;
    final subTextColor = isDark ? ThemeColors.blackTextSecondary : ThemeColors.ivoryTextSecondary;
    final cardColor = isDark ? ThemeColors.blackSurface : ThemeColors.ivorySurface;

    // Filter logs based on CalendarFormat
    final filteredLogs = _currentLogs.where((log) {
      final intakeAt = DateTime.parse(log['intake_at']).toLocal();
      
      if (_calendarFormat == CalendarFormat.month) {
        // Month view: Show logs for the focused month
        return intakeAt.year == _focusedDay.year && 
               intakeAt.month == _focusedDay.month;
      } else if (_calendarFormat == CalendarFormat.twoWeeks) {
        // 2 Weeks view: Show logs for the 2 weeks range around focused day
        // TableCalendar's 2 weeks logic is complex, let's approximate:
        // Show 14 days starting from the beginning of the focused week
        final diff = _focusedDay.weekday - 1;
        final startOfWeek = DateTime(_focusedDay.year, _focusedDay.month, _focusedDay.day - diff);
        final endOfRange = startOfWeek.add(const Duration(days: 14));
        
        return intakeAt.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
               intakeAt.isBefore(endOfRange);
      } else {
        // Week view: Show logs for the focused week
        final diff = _focusedDay.weekday - 1;
        final startOfWeek = DateTime(_focusedDay.year, _focusedDay.month, _focusedDay.day - diff);
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        
        return intakeAt.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
               intakeAt.isBefore(endOfWeek);
      }
    }).toList();

    // Sort logs by date (latest first)
    filteredLogs.sort((a, b) {
      final dateA = DateTime.parse(a['intake_at']);
      final dateB = DateTime.parse(b['intake_at']);
      return dateB.compareTo(dateA);
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          // 캐시 삭제 (강제 새로고침)
          _monthlyCache.remove('${_focusedDay.year}-${_focusedDay.month}');
          
          // 현재 보고 있는 달의 데이터 다시 로드
          await _fetchMonthlyLogs(_focusedDay);
          widget.onRefresh(); // 부모 상태도 갱신
        },
        child: Column(
          children: [
            // Calendar
            Container(
              color: isDark ? ThemeColors.blackBackground : ThemeColors.ivoryBackground,
              padding: const EdgeInsets.only(bottom: 8),
              child: TableCalendar(
                firstDay: DateTime(2020),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                eventLoader: _getEventsForDay,
                availableCalendarFormats: const {
                  CalendarFormat.month: '한달',
                  CalendarFormat.twoWeeks: '2주',
                  CalendarFormat.week: '1주',
                },
                selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDate = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  // 달이 바뀌었는지 체크
                  if (focusedDay.month != _focusedDay.month || focusedDay.year != _focusedDay.year) {
                    _fetchMonthlyLogs(focusedDay);
                  }
                  setState(() {
                    _focusedDay = focusedDay;
                  });
                },
                calendarStyle: CalendarStyle(
                  selectedDecoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  defaultTextStyle: TextStyle(color: textColor),
                  weekendTextStyle: TextStyle(color: Colors.red[300]),
                  outsideTextStyle: TextStyle(color: Colors.grey[600]),
                  markerDecoration: const BoxDecoration(
                    color: Colors.brown,
                    shape: BoxShape.circle,
                  ),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: true,
                  titleCentered: true,
                  formatButtonShowsNext: false,
                  formatButtonDecoration: BoxDecoration(
                    border: Border.all(color: textColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  formatButtonTextStyle: TextStyle(color: textColor),
                  titleTextStyle: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
                  leftChevronIcon: Icon(Icons.chevron_left, color: textColor),
                  rightChevronIcon: Icon(Icons.chevron_right, color: textColor),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      _isGridView ? Icons.list : Icons.grid_view,
                      color: textColor,
                    ),
                    onPressed: () {
                      setState(() {
                        _isGridView = !_isGridView;
                      });
                    },
                    tooltip: _isGridView ? '리스트 보기' : '그리드 보기',
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Text(
                        '기록이 없어요 ☕️',
                        style: TextStyle(color: subTextColor),
                      ),
                    )
                  : _isGridView
                      ? GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: filteredLogs.length,
                          itemBuilder: (ctx, i) => _buildGridItem(filteredLogs[i], cardColor, textColor, subTextColor),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredLogs.length,
                          itemBuilder: (ctx, i) => _buildListItem(filteredLogs[i], cardColor, textColor, subTextColor),
                        ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildListItem(dynamic log, Color cardColor, Color textColor, Color subTextColor) {
    final intakeAt = DateTime.parse(log['intake_at']).toLocal();
    final timeStr = DateFormat('yyyy.MM.dd HH:mm').format(intakeAt);
    final drinkName = log['drink_name'] ?? 'Coffee';
    final amount = log['amount'] ?? 0;

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.coffee, color: Colors.amber),
        ),
        title: Text(
          drinkName,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          timeStr,
          style: TextStyle(color: subTextColor, fontSize: 12),
        ),
        trailing: Text(
          '${amount}mg',
          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        onTap: () => widget.onEditLog(log),
      ),
    );
  }

  Widget _buildGridItem(dynamic log, Color cardColor, Color textColor, Color subTextColor) {
    final intakeAt = DateTime.parse(log['intake_at']).toLocal();
    final timeStr = DateFormat('MM/dd\nHH:mm').format(intakeAt);
    final drinkName = log['drink_name'] ?? 'Coffee';
    final amount = log['amount'] ?? 0;

    return GestureDetector(
      onTap: () => widget.onEditLog(log),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.coffee, color: Colors.amber, size: 24),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                drinkName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${amount}mg',
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: subTextColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
