package controllers

import (
	"caffy-backend/config"
	"caffy-backend/middleware"
	"caffy-backend/models"
	"caffy-backend/services"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// 1. 사용자 생성 (회원가입 대용) - deprecated, use auth_controller.Register
func CreateUser(c *gin.Context) {
	var input models.User
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	config.DB.Create(&input)
	c.JSON(http.StatusOK, input)
}

// 2. 카페인 섭취 기록 추가
func AddLog(c *gin.Context) {
	var input struct {
		DrinkName  string    `json:"drink_name"`
		Amount     float64   `json:"amount"`
		IntakeAt   time.Time `json:"intake_at"`
		BeverageID *uint     `json:"beverage_id"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 토큰에서 사용자 ID 가져오기
	userID := middleware.GetUserID(c)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "인증이 필요합니다"})
		return
	}

	log := models.CaffeineLog{
		UserID:     userID,
		DrinkName:  input.DrinkName,
		Amount:     input.Amount,
		IntakeAt:   input.IntakeAt,
		BeverageID: input.BeverageID,
	}

	// 시간 입력이 없으면 현재 시간으로 설정
	if log.IntakeAt.IsZero() {
		log.IntakeAt = time.Now()
	}

	config.DB.Create(&log)
	c.JSON(http.StatusOK, log)
}

// 3. 현재 상태 조회 (ID 기반 - 레거시)
func GetCurrentStatus(c *gin.Context) {
	userId := c.Param("id")

	var user models.User
	var logs []models.CaffeineLog

	// 사용자 및 최근 24시간 내 로그 조회
	if err := config.DB.First(&user, userId).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// 성능 최적화: 24시간 이내 기록만 가져옴
	yesterday := time.Now().Add(-24 * time.Hour)
	config.DB.Where("user_id = ? AND intake_at > ?", userId, yesterday).Find(&logs)

	totalRemaining := 0.0
	halfLife := services.GetHalfLife(user.MetabolismType)

	for _, log := range logs {
		rem := services.CalculateRemaining(log.Amount, log.IntakeAt, halfLife)
		totalRemaining += rem
	}

	c.JSON(http.StatusOK, gin.H{
		"nickname":            user.Nickname,
		"current_caffeine_mg": int(totalRemaining),
		"half_life_used":      halfLife,
		"status_message":      getStatusMessage(totalRemaining),
	})
}

// 4. 현재 상태 조회 (토큰 기반 - 신규, 개인화된 반감기 적용)
func GetMyStatus(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	var logs []models.CaffeineLog

	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// 사용자 설정 기간 적용 (1일, 3일, 7일)
	periodDays := user.ViewPeriodDays
	if periodDays <= 0 {
		periodDays = 7 // 기본값 7일
	}
	startTime := time.Now().Add(-time.Duration(periodDays) * 24 * time.Hour)
	config.DB.Where("user_id = ? AND intake_at > ?", userID, startTime).Order("intake_at DESC").Find(&logs)

	// 개인화된 반감기 사용
	halfLife := services.GetPersonalHalfLife(&user)
	baseHalfLife := services.GetHalfLife(user.MetabolismType)

	totalRemaining := 0.0
	var latestCanSleepAt time.Time
	hasPeaking := false

	for _, log := range logs {
		result := services.CalculateRemainingAdvanced(log.Amount, log.IntakeAt, halfLife)
		totalRemaining += result.CurrentAmount

		// 흡수 중인 음료가 있는지 체크
		if result.IsPeaking {
			hasPeaking = true
		}

		// 가장 늦은 수면 가능 시간 계산
		if result.CanSleepAt.After(latestCanSleepAt) {
			latestCanSleepAt = result.CanSleepAt
		}
	}

	// 수면 가능 시간 포맷팅
	var canSleepMessage string
	if latestCanSleepAt.Before(time.Now()) || latestCanSleepAt.IsZero() {
		canSleepMessage = "지금 바로 잘 수 있어요 😴"
	} else {
		untilSleep := time.Until(latestCanSleepAt)
		hours := int(untilSleep.Hours())
		mins := int(untilSleep.Minutes()) % 60
		if hours > 0 {
			canSleepMessage = latestCanSleepAt.Format("15:04") + " 이후 수면 권장 (약 " + strconv.Itoa(hours) + "시간 " + strconv.Itoa(mins) + "분 후)"
		} else {
			canSleepMessage = latestCanSleepAt.Format("15:04") + " 이후 수면 권장 (약 " + strconv.Itoa(mins) + "분 후)"
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"user_id":             userID,
		"nickname":            user.Nickname,
		"current_caffeine_mg": int(totalRemaining),
		"half_life_used":      halfLife,
		"base_half_life":      baseHalfLife,
		"is_personalized":     user.TotalFeedbacks >= 5 && user.LearningConfidence >= 0.3,
		"learning_confidence": user.LearningConfidence,
		"status_message":      getStatusMessage(totalRemaining),
		"logs_count":          len(logs),
		"view_period_days":    periodDays,
		"is_peaking":          hasPeaking,
		"can_sleep_at":        latestCanSleepAt.Format(time.RFC3339),
		"can_sleep_message":   canSleepMessage,
	})
}

// 5. 섭취 기록 히스토리 조회
func GetMyLogs(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// 쿼리 파라미터로 기간 지정 가능
	periodDays := user.ViewPeriodDays
	if days := c.Query("days"); days != "" {
		if d, err := strconv.Atoi(days); err == nil && d > 0 {
			periodDays = d
		}
	}
	if periodDays <= 0 {
		periodDays = 7
	}

	startTime := time.Now().Add(-time.Duration(periodDays) * 24 * time.Hour)

	var logs []models.CaffeineLog
	config.DB.Where("user_id = ? AND intake_at > ?", userID, startTime).
		Order("intake_at DESC").Find(&logs)

	// 일별 통계
	dailyStats := make(map[string]float64)
	for _, log := range logs {
		dateKey := log.IntakeAt.Format("2006-01-02")
		dailyStats[dateKey] += log.Amount
	}

	c.JSON(http.StatusOK, gin.H{
		"logs":        logs,
		"total_count": len(logs),
		"period_days": periodDays,
		"daily_stats": dailyStats,
	})
}

// 6. 조회 기간 설정 변경
func SetViewPeriod(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var input struct {
		Days int `json:"days" binding:"required,oneof=1 3 7"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "유효한 기간을 선택하세요 (1, 3, 7일)"})
		return
	}

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	user.ViewPeriodDays = input.Days
	config.DB.Save(&user)

	c.JSON(http.StatusOK, gin.H{
		"message":          "조회 기간이 변경되었습니다",
		"view_period_days": user.ViewPeriodDays,
	})
}

