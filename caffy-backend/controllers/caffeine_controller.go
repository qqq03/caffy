package controllers

import (
	"caffy-backend/config"
	"caffy-backend/middleware"
	"caffy-backend/models"
	"caffy-backend/services"
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
	for _, log := range logs {
		rem := services.CalculateRemaining(log.Amount, log.IntakeAt, halfLife)
		totalRemaining += rem
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

// 헬퍼 함수
func getStatusMessage(mg float64) string {
	if mg > 200 {
		return "⚠️ 과다 상태입니다. 불안감을 느낄 수 있어요."
	} else if mg > 50 {
		return "⚡️ 집중하기 딱 좋은 상태입니다!"
	} else {
		return "😴 카페인 효과가 거의 사라졌습니다."
	}
}
