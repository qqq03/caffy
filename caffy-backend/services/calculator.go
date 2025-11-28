package services

import (
	"math"
	"time"
)

// 대사 타입 상수
const (
	MetaNormal = 0
	MetaFast   = 1
	MetaSlow   = 2
)

// GetHalfLife : 대사 타입에 따른 반감기(시간) 반환
func GetHalfLife(metaType int) float64 {
	switch metaType {
	case MetaFast:
		return 3.0 // 흡연자 등 빠른 대사
	case MetaSlow:
		return 8.0 // 임산부, 피임약 복용, 간 기능 저하 등
	default:
		return 5.0 // 일반 성인 평균
	}
}

// CalculateRemaining : 특정 섭취 기록의 현재 잔여량 계산
func CalculateRemaining(amount float64, intakeAt time.Time, halfLife float64) float64 {
	elapsedHours := time.Since(intakeAt).Hours()

	// 아직 마시지 않은 미래의 기록이거나, 24시간이 지나 영향력이 미미하면 0 처리
	if elapsedHours < 0 {
		return amount // 아직 흡수 전 (단순화)
	}
	if elapsedHours > 24 {
		return 0
	}

	// 반감기 공식: 남은 양 = 초기 양 * (1/2)^(경과시간/반감기)
	return amount * math.Pow(0.5, elapsedHours/halfLife)
}