// 7. 섭취 기록 수정 (비율 조절)
func UpdateLog(c *gin.Context) {
	userID := middleware.GetUserID(c)
	logID := c.Param("id")

	var input struct {
		Amount     *float64 `json:"amount"`
		Percentage *float64 `json:"percentage"` // 0.0 ~ 1.0 (예: 0.5 = 50%)
		DrinkName  *string  `json:"drink_name"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var log models.CaffeineLog
	if err := config.DB.Where("id = ? AND user_id = ?", logID, userID).First(&log).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "기록을 찾을 수 없습니다"})
		return
	}

	// 비율로 수정하는 경우
	if input.Percentage != nil {
		log.Amount = log.Amount * (*input.Percentage)
	}

	// 직접 양 수정하는 경우
	if input.Amount != nil {
		log.Amount = *input.Amount
	}

	if input.DrinkName != nil {
		log.DrinkName = *input.DrinkName
	}

	config.DB.Save(&log)
	c.JSON(http.StatusOK, gin.H{
		"message": "기록이 수정되었습니다",
		"log":     log,
	})
}

// 8. 섭취 기록 삭제
func DeleteLog(c *gin.Context) {
	userID := middleware.GetUserID(c)
	logID := c.Param("id")

	var log models.CaffeineLog
	if err := config.DB.Where("id = ? AND user_id = ?", logID, userID).First(&log).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "기록을 찾을 수 없습니다"})
		return
	}

	config.DB.Delete(&log)
	c.JSON(http.StatusOK, gin.H{"message": "기록이 삭제되었습니다"})
}

// 9. 그래프 데이터 조회 (시간대별 실제 카페인 잔류량 - 흡수 구간 반영)
func GetGraphData(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// 기간 설정
	periodDays := user.ViewPeriodDays
	if periodDays <= 0 {
		periodDays = 7
	}

	// 과거 기간 + 미래 예측을 위한 로그 조회
	startTime := time.Now().Add(-time.Duration(periodDays) * 24 * time.Hour)
	var logs []models.CaffeineLog
	config.DB.Where("user_id = ? AND intake_at > ?", userID, startTime).
		Order("intake_at ASC").Find(&logs)

	halfLife := services.GetPersonalHalfLife(&user)
	now := time.Now()

	// 30분 단위로 데이터 포인트 생성 (흡수 곡선 표현을 위해 더 세밀하게)
	var graphPoints []map[string]interface{}

	// 과거 기간 시작부터 미래까지
	intervalsBack := periodDays * 48    // 30분 단위
	intervalsForward := periodDays * 24 // 미래는 절반만

	for i := -intervalsBack; i <= intervalsForward; i++ {
		targetTime := now.Add(time.Duration(i*30) * time.Minute)
		totalCaffeine := 0.0

		// 각 섭취 기록에서 해당 시점의 잔류량 계산 (services 함수 사용)
		for _, log := range logs {
			remaining := services.CalculateCaffeineAtTime(log.Amount, log.IntakeAt, targetTime, halfLife)
			totalCaffeine += remaining
		}

		graphPoints = append(graphPoints, map[string]interface{}{
			"hour":     float64(i) / 2.0, // 30분 단위를 시간으로 변환
			"time":     targetTime.Format(time.RFC3339),
			"caffeine": int(math.Round(totalCaffeine)),
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"graph_points":     graphPoints,
		"half_life":        halfLife,
		"period_days":      periodDays,
		"current_caffeine": graphPoints[intervalsBack]["caffeine"], // 현재 시점 (i=0)
	})
}

// 헬퍼 함수
func getStatusMessage(mg float64) string {
	if mg > 1000 {
		return "💀 치명적인 상태입니다! 병원에 문의해보세요!"
	} else if mg > 800 {
		return "🚨 매우 위험한 상태입니다! 즉시 카페인 섭취를 중단하세요!"
	} else if mg > 200 {
		return "⚠️ 과다 상태입니다. 불안감을 느낄 수 있어요."
	} else if mg > 50 {
		return "⚡️ 집중하기 딱 좋은 상태입니다!"
	} else {
		return "😴 카페인 효과가 거의 사라졌습니다."
	}
}
