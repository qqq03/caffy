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

	AbsorptionTime = 45.0 // 섭취 후 최고 농도 도달 시간 (분)
	SleepThreshold = 50.0 // 수면에 방해되지 않는 최소 잔류량 (mg)
)

// CalculationResult : 상세 계산 결과
type CalculationResult struct {
	CurrentAmount float64   // 현재 잔류량 (mg)
	IsPeaking     bool      // 현재 흡수 중(상승 중)인가?
	CanSleepAt    time.Time // 언제쯤 잘 수 있는가? (예측 시간)
}

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

// CalculateRemaining : 특정 섭취 기록의 현재 잔여량 계산 (기존 호환용)
func CalculateRemaining(amount float64, intakeAt time.Time, halfLife float64) float64 {
	result := CalculateRemainingAdvanced(amount, intakeAt, halfLife)
	return result.CurrentAmount
}

// CalculateRemainingAdvanced : 고도화된 잔여량 계산 (흡수 구간 포함)
func CalculateRemainingAdvanced(amount float64, intakeAt time.Time, halfLife float64) CalculationResult {
	elapsedMinutes := time.Since(intakeAt).Minutes()
	elapsedHours := elapsedMinutes / 60.0

	var currentAmount float64
	isPeaking := false

	// 1. 흡수 모델 (Pharmacokinetics Absorption Phase)
	if elapsedMinutes < 0 {
		// 미래의 섭취 → 아직 흡수 전
		currentAmount = 0
	} else if elapsedMinutes < AbsorptionTime {
		// 상승 구간: 0분~45분 사이에 점진적으로 증가
		// Sinusoidal easing으로 자연스러운 흡수 곡선
		ratio := elapsedMinutes / AbsorptionTime
		// 부드러운 증가: sin(ratio * π/2)
		currentAmount = amount * math.Sin(ratio*math.Pi/2)
		isPeaking = true
	} else {
		// 2. 대사 모델 (Elimination Phase)
		// 최고점(45분)을 기준으로 반감기 적용
		eliminationHours := elapsedHours - (AbsorptionTime / 60.0)
		currentAmount = amount * math.Pow(0.5, eliminationHours/halfLife)
	}

	// 3. 24시간 지나거나 극소량이면 0 처리
	if elapsedHours > 24 || currentAmount < 1.0 {
		currentAmount = 0
	}

	// 4. 수면 가능 시간 예측
	canSleepAt := calculateSleepTime(amount, intakeAt, halfLife)

	return CalculationResult{
		CurrentAmount: math.Round(currentAmount*10) / 10,
		IsPeaking:     isPeaking,
		CanSleepAt:    canSleepAt,
	}
}

// calculateSleepTime : 수면 가능 시간 계산
func calculateSleepTime(amount float64, intakeAt time.Time, halfLife float64) time.Time {
	if amount <= SleepThreshold {
		return time.Now() // 이미 수면 가능
	}

	// 역산: SleepThreshold까지 떨어지는 데 걸리는 시간
	// t = halfLife * log2(amount / SleepThreshold)
	hoursNeeded := halfLife * (math.Log(amount/SleepThreshold) / math.Log(2))

	// 흡수 시간 보정 (45분 추가)
	hoursNeeded += (AbsorptionTime / 60.0)

	return intakeAt.Add(time.Duration(hoursNeeded*60) * time.Minute)
}

// CalculateTotalRemaining : 여러 섭취 기록의 총 잔여량 계산
func CalculateTotalRemaining(logs []struct {
	Amount   float64
	IntakeAt time.Time
}, halfLife float64) float64 {
	total := 0.0
	for _, log := range logs {
		total += CalculateRemaining(log.Amount, log.IntakeAt, halfLife)
	}
	return total
}

// PredictCaffeineAt : 특정 미래 시간의 예상 카페인량 계산
func PredictCaffeineAt(currentAmount float64, halfLife float64, hoursLater float64) float64 {
	if hoursLater <= 0 {
		return currentAmount
	}
	return currentAmount * math.Pow(0.5, hoursLater/halfLife)
}

// GetMaxSafeIntake : 목표 시간에 안전 수치 이하가 되려면 지금 최대 얼마까지 섭취 가능한지
func GetMaxSafeIntake(currentAmount float64, halfLife float64, hoursUntilTarget float64, targetAmount float64) float64 {
	if hoursUntilTarget <= 0 {
		return 0
	}

	// 흡수 시간 보정 (45분 후 최고점이므로 약간 더 여유)
	absorptionBuffer := AbsorptionTime / 60.0
	if hoursUntilTarget < absorptionBuffer {
		// 흡수 시간보다 목표 시간이 짧으면 섭취 불가
		return 0
	}

	// 목표 시간에 targetAmount가 되려면 지금 최대 얼마까지 가능?
	// (currentAmount + X) * 0.5^(t/h) = targetAmount
	// X = targetAmount / 0.5^(t/h) - currentAmount
	maxTotal := targetAmount / math.Pow(0.5, hoursUntilTarget/halfLife)
	maxAdditional := maxTotal - currentAmount

	if maxAdditional < 0 {
		return 0
	}
	return math.Round(maxAdditional)
}

// CalculateCaffeineAtTime : 특정 시점의 카페인 잔류량 계산 (그래프용)
func CalculateCaffeineAtTime(amount float64, intakeAt time.Time, targetTime time.Time, halfLife float64) float64 {
	elapsedMinutes := targetTime.Sub(intakeAt).Minutes()
	elapsedHours := elapsedMinutes / 60.0

	var currentAmount float64

	if elapsedMinutes < 0 {
		// 아직 섭취 전
		currentAmount = 0
	} else if elapsedMinutes < AbsorptionTime {
		// 흡수 구간: 0~45분 사이 점진적 증가 (사인 곡선)
		ratio := elapsedMinutes / AbsorptionTime
		currentAmount = amount * math.Sin(ratio*math.Pi/2)
	} else {
		// 대사 구간: 45분 이후 반감기 적용
		eliminationHours := elapsedHours - (AbsorptionTime / 60.0)
		currentAmount = amount * math.Pow(0.5, eliminationHours/halfLife)
	}

	// 24시간 이상 또는 극소량은 0 처리
	if elapsedHours > 24 || currentAmount < 1.0 {
		return 0
	}

	return currentAmount
}
