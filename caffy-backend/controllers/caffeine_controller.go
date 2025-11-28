package controllers

import (
	"caffy-backend/config"
	"caffy-backend/models"
	"caffy-backend/services"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// 1. 사용자 생성 (회원가입 대용)
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
	var input models.CaffeineLog
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// 시간 입력이 없으면 현재 시간으로 설정
	if input.IntakeAt.IsZero() {
		input.IntakeAt = time.Now()
	}
	config.DB.Create(&input)
	c.JSON(http.StatusOK, input)
}

// 3. 현재 상태 조회 (핵심!)
// 사용자의 현재 체내 총 카페인 잔류량을 계산해서 리턴
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
		"current_caffeine_mg": int(totalRemaining), // 소수점 버림
		"half_life_used":      halfLife,
		"status_message":      getStatusMessage(totalRemaining),
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
