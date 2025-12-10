package services

import (
	"caffy-backend/config"
	"caffy-backend/models"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"time"
)

// SmartRecognitionResult : 스마트 인식 결과
type SmartRecognitionResult struct {
	Found          bool    `json:"found"`
	DrinkName      string  `json:"drink_name"`
	CaffeineAmount int     `json:"caffeine_amount"`
	Confidence     float64 `json:"confidence"`
	Source         string  `json:"source"` // "database", "llm", "manual"
	Description    string  `json:"description"`
	Brand          string  `json:"brand"`
	Category       string  `json:"category"`
	ImageID        uint    `json:"image_id,omitempty"` // 저장된 이미지 ID
	IsNew          bool    `json:"is_new"`             // 새로 학습된 데이터인지
}

// SmartRecognizeDrink : DB 우선 검색 → LLM 폴백 → 결과 저장
func SmartRecognizeDrink(imageBase64 string, userID uint) (*SmartRecognitionResult, error) {
	result := &SmartRecognitionResult{}

	// 1. 이미지 해시 계산
	imageHash := calculateHash(imageBase64)

	// 2. DB에서 해시로 검색 (정확히 일치하는 이미지)
	var existingImage models.BeverageImage
	if err := config.DB.Where("image_hash = ?", imageHash).First(&existingImage).Error; err == nil {
		// DB에서 찾음! (비용 0)
		existingImage.UsageCount++
		config.DB.Save(&existingImage)

		result.Found = true
		result.DrinkName = existingImage.DrinkName
		result.CaffeineAmount = existingImage.CaffeineAmount
		result.Confidence = existingImage.Confidence
		result.Source = "database"
		result.ImageID = existingImage.ID
		result.IsNew = false

		// Beverage 정보 가져오기
		if existingImage.BeverageID != nil {
			var beverage models.Beverage
			if config.DB.First(&beverage, existingImage.BeverageID).Error == nil {
				result.Brand = beverage.Brand
				result.Category = beverage.Category
			}
		}

		// 사용자 요청: 이미지를 로컬에 저장 (히스토리용)
		decodedImage, _ := base64.StdEncoding.DecodeString(imageBase64)
		SaveImage(decodedImage, userID, result.DrinkName)

		logSmartRecognition(userID, imageHash, "database", result.CaffeineAmount, result.Confidence)
		return result, nil
	}

	// 3. DB에서 못 찾음 → LLM 호출 (비용 발생)
	llmResult, err := RecognizeDrinkWithLLM(imageBase64)
	if err != nil {
		// LLM 실패 시 OpenAI로 폴백 시도
		llmResult, err = RecognizeDrinkWithOpenAI(imageBase64)
		if err != nil {
			return nil, err
		}
	}

	// 4. LLM 결과를 DB에 저장 (학습)
	newImage := models.BeverageImage{
		ImageHash:      imageHash,
		DrinkName:      llmResult.DrinkName,
		CaffeineAmount: llmResult.CaffeineAmount,
		Confidence:     llmResult.Confidence,
		Source:         "llm",
		UsageCount:     1,
		UploadedByUser: userID,
	}

	// 사용자 요청: 이미지를 로컬에 저장
	decodedImage, _ := base64.StdEncoding.DecodeString(imageBase64)
	imagePath, _ := SaveImage(decodedImage, userID, llmResult.DrinkName)
	newImage.ImagePath = imagePath

	// 브랜드가 있으면 Beverage 테이블에서 찾거나 생성
	if llmResult.Brand != "" {
		var beverage models.Beverage
		if err := config.DB.Where("name = ? OR brand = ?", llmResult.DrinkName, llmResult.Brand).First(&beverage).Error; err == nil {
			newImage.BeverageID = &beverage.ID
		} else {
			// 새 음료 생성
			newBeverage := models.Beverage{
				Name:           llmResult.DrinkName,
				Brand:          llmResult.Brand,
				CaffeineAmount: float64(llmResult.CaffeineAmount),
				Category:       llmResult.Category,
				IsVerified:     false,
			}
			config.DB.Create(&newBeverage)
			newImage.BeverageID = &newBeverage.ID
		}
	}

	config.DB.Create(&newImage)

	result.Found = llmResult.CaffeineAmount > 0
	result.DrinkName = llmResult.DrinkName
	result.CaffeineAmount = llmResult.CaffeineAmount
	result.Confidence = llmResult.Confidence
	result.Source = "llm"
	result.Description = llmResult.Description
	result.Brand = llmResult.Brand
	result.Category = llmResult.Category
	result.ImageID = newImage.ID
	result.IsNew = true

	logSmartRecognition(userID, imageHash, "llm", result.CaffeineAmount, result.Confidence)
	return result, nil
}

// calculateHash : 이미지 Base64의 SHA256 해시
func calculateHash(imageBase64 string) string {
	hash := sha256.Sum256([]byte(imageBase64))
	return hex.EncodeToString(hash[:])
}

// logSmartRecognition : 인식 로그 저장
func logSmartRecognition(userID uint, imageHash string, source string, caffeineAmount int, confidence float64) {
	log := models.RecognitionLog{
		UserID:         userID,
		ImagePath:      imageHash,
		Confidence:     confidence,
		VisionAPIUsed:  source == "llm",
		ProcessingTime: int(time.Now().UnixMilli() % 10000), // 간단한 타임스탬프
	}
	config.DB.Create(&log)
}

// GetRecognitionStats : 인식 통계
func GetSmartRecognitionStats() map[string]interface{} {
	var totalImages int64
	var dbHits int64
	var llmCalls int64

	config.DB.Model(&models.BeverageImage{}).Count(&totalImages)
	config.DB.Model(&models.BeverageImage{}).Where("source = ?", "database").Count(&dbHits)
	config.DB.Model(&models.BeverageImage{}).Where("source = ?", "llm").Count(&llmCalls)

	// 가장 많이 인식된 음료 Top 5
	var topDrinks []struct {
		DrinkName  string
		UsageCount int
	}
	config.DB.Model(&models.BeverageImage{}).
		Select("drink_name, SUM(usage_count) as usage_count").
		Group("drink_name").
		Order("usage_count DESC").
		Limit(5).
		Find(&topDrinks)

	return map[string]interface{}{
		"total_learned_images": totalImages,
		"db_hit_count":         dbHits,
		"llm_call_count":       llmCalls,
		"top_drinks":           topDrinks,
	}
}
