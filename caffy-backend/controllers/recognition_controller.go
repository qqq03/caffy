package controllers

import (
	"caffy-backend/config"
	"caffy-backend/models"
	"caffy-backend/services"
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// ========================================
// 이미지 인식 관련 API
// ========================================

// RecognizeImage : 이미지로 음료 인식
// POST /api/recognize
func RecognizeImage(c *gin.Context) {
	// 1. 사용자 ID 확인
	userIDStr := c.PostForm("user_id")
	if userIDStr == "" {
		userIDStr = c.Query("user_id")
	}

	userID, err := strconv.ParseUint(userIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id가 필요합니다"})
		return
	}

	// 2. 이미지 파일 받기
	file, err := c.FormFile("image")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "이미지 파일이 필요합니다"})
		return
	}

	// 파일 크기 체크 (10MB 제한)
	if file.Size > 10*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "이미지 크기는 10MB 이하여야 합니다"})
		return
	}

	// 파일 열기
	src, err := file.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "파일 읽기 실패"})
		return
	}
	defer src.Close()

	// 이미지 데이터 읽기
	imageData, err := io.ReadAll(src)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "이미지 데이터 읽기 실패"})
		return
	}

	// 3. 인식 수행
	result, err := services.RecognizeBeverage(imageData, uint(userID))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// 4. 결과 반환
	c.JSON(http.StatusOK, gin.H{
		"success":         result.Found,
		"beverage":        result.Beverage,
		"confidence":      result.Confidence,
		"vision_api_used": result.VisionAPIUsed,
		"is_new_beverage": result.IsNewBeverage,
		"ocr_text":        result.OCRText,
		"detected_logos":  result.DetectedLogos,
		"detected_labels": result.DetectedLabels,
	})
}

// ========================================
// 음료 관리 API
// ========================================

// GetAllBeverages : 모든 음료 목록 조회
// GET /api/beverages
func GetAllBeverages(c *gin.Context) {
	var beverages []models.Beverage

	// 쿼리 파라미터로 필터링
	query := config.DB.Model(&models.Beverage{})

	if category := c.Query("category"); category != "" {
		query = query.Where("category = ?", category)
	}
	if brand := c.Query("brand"); brand != "" {
		query = query.Where("brand LIKE ?", "%"+brand+"%")
	}
	if verified := c.Query("verified"); verified == "true" {
		query = query.Where("is_verified = ?", true)
	}

	query.Order("name ASC").Find(&beverages)

	c.JSON(http.StatusOK, beverages)
}

// GetBeverage : 특정 음료 조회
// GET /api/beverages/:id
func GetBeverage(c *gin.Context) {
	id := c.Param("id")
	var beverage models.Beverage

	if err := config.DB.Preload("Images").First(&beverage, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "음료를 찾을 수 없습니다"})
		return
	}

	c.JSON(http.StatusOK, beverage)
}

// CreateBeverage : 새 음료 등록 (수동)
// POST /api/beverages
func CreateBeverage(c *gin.Context) {
	var input models.Beverage
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 중복 체크
	var existing models.Beverage
	if err := config.DB.Where("name = ?", input.Name).First(&existing).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "이미 존재하는 음료입니다", "beverage": existing})
		return
	}

	config.DB.Create(&input)
	c.JSON(http.StatusCreated, input)
}

// UpdateBeverage : 음료 정보 수정
// PUT /api/beverages/:id
func UpdateBeverage(c *gin.Context) {
	id := c.Param("id")
	var beverage models.Beverage

	if err := config.DB.First(&beverage, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "음료를 찾을 수 없습니다"})
		return
	}

	var input models.Beverage
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	config.DB.Model(&beverage).Updates(input)
	c.JSON(http.StatusOK, beverage)
}

// SearchBeverages : 음료 검색
// GET /api/beverages/search?q=아메리카노
func SearchBeverages(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "검색어가 필요합니다"})
		return
	}

	var beverages []models.Beverage
	config.DB.Where("name LIKE ? OR brand LIKE ?", "%"+query+"%", "%"+query+"%").
		Order("is_verified DESC, name ASC").
		Limit(20).
		Find(&beverages)

	c.JSON(http.StatusOK, beverages)
}

// ========================================
// 피드백 API (학습용)
// ========================================

// SubmitFeedback : 인식 결과에 대한 피드백
// POST /api/feedback
func SubmitFeedback(c *gin.Context) {
	var input struct {
		RecognitionLogID uint  `json:"recognition_log_id" binding:"required"`
		IsCorrect        bool  `json:"is_correct"`
		CorrectedID      *uint `json:"corrected_id"` // 틀렸을 경우 올바른 음료 ID
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var log models.RecognitionLog
	if err := config.DB.First(&log, input.RecognitionLogID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "로그를 찾을 수 없습니다"})
		return
	}

	// 피드백 업데이트
	log.IsCorrect = &input.IsCorrect
	if input.CorrectedID != nil {
		log.CorrectedID = input.CorrectedID
	}

	config.DB.Save(&log)

	c.JSON(http.StatusOK, gin.H{"message": "피드백이 저장되었습니다"})
}

// ========================================
// 통계 API
// ========================================

// GetRecognitionStats : 인식 통계
// GET /api/stats/recognition
func GetRecognitionStats(c *gin.Context) {
	var totalLogs int64
	var visionAPIUsed int64
	var correctFeedbacks int64

	config.DB.Model(&models.RecognitionLog{}).Count(&totalLogs)
	config.DB.Model(&models.RecognitionLog{}).Where("vision_api_used = ?", true).Count(&visionAPIUsed)
	config.DB.Model(&models.RecognitionLog{}).Where("is_correct = ?", true).Count(&correctFeedbacks)

	var avgProcessingTime float64
	config.DB.Model(&models.RecognitionLog{}).Select("AVG(processing_time)").Scan(&avgProcessingTime)

	var totalBeverages int64
	var verifiedBeverages int64
	config.DB.Model(&models.Beverage{}).Count(&totalBeverages)
	config.DB.Model(&models.Beverage{}).Where("is_verified = ?", true).Count(&verifiedBeverages)

	c.JSON(http.StatusOK, gin.H{
		"total_recognitions":     totalLogs,
		"vision_api_calls":       visionAPIUsed,
		"correct_feedbacks":      correctFeedbacks,
		"avg_processing_time_ms": int(avgProcessingTime),
		"total_beverages":        totalBeverages,
		"verified_beverages":     verifiedBeverages,
		"cache_hit_rate":         float64(totalLogs-visionAPIUsed) / float64(max(totalLogs, 1)) * 100,
	})
}

func max(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
