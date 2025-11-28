package services

import (
	"caffy-backend/config"
	"caffy-backend/models"
	"math"
	"time"
)

// ========================================
// 개인별 카페인 대사 학습 서비스
// ========================================

// LearningService : 학습 서비스 구조체
type LearningService struct {
	MinDataPoints   int     // 학습에 필요한 최소 데이터 포인트
	LearningRate    float64 // 학습률 (새 데이터의 반영 비율)
	MinHalfLife     float64 // 최소 반감기 (시간)
	MaxHalfLife     float64 // 최대 반감기 (시간)
	ConfidenceDecay float64 // 시간에 따른 신뢰도 감소율
}

// NewLearningService : 학습 서비스 생성
func NewLearningService() *LearningService {
	return &LearningService{
		MinDataPoints:   5,
		LearningRate:    0.2, // 새 데이터가 20% 반영
		MinHalfLife:     2.0,
		MaxHalfLife:     12.0,
		ConfidenceDecay: 0.01,
	}
}

// GetPersonalHalfLife : 사용자의 개인화된 반감기 반환
func GetPersonalHalfLife(user *models.User) float64 {
	// 학습된 개인 반감기가 있고, 신뢰도가 충분하면 사용
	if user.TotalFeedbacks >= 5 && user.LearningConfidence >= 0.3 {
		return user.PersonalHalfLife
	}

	// 아니면 기본 반감기에 개인 특성 보정 적용
	baseHalfLife := GetHalfLife(user.MetabolismType)
	return ApplyPersonalModifiers(baseHalfLife, user)
}

// ApplyPersonalModifiers : 개인 특성에 따른 반감기 보정
func ApplyPersonalModifiers(baseHalfLife float64, user *models.User) float64 {
	halfLife := baseHalfLife

	// 흡연자: 대사 50% 빨라짐 (반감기 감소)
	if user.IsSmoker {
		halfLife *= 0.65
	}

	// 임신: 대사 50~100% 느려짐 (반감기 증가)
	if user.IsPregnant {
		halfLife *= 2.0
	}

	// 운동 빈도: 많이 할수록 대사 빨라짐
	if user.ExercisePerWeek >= 5 {
		halfLife *= 0.9 // 10% 빨라짐
	} else if user.ExercisePerWeek <= 1 {
		halfLife *= 1.1 // 10% 느려짐
	}

	// 체중 보정 (평균 70kg 기준)
	if user.Weight > 0 {
		weightFactor := 70.0 / user.Weight
		// 체중이 많이 나갈수록 희석되어 대사 느려짐
		halfLife *= math.Pow(weightFactor, 0.3) // 약한 보정
	}

	// 범위 제한
	if halfLife < 2.0 {
		halfLife = 2.0
	}
	if halfLife > 12.0 {
		halfLife = 12.0
	}

	return halfLife
}

// ProcessFeedback : 사용자 피드백을 받아 학습 수행
func (ls *LearningService) ProcessFeedback(userID uint, senseLevel int, actualFeeling string) (*models.CaffeineFeedback, error) {
	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		return nil, err
	}

	// 현재 예측된 카페인 잔류량 계산
	predictedLevel := CalculateCurrentCaffeine(userID, GetPersonalHalfLife(&user))

	// 마지막 섭취 정보 가져오기
	var lastLog models.CaffeineLog
	hoursAfterLast := 0.0
	lastAmount := 0.0

	if err := config.DB.Where("user_id = ?", userID).Order("intake_at DESC").First(&lastLog).Error; err == nil {
		hoursAfterLast = time.Since(lastLog.IntakeAt).Hours()
		lastAmount = lastLog.Amount
	}

	// 피드백 저장
	feedback := models.CaffeineFeedback{
		UserID:           userID,
		FeedbackAt:       time.Now(),
		SenseLevel:       senseLevel,
		PredictedLevel:   predictedLevel,
		ActualFeeling:    actualFeeling,
		HoursAfterLast:   hoursAfterLast,
		LastIntakeAmount: lastAmount,
	}

	if err := config.DB.Create(&feedback).Error; err != nil {
		return nil, err
	}

	// 실시간 학습 수행
	ls.LearnFromFeedback(&user, &feedback)

	return &feedback, nil
}

