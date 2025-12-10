import 'dart:math';
import 'package:caffy_app/config/theme_colors.dart';
import 'package:caffy_app/main.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class StatusScreen extends StatefulWidget {
  final int currentMg;
  final String statusMsg;
  final double halfLife;
  final List<dynamic> graphPoints;

  final TimeOfDay bedtime;
  final TimeOfDay wakeUpTime;
  final int sleepThresholdMg;

  final Function(int) onViewPeriodChanged;
  final int viewPeriodDays;
  final Function() onRefresh;
  final Function() onAddCamera;
  final Function() onAddGallery;
  final Function() onAddManual;

  const StatusScreen({
    super.key,
    required this.currentMg,
    required this.statusMsg,
    required this.halfLife,
    required this.graphPoints,
    required this.bedtime,
    required this.wakeUpTime,
    required this.sleepThresholdMg,
    required this.onViewPeriodChanged,
    required this.viewPeriodDays,
    required this.onRefresh,
    required this.onAddCamera,
    required this.onAddGallery,
    required this.onAddManual,
  });

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  // 그래프 줌 레벨 (1.0 = 전체, 12.0 = 2시간 단위까지 확대)
  double _graphZoomLevel = 1.0;
  double _scrollOffset = 0.0; // 그래프 스크롤 오프셋
  static const double _minZoom = 1.0;
  static const double _maxZoom = 12.0; // 최대 2시간 간격까지 줌인

  @override
  Widget build(BuildContext context) {
    final isDark = MyApp.isDarkMode(context);
    // Dark mode background: Very dark grey/black (from image)
    final backgroundColor = isDark ? ThemeColors.blackBackground : ThemeColors.ivoryBackground;

    final currentMg = widget.currentMg;
    final statusMsg = widget.statusMsg;
    final halfLife = widget.halfLife;
    final graphPoints = widget.graphPoints;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // 스크롤 가능하도록 설정
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 상태 카드 (Top Card)
              _buildStatusCard(currentMg, statusMsg, halfLife),
              const SizedBox(height: 16),

              // 2. 그래프 카드 (Middle Card)
              _buildGraphCard(currentMg, graphPoints, halfLife),
              const SizedBox(height: 16),

              // 3. 액션 버튼 (Bottom Row)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildActionButton(context, '카메라', Icons.camera_alt, widget.onAddCamera),
                  _buildActionButton(context, '갤러리', Icons.photo_library, widget.onAddGallery),
                  _buildActionButton(context, '직접 입력', Icons.edit, widget.onAddManual),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // 1. 상태 카드
  Widget _buildStatusCard(int currentMg, String statusMsg, double halfLife) {
    final isDark = MyApp.isDarkMode(context);
    // Dark mode card: Dark grey (from image)
    final cardColor = isDark ? ThemeColors.blackSurface : ThemeColors.ivorySurface;
    final textColor = isDark ? ThemeColors.blackTextPrimary : ThemeColors.ivoryTextPrimary;

    final hoursUntilBedtime = _getHoursUntilBedtime();
    final maxAllowed = _getMaxAllowedIntake(currentMg, halfLife);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "$currentMg mg",
            style: TextStyle(
              color: isDark ? const Color(0xFFFFE0B2) : textColor, // Light orange in dark mode
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusMsg.isEmpty ? "🙂 카페인 효과가 사라졌습니다." : statusMsg,
            style: TextStyle(
              color: isDark ? Colors.grey[400] : const Color(0xFF8D6E63),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2E3B33) : const Color(0xFFE8F5E9), // Dark green bg in dark mode
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bedtime, size: 16, color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32)),
                    const SizedBox(width: 6),
                    Text(
                      "${_formatBedtime()} 수면 기준",
                      style: TextStyle(
                        color: isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "${hoursUntilBedtime.toStringAsFixed(1)}시간 후 / +$maxAllowed mg 가능",
                  style: TextStyle(
                    color: isDark ? const Color(0xFFA5D6A7) : const Color(0xFF388E3C),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. 그래프 카드
  Widget _buildGraphCard(int currentMg, List<dynamic> graphPoints, double halfLife) {
    final isDark = MyApp.isDarkMode(context);
    final cardColor = isDark ? ThemeColors.blackSurface : ThemeColors.ivorySurface;
    final dividerColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
    final subTextColor = isDark ? ThemeColors.blackTextSecondary : ThemeColors.ivoryTextSecondary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 기간 선택 (Segmented Control Style)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(child: _buildSegmentButton(1, '1일')),
                Expanded(child: _buildSegmentButton(7, '1주')),
                Expanded(child: _buildSegmentButton(30, '한달')),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 그래프
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onHorizontalDragUpdate: (details) {
                  final width = constraints.maxWidth;
                  final visibleRange = _getVisibleRange();
                  final hoursPerPixel = visibleRange / width;
                  
                  setState(() {
                    double newOffset = _scrollOffset - (details.primaryDelta! * hoursPerPixel);
                    
                    // 스크롤 범위 제한
                    final pastHours = _getBaseRange() - _getFutureHours();
                    final futureHours = _getFutureHours();
                    final halfVisible = visibleRange / 2;
                    
                    final minOffset = -pastHours + halfVisible;
                    final maxOffset = futureHours - halfVisible;
                    
                    if (minOffset <= maxOffset) {
                      _scrollOffset = newOffset.clamp(minOffset, maxOffset);
                    } else {
                      // 줌 아웃 상태라 전체가 다 보이는 경우
                      _scrollOffset = newOffset.clamp(maxOffset, minOffset); 
                    }
                  });
                },
                child: SizedBox(
                  height: 200,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: LineChart(
                      LineChartData(
                      rangeAnnotations: RangeAnnotations(
                        verticalRangeAnnotations: widget.viewPeriodDays == 1 ? _getSleepRanges() : [],
                      ),
                      extraLinesData: ExtraLinesData(
                        verticalLines: widget.viewPeriodDays == 1 ? _getSleepLabels() : [],
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              // barIndex 0: 수면 한계선 (초록), 1: 카페인 그래프 (주황)
                              final isLimit = spot.barIndex == 0;
                              final color = isLimit 
                                  ? Colors.green 
                                  : const Color(0xFFD87D4A);
                              final label = isLimit ? '추천량 : ' : '섭취량  : ';
                              
                              return LineTooltipItem(
                                '$label ${spot.y.toInt()}',
                                TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _getDynamicMaxY(currentMg, graphPoints, halfLife) / 5,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: dividerColor,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: _getGraphInterval(),
                            getTitlesWidget: _getBottomTitleWidget,
                          ),
                        ),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: _getMinX(),
                      maxX: _getMaxX(),
                      minY: 0,
                      maxY: _getDynamicMaxY(currentMg, graphPoints, halfLife),
                      lineBarsData: [
                        // 수면 한계선 (1일 뷰일 때만 표시)
                        if (widget.viewPeriodDays == 1)
                        LineChartBarData(
                          spots: _generateLimitSpots(halfLife, widget.bedtime, widget.sleepThresholdMg),
                          isCurved: true,
                          curveSmoothness: 0.3,
                          color: Colors.green.withOpacity(0.5),
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          dashArray: [5, 5], // 점선 효과
                          belowBarData: BarAreaData(show: false),
                        ),
                        // 실제 카페인 그래프
                        LineChartBarData(
                          spots: _generateSpots(currentMg, graphPoints, halfLife),
                          isCurved: true,
                          preventCurveOverShooting: true, // 그래프 딥 현상 방지
                          curveSmoothness: 0.2, // 곡선 부드러움 조정
                          color: const Color(0xFFD87D4A), // Darker orange for graph line
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFD87D4A).withOpacity(0.3),
                                const Color(0xFFD87D4A).withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            }
          ),
          const SizedBox(height: 16),

          // 줌 컨트롤
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildZoomIconButton(Icons.remove, () {
                  _handleZoomOut();
                }),
                const SizedBox(width: 16),
                _buildZoomIconButton(Icons.add, () {
                  _handleZoomIn();
                }),
                const SizedBox(width: 16),
                Text(
                  _getZoomLabel(),
                  style: TextStyle(
                    color: subTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
                _buildZoomIconButton(Icons.refresh, () {
                  setState(() {
                    _graphZoomLevel = 1.0;
                    _scrollOffset = 0.0;
                  });
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(int days, String label) {
    final isSelected = widget.viewPeriodDays == days;
    final isDark = MyApp.isDarkMode(context);
    
    return GestureDetector(
      onTap: () => widget.onViewPeriodChanged(days),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD87D4A) : Colors.transparent, // Orange accent
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? [
            BoxShadow(
              color: const Color(0xFFD87D4A).withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ] : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : (isDark ? Colors.grey[500] : Colors.grey[600]),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildZoomIconButton(IconData icon, VoidCallback onTap) {
    final isDark = MyApp.isDarkMode(context);
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 20,
        color: isDark ? Colors.grey[500] : Colors.grey[700],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    final isDark = MyApp.isDarkMode(context);
    final cardColor = isDark ? ThemeColors.blackSurface : ThemeColors.ivorySurface;
    final textColor = isDark ? ThemeColors.blackTextPrimary : ThemeColors.ivoryTextPrimary;
    final iconColor = isDark ? ThemeColors.primaryOrange : ThemeColors.ivoryTextPrimary; // Orange icon in dark mode

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 기간별 X축 범위 설정 (과거 + 미래 48시간)
  double _getBaseRange() {
    // 과거 시간 (기간별)
    double pastHours;
    switch (widget.viewPeriodDays) {
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

  double _getVisibleRange() {
    return _getBaseRange() / _graphZoomLevel;
  }

  double _getMinX() {
    final visibleRange = _getVisibleRange();
    return (-visibleRange / 2) + _scrollOffset;
  }

  double _getMaxX() {
    final visibleRange = _getVisibleRange();
    return (visibleRange / 2) + _scrollOffset;
  }

  void _clampOffset() {
    final visibleRange = _getVisibleRange();
    final pastHours = _getBaseRange() - _getFutureHours();
    final futureHours = _getFutureHours();
    final halfVisible = visibleRange / 2;
    
    final minOffset = -pastHours + halfVisible;
    final maxOffset = futureHours - halfVisible;
    
    if (minOffset <= maxOffset) {
      _scrollOffset = _scrollOffset.clamp(minOffset, maxOffset);
    } else {
      _scrollOffset = _scrollOffset.clamp(maxOffset, minOffset);
    }
  }

  void _handleZoomOut() {
    setState(() {
      _graphZoomLevel = (_graphZoomLevel / 2).clamp(_minZoom, _maxZoom);
      _clampOffset();
      _syncPeriodWithZoom();
    });
  }

  void _handleZoomIn() {
    // 한달 뷰에서 + 누르면 1주로 축소
    if (widget.viewPeriodDays == 30) {
      setState(() {
        _graphZoomLevel = 1.0;
        _scrollOffset = 0.0;
      });
      widget.onViewPeriodChanged(7);
      return;
    }

    // 1주 뷰에서 +를 계속 누르면 1일로 전환
    if (widget.viewPeriodDays == 7 && _graphZoomLevel <= _minZoom + 0.01) {
      setState(() {
        _graphZoomLevel = 1.0;
        _scrollOffset = 0.0;
      });
      widget.onViewPeriodChanged(1);
      return;
    }

    setState(() {
      _graphZoomLevel = (_graphZoomLevel * 2).clamp(_minZoom, _maxZoom);
      _clampOffset();
      _syncPeriodWithZoom();
    });
  }

  double _getGraphInterval() {
    double baseInterval;
    switch (widget.viewPeriodDays) {
      case 1: baseInterval = 6; break;   // 6시간 간격 (1일 기본)
      case 3: baseInterval = 12; break;  // 12시간 간격
      case 7: baseInterval = 24; break;  // 1일 간격
      case 14: baseInterval = 48; break; // 2일 간격
      case 30: baseInterval = 168; break; // 7일(1주) 간격
      default: baseInterval = 6;
    }
    // 줌인하면 간격도 좁아짐
    double interval = baseInterval / _graphZoomLevel;
    // 최소 2시간, 최대 168시간(7일) 간격으로 제한
    if (interval < 2) return 2;
    if (interval < 3) return 3;
    if (interval < 6) return 6;
    if (interval < 12) return 12;
    if (interval < 24) return 24;
    if (interval < 168) return 168;
    return 168; // 기본값 (최대 1주)
  }

  // 동적 그래프 최대값 계산 (현재값의 120%, 최소 100mg)
  double _getDynamicMaxY(int currentMg, List<dynamic> graphPoints, double halfLife) {
    // 그래프의 모든 데이터 포인트 중 최대값 계산
    final spots = _generateSpots(currentMg, graphPoints, halfLife);
    double maxValue = currentMg.toDouble();
    for (final spot in spots) {
      if (spot.y > maxValue) maxValue = spot.y;
    }
    
    // 수면 한계선도 고려 (너무 높지 않은 경우만)
    // 현재 값의 2배 또는 500mg 중 큰 값까지만 고려하여 그래프가 너무 납작해지는 것 방지
    final limitCap = max(maxValue * 2, 500.0);
    final limitSpots = _generateLimitSpots(halfLife, widget.bedtime, widget.sleepThresholdMg);
    for (final spot in limitSpots) {
      // 현재 뷰 범위 내의 데이터만 확인
      if (spot.x >= _getMinX() && spot.x <= _getMaxX()) {
        if (spot.y > maxValue && spot.y < limitCap) {
          maxValue = spot.y;
        }
      }
    }

    // 최대값의 120%로 설정 (최소 100)
    return max(100, maxValue * 1.2);
  }

  Widget _getBottomTitleWidget(double value, TitleMeta meta) {
    final isDark = MyApp.isDarkMode(context);
    final subTextColor = isDark ? ThemeColors.blackTextSecondary : ThemeColors.ivoryTextSecondary;
    final highlightColor = isDark ? Colors.white : Colors.black;

    final hours = value.toInt();
    final minutes = ((value - hours) * 60).round();
    final now = DateTime.now();
    final targetTime = now.add(Duration(hours: hours, minutes: minutes));
    
    final interval = _getGraphInterval();
    
    String text;
    bool isHighlight = false;

    // 1. 간격이 넓으면(24시간 이상) 날짜 위주 표시
    if (interval >= 24) {
      text = '${targetTime.month}/${targetTime.day}';
      isHighlight = true;
    } 
    // 2. 자정(00:00)인 경우 날짜 표시
    else if (targetTime.hour == 0 && targetTime.minute == 0) {
      text = '${targetTime.month}/${targetTime.day}';
      isHighlight = true;
    }
    // 3. 현재 시점(0)인 경우 날짜 표시 (그래프 기준점)
    else if (value.abs() < 0.1) {
      text = '${targetTime.month}/${targetTime.day}';
      isHighlight = true;
    }
    // 4. 그 외 시간 표시
    else {
      if (interval <= 1) {
        text = '${targetTime.hour}:${targetTime.minute.toString().padLeft(2, '0')}';
      } else {
        text = '${targetTime.hour}'; // '시' 제거하여 간소화
      }
    }

    return SideTitleWidget(
      meta: meta,
      child: Text(
        text,
        style: TextStyle(
          color: isHighlight ? highlightColor : subTextColor,
          fontSize: 10,
          fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // 수면시간까지 남은 시간 계산
  double _getHoursUntilBedtime() {
    final now = DateTime.now();
    final bedtimeDateTime = DateTime(now.year, now.month, now.day, widget.bedtime.hour, widget.bedtime.minute);

    if (now.isAfter(bedtimeDateTime)) {
      // 이미 수면 시간이 지났으면 다음날
      final tomorrowBedtime = bedtimeDateTime.add(const Duration(days: 1));
      return tomorrowBedtime.difference(now).inMinutes / 60.0;
    }
    return bedtimeDateTime.difference(now).inMinutes / 60.0;
  }

  // 수면 시간에 sleepThresholdMg 이하가 되려면 지금 최대 얼마나 섭취 가능한지 계산
  int _getMaxAllowedIntake(int currentMg, double halfLife) {
    final hoursUntilBedtime = _getHoursUntilBedtime();
    if (hoursUntilBedtime <= 0) return 0;

    // 수면 시간에 sleepThresholdMg가 되려면 현재 얼마까지 가능한가
    final maxTotalAtNow = widget.sleepThresholdMg * pow(2, hoursUntilBedtime / halfLife);
    final maxAdditional = maxTotalAtNow - currentMg;

    return max(0, maxAdditional.toInt());
  }

  // 수면 한계선 데이터 생성
  List<FlSpot> _generateLimitSpots(double halfLife, TimeOfDay bedtime, int sleepThreshold) {
    final spots = <FlSpot>[];
    final minX = _getMinX();
    final maxX = _getMaxX();
    final now = DateTime.now();

    // 수면 지속 시간 계산 (분 단위)
    final bedMinutes = bedtime.hour * 60 + bedtime.minute;
    final wakeMinutes = widget.wakeUpTime.hour * 60 + widget.wakeUpTime.minute;
    int sleepDurationMinutes;
    if (wakeMinutes < bedMinutes) {
      sleepDurationMinutes = (24 * 60 - bedMinutes) + wakeMinutes;
    } else {
      sleepDurationMinutes = wakeMinutes - bedMinutes;
    }

    // 0.5시간(30분) 단위로 계산
    for (double i = minX.floor().toDouble(); i <= maxX.ceil(); i += 0.5) {
      final targetTime = now.add(Duration(minutes: (i * 60).round()));
      
      // targetTime 이후의 가장 가까운 수면 시간 찾기
      DateTime nextBedtime = DateTime(targetTime.year, targetTime.month, targetTime.day, bedtime.hour, bedtime.minute);
      if (nextBedtime.isBefore(targetTime) || nextBedtime.isAtSameMomentAs(targetTime)) {
        nextBedtime = nextBedtime.add(const Duration(days: 1));
      }

      // 직전 수면 시작 시간
      DateTime lastBedtime = nextBedtime.subtract(const Duration(days: 1));
      // 직전 기상 시간
      DateTime lastWakeUp = lastBedtime.add(Duration(minutes: sleepDurationMinutes));

      // 수면 중인지 확인 (lastBedtime ~ lastWakeUp 사이)
      if (targetTime.isAfter(lastBedtime) && targetTime.isBefore(lastWakeUp)) {
        spots.add(FlSpot.nullSpot);
        continue;
      }

      final hoursUntilBedtime = nextBedtime.difference(targetTime).inMinutes / 60.0;
      
      // 한계치 계산: Threshold * 2^(남은시간/반감기)
      double maxAllowed = (sleepThreshold * pow(2, hoursUntilBedtime / halfLife)).toDouble();
      
      // 최대 300으로 제한
      if (maxAllowed > 300) maxAllowed = 300;

      spots.add(FlSpot(i, maxAllowed));
    }
    return spots;
  }

  // 수면 시간 포맷
  String _formatBedtime() {
    final hour = widget.bedtime.hour.toString().padLeft(2, '0');
    final minute = widget.bedtime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // 수면 시간 영역 (보라색 배경)
  List<VerticalRangeAnnotation> _getSleepRanges() {
    final ranges = <VerticalRangeAnnotation>[];
    final minX = _getMinX();
    final maxX = _getMaxX();
    final now = DateTime.now();
    
    // 검색 범위: minX 하루 전부터 maxX 하루 후까지
    DateTime current = now.add(Duration(hours: minX.floor() - 24));
    DateTime end = now.add(Duration(hours: maxX.ceil() + 24));
    current = DateTime(current.year, current.month, current.day);

    while (current.isBefore(end)) {
      DateTime bedtime = DateTime(current.year, current.month, current.day, widget.bedtime.hour, widget.bedtime.minute);
      DateTime wakeUp = DateTime(current.year, current.month, current.day, widget.wakeUpTime.hour, widget.wakeUpTime.minute);
      
      // 기상 시간이 취침 시간보다 빠르면 다음날로 간주
      if (wakeUp.isBefore(bedtime)) {
        wakeUp = wakeUp.add(const Duration(days: 1));
      }

      double startX = bedtime.difference(now).inMinutes / 60.0;
      double endX = wakeUp.difference(now).inMinutes / 60.0;

      // 화면에 조금이라도 보이면 추가 (그래프 범위 내로 클램핑)
      if (endX > minX && startX < maxX) {
        ranges.add(VerticalRangeAnnotation(
          x1: startX.clamp(minX, maxX),
          x2: endX.clamp(minX, maxX),
          color: Colors.deepPurple.withOpacity(0.1),
        ));
      }
      current = current.add(const Duration(days: 1));
    }
    return ranges;
  }

  // 수면 시간 라벨
  List<VerticalLine> _getSleepLabels() {
    final lines = <VerticalLine>[];
    final minX = _getMinX();
    final maxX = _getMaxX();
    final now = DateTime.now();
    
    DateTime current = now.add(Duration(hours: minX.floor() - 24));
    DateTime end = now.add(Duration(hours: maxX.ceil() + 24));
    current = DateTime(current.year, current.month, current.day);

    while (current.isBefore(end)) {
      DateTime bedtime = DateTime(current.year, current.month, current.day, widget.bedtime.hour, widget.bedtime.minute);
      DateTime wakeUp = DateTime(current.year, current.month, current.day, widget.wakeUpTime.hour, widget.wakeUpTime.minute);
      
      if (wakeUp.isBefore(bedtime)) {
        wakeUp = wakeUp.add(const Duration(days: 1));
      }

      double startX = bedtime.difference(now).inMinutes / 60.0;
      double endX = wakeUp.difference(now).inMinutes / 60.0;
      double centerX = (startX + endX) / 2;

      if (endX > minX && startX < maxX) {
        lines.add(VerticalLine(
          x: centerX,
          color: Colors.transparent,
          strokeWidth: 0,
          label: VerticalLineLabel(
            show: true,
            alignment: Alignment.center,
            style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12),
            labelResolver: (line) => '수면시간',
          ),
        ));
      }
      current = current.add(const Duration(days: 1));
    }
    return lines;
  }

  // DB 기반 그래프 데이터 생성 (서버에서 받은 실제 데이터)
  List<FlSpot> _generateSpots(int initial, List<dynamic> graphPoints, double halfLife) {
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

    for (double i = minX.toDouble(); i <= maxX; i += 0.5) {
      double y;
      if (i <= 0) {
        y = initial * pow(2, i.abs() / halfLife).toDouble();
      } else {
        y = initial * pow(0.5, i / halfLife).toDouble();
      }
      spots.add(FlSpot(i, y));
    }
    return spots;
  }

  // 줌 레벨 라벨
  String _getZoomLabel() {
    final interval = _getGraphInterval();
    if (interval <= 6) return '1일';
    if (interval <= 12) return '1주';
    return '한달';
  }

  // 줌에 따라 기간 선택 버튼도 동기화
  void _syncPeriodWithZoom() {
    final interval = _getGraphInterval();
    int newPeriod;
    if (interval <= 6) {
      newPeriod = 1;   // 1일
    } else if (interval <= 12) {
      newPeriod = 7;   // 1주
    } else {
      newPeriod = 30;  // 한달
    }
    
    if (widget.viewPeriodDays != newPeriod) {
      widget.onViewPeriodChanged(newPeriod);
    }
  }
}
