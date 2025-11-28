package controllers

import (
	"caffy-backend/config"
	"caffy-backend/middleware"
	"caffy-backend/models"
	"caffy-backend/services"
	"math"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ========================================
// 개인별 학습 API
// ========================================

// SubmitSenseFeedback : 체감 피드백 제출
// POST /api/learning/feedback
func SubmitSenseFeedback(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var input struct {
		SenseLevel    int    `json:"sense_level" binding:"required,min=1,max=5"` // 1~5
		ActualFeeling string `json:"actual_feeling"`                             // 선택적 텍스트
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ls := services.NewLearningService()
	feedback, err := ls.ProcessFeedback(userID, input.SenseLevel, input.ActualFeeling)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "피드백 처리 실패"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  "피드백이 반영되었습니다",
		"feedback": feedback,
	})
}

// GetLearningStats : 학습 통계 조회
// GET /api/learning/stats
func GetLearningStats(c *gin.Context) {
	userID := middleware.GetUserID(c)

	stats := services.GetLearningStats(userID)

	c.JSON(http.StatusOK, stats)
}

// TriggerBatchLearning : 배치 학습 트리거
// POST /api/learning/train
func TriggerBatchLearning(c *gin.Context) {
	userID := middleware.GetUserID(c)

	ls := services.NewLearningService()
	err := ls.BatchLearn(userID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "학습 실패"})
		return
	}

	stats := services.GetLearningStats(userID)

	c.JSON(http.StatusOK, gin.H{
		"message": "배치 학습 완료",
		"stats":   stats,
	})
}

// GetPersonalizedPrediction : 개인화된 예측 조회
// GET /api/learning/prediction
func GetPersonalizedPrediction(c *gin.Context) {
	userID := middleware.GetUserID(c)

	// 사용자 정보 로드
	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "사용자를 찾을 수 없습니다"})
		return
	}

	// 개인화된 반감기로 계산
	personalHalfLife := services.GetPersonalHalfLife(&user)
	currentCaffeine := services.CalculateCurrentCaffeine(userID, personalHalfLife)

	// 향후 예측 (1시간 단위, 12시간)
	predictions := make([]map[string]interface{}, 13)
	for i := 0; i <= 12; i++ {
		hours := float64(i)
		remaining := currentCaffeine * math.Pow(0.5, hours/personalHalfLife)

		predictions[i] = map[string]interface{}{
			"hours":    i,
			"caffeine": int(remaining),
			"sense":    senseLevelToText(remaining),
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"current_caffeine":   int(currentCaffeine),
		"personal_half_life": personalHalfLife,
		"is_personalized":    user.TotalFeedbacks >= 5,
		"confidence":         user.LearningConfidence,
		"predictions":        predictions,
	})
}

// senseLevelToText : mg을 텍스트 상태로 변환
func senseLevelToText(mg float64) string {
	if mg < 25 {
		return "😴 거의 없음"
	} else if mg < 75 {
		return "😐 약간"
	} else if mg < 125 {
		return "⚡ 적당"
	} else if mg < 175 {
		return "🔥 활발"
	} else {
		return "⚠️ 과다"
	}
}