// LearnFromFeedback : 피드백으로부터 학습
func (ls *LearningService) LearnFromFeedback(user *models.User, feedback *models.CaffeineFeedback) {
	// 체감 레벨과 예측 레벨 비교
	// senseLevel: 1(졸림) ~ 5(매우 각성)
	// 예측 mg 기준: 0mg=1, 50mg=2, 100mg=3, 150mg=4, 200mg+=5

	expectedSense := mgToSenseLevel(feedback.PredictedLevel)
	senseDiff := float64(feedback.SenseLevel) - expectedSense

	// 반감기 조정
	// 실제로 더 각성 상태면 -> 반감기가 예상보다 김 (대사 느림)
	// 실제로 덜 각성 상태면 -> 반감기가 예상보다 짧음 (대사 빠름)

	if feedback.HoursAfterLast > 0 && feedback.LastIntakeAmount > 0 {
		adjustment := senseDiff * 0.1 // 미세 조정

		previousHalfLife := user.PersonalHalfLife
		if previousHalfLife == 0 {
			previousHalfLife = GetHalfLife(user.MetabolismType)
		}

		// 새 반감기 = 이전 반감기 + 조정값
		newHalfLife := previousHalfLife + adjustment

		// 범위 제한
		if newHalfLife < ls.MinHalfLife {
			newHalfLife = ls.MinHalfLife
		}
		if newHalfLife > ls.MaxHalfLife {
			newHalfLife = ls.MaxHalfLife
		}

		// Exponential Moving Average 적용
		user.PersonalHalfLife = (1-ls.LearningRate)*previousHalfLife + ls.LearningRate*newHalfLife
		user.TotalFeedbacks++

		// 신뢰도 업데이트 (피드백이 쌓일수록 증가, 최대 0.95)
		user.LearningConfidence = math.Min(0.95, float64(user.TotalFeedbacks)/20.0)

		// 학습 히스토리 저장
		history := models.LearningHistory{
			UserID:           user.ID,
			PreviousHalfLife: previousHalfLife,
			NewHalfLife:      user.PersonalHalfLife,
			DataPointsUsed:   user.TotalFeedbacks,
			Reason:           "realtime_feedback",
		}
		config.DB.Create(&history)

		// 피드백 학습 완료 표시
		feedback.IsUsedForLearning = true
		config.DB.Save(feedback)
	}

	// 사용자 저장
	config.DB.Save(user)
}

// BatchLearn : 배치 학습 (축적된 데이터로 정밀 학습)
func (ls *LearningService) BatchLearn(userID uint) error {
	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		return err
	}

	// 미사용 피드백 가져오기
	var feedbacks []models.CaffeineFeedback
	config.DB.Where("user_id = ? AND is_used_for_learning = ?", userID, false).
		Order("feedback_at ASC").
		Find(&feedbacks)

	if len(feedbacks) < ls.MinDataPoints {
		return nil // 데이터 부족
	}

	// Grid Search로 최적 반감기 찾기
	bestHalfLife := user.PersonalHalfLife
	if bestHalfLife == 0 {
		bestHalfLife = GetHalfLife(user.MetabolismType)
	}
	bestError := math.MaxFloat64

	for hl := ls.MinHalfLife; hl <= ls.MaxHalfLife; hl += 0.5 {
		totalError := 0.0

		for _, fb := range feedbacks {
			// 해당 반감기로 예측했을 때의 레벨
			predicted := EstimateCaffeineAt(userID, fb.FeedbackAt, hl)
			predictedSense := mgToSenseLevel(predicted)

			// 실제 체감과의 차이
			diff := float64(fb.SenseLevel) - predictedSense
			totalError += diff * diff // MSE
		}

		avgError := totalError / float64(len(feedbacks))
		if avgError < bestError {
			bestError = avgError
			bestHalfLife = hl
		}
	}

	// 개선이 있으면 업데이트
	previousHalfLife := user.PersonalHalfLife
	improvement := 0.0

	if previousHalfLife > 0 {
		// 이전 반감기의 에러 계산
		prevError := 0.0
		for _, fb := range feedbacks {
			predicted := EstimateCaffeineAt(userID, fb.FeedbackAt, previousHalfLife)
			predictedSense := mgToSenseLevel(predicted)
			diff := float64(fb.SenseLevel) - predictedSense
			prevError += diff * diff
		}
		prevError /= float64(len(feedbacks))

		if prevError > 0 {
			improvement = (prevError - bestError) / prevError * 100
		}
	}

	user.PersonalHalfLife = bestHalfLife
	user.LearningConfidence = math.Min(0.95, float64(len(feedbacks))/20.0)

	// 학습 히스토리 저장
	history := models.LearningHistory{
		UserID:           user.ID,
		PreviousHalfLife: previousHalfLife,
		NewHalfLife:      bestHalfLife,
		DataPointsUsed:   len(feedbacks),
		Improvement:      improvement,
		Reason:           "batch_learning",
	}
	config.DB.Create(&history)

	// 피드백 학습 완료 표시
	for _, fb := range feedbacks {
		fb.IsUsedForLearning = true
		config.DB.Save(&fb)
	}

	config.DB.Save(&user)

	return nil
}

// ========================================
// 헬퍼 함수
// ========================================

// mgToSenseLevel : mg을 체감 레벨(1~5)로 변환
func mgToSenseLevel(mg float64) float64 {
	if mg <= 0 {
		return 1.0
	}
	// 0mg -> 1, 50mg -> 2, 100mg -> 3, 150mg -> 4, 200mg+ -> 5
	level := 1.0 + (mg / 50.0)
	if level > 5 {
		level = 5
	}
	return level
}

// CalculateCurrentCaffeine : 현재 카페인 잔류량 계산
func CalculateCurrentCaffeine(userID uint, halfLife float64) float64 {
	var logs []models.CaffeineLog
	yesterday := time.Now().Add(-24 * time.Hour)

	config.DB.Where("user_id = ? AND intake_at > ?", userID, yesterday).Find(&logs)

	totalRemaining := 0.0
	for _, log := range logs {
		remaining := CalculateRemaining(log.Amount, log.IntakeAt, halfLife)
		totalRemaining += remaining
	}

	return totalRemaining
}

// EstimateCaffeineAt : 특정 시점의 카페인 잔류량 추정
func EstimateCaffeineAt(userID uint, targetTime time.Time, halfLife float64) float64 {
	var logs []models.CaffeineLog
	startTime := targetTime.Add(-24 * time.Hour)

	config.DB.Where("user_id = ? AND intake_at > ? AND intake_at < ?",
		userID, startTime, targetTime).Find(&logs)

	totalRemaining := 0.0
	for _, log := range logs {
		elapsedHours := targetTime.Sub(log.IntakeAt).Hours()
		if elapsedHours > 0 {
			remaining := log.Amount * math.Pow(0.5, elapsedHours/halfLife)
			totalRemaining += remaining
		}
	}

	return totalRemaining
}

// GetLearningStats : 학습 통계 조회
func GetLearningStats(userID uint) map[string]interface{} {
	var user models.User
	config.DB.First(&user, userID)

	var feedbackCount int64
	config.DB.Model(&models.CaffeineFeedback{}).Where("user_id = ?", userID).Count(&feedbackCount)

	var histories []models.LearningHistory
	config.DB.Where("user_id = ?", userID).Order("created_at DESC").Limit(5).Find(&histories)

	baseHalfLife := GetHalfLife(user.MetabolismType)
	personalHalfLife := GetPersonalHalfLife(&user)

	return map[string]interface{}{
		"base_half_life":      baseHalfLife,
		"personal_half_life":  personalHalfLife,
		"learning_confidence": user.LearningConfidence,
		"total_feedbacks":     user.TotalFeedbacks,
		"feedback_count":      feedbackCount,
		"recent_learning":     histories,
		"is_personalized":     user.TotalFeedbacks >= 5 && user.LearningConfidence >= 0.3,
	}
}
