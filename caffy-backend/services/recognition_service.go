package services

import (
	"caffy-backend/config"
	"caffy-backend/models"
	"encoding/json"
	"strings"
	"time"
)

// RecognitionResult : 인식 결과
type RecognitionResult struct {
	Found          bool             `json:"found"`           // DB에서 찾았는지
	Beverage       *models.Beverage `json:"beverage"`        // 찾은 음료 정보
	Confidence     float64          `json:"confidence"`      // 신뢰도 (0~1)
	VisionAPIUsed  bool             `json:"vision_api_used"` // Vision API 사용 여부
	OCRText        string           `json:"ocr_text"`        // OCR 결과
	DetectedLabels []string         `json:"detected_labels"` // 감지된 라벨
	DetectedLogos  []string         `json:"detected_logos"`  // 감지된 로고
	IsNewBeverage  bool             `json:"is_new_beverage"` // 새로 등록된 음료인지
}

// RecognizeBeverage : 이미지로 음료 인식
func RecognizeBeverage(imageData []byte, userID uint) (*RecognitionResult, error) {
	startTime := time.Now()
	result := &RecognitionResult{}

	// 1. 이미지 해시 계산
	imageHash := CalculateImageHash(imageData)

	// 2. DB에서 해시로 먼저 검색 (빠른 매칭)
	var existingImage models.BeverageImage
	if err := config.DB.Where("image_hash = ?", imageHash).
		Preload("Beverage").First(&existingImage).Error; err == nil {
		// 정확히 일치하는 이미지 발견!
		var beverage models.Beverage
		config.DB.First(&beverage, existingImage.BeverageID)

		result.Found = true
		result.Beverage = &beverage
		result.Confidence = 1.0
		result.VisionAPIUsed = false

		logRecognition(userID, "", &beverage.ID, 1.0, false, int(time.Since(startTime).Milliseconds()))
		return result, nil
	}

	// 3. DB에서 못 찾았으면 Vision API 호출
	visionResult, err := AnalyzeImage(imageData)
	if err != nil {
		return nil, err
	}

	result.VisionAPIUsed = true
	result.OCRText = visionResult.FullText
	result.DetectedLogos = visionResult.Logos

	// 라벨 문자열 추출
	for _, label := range visionResult.Labels {
		result.DetectedLabels = append(result.DetectedLabels, label.Description)
	}

	// 4. OCR 텍스트와 로고로 DB 검색
	beverage := findBeverageByVisionResult(visionResult)

	if beverage != nil {
		result.Found = true
		result.Beverage = beverage
		result.Confidence = 0.8 // Vision API 결과는 약간 낮은 신뢰도

		// 이 이미지를 해당 음료에 연결하여 저장 (학습)
		saveNewBeverageImage(beverage.ID, imageHash, imageData, visionResult, userID)

		logRecognition(userID, "", &beverage.ID, 0.8, true, int(time.Since(startTime).Milliseconds()))
	} else {
		// 5. DB에 없으면 새 음료 등록
		newBeverage := createNewBeverageFromVision(visionResult)
		if newBeverage != nil {
			result.Found = true
			result.Beverage = newBeverage
			result.Confidence = 0.5 // 새로 등록된 건 낮은 신뢰도
			result.IsNewBeverage = true

			// 이미지도 저장
			saveNewBeverageImage(newBeverage.ID, imageHash, imageData, visionResult, userID)

			logRecognition(userID, "", &newBeverage.ID, 0.5, true, int(time.Since(startTime).Milliseconds()))
		} else {
			result.Found = false
			logRecognition(userID, "", nil, 0, true, int(time.Since(startTime).Milliseconds()))
		}
	}

	return result, nil
}

// findBeverageByVisionResult : Vision API 결과로 DB에서 음료 검색
func findBeverageByVisionResult(vision *VisionResult) *models.Beverage {
	var beverage models.Beverage

	// 1. 로고로 브랜드 검색
	for _, logo := range vision.Logos {
		if err := config.DB.Where("LOWER(brand) LIKE ?", "%"+strings.ToLower(logo)+"%").
			First(&beverage).Error; err == nil {
			return &beverage
		}
	}

	// 2. OCR 텍스트에서 음료 이름 검색
	ocrLower := strings.ToLower(vision.FullText)

	// 알려진 음료 패턴 검색
	knownPatterns := []string{
		"아메리카노", "americano",
		"라떼", "latte",
		"카푸치노", "cappuccino",
		"에스프레소", "espresso",
		"콜드브루", "cold brew",
		"모카", "mocha",
		"마끼아또", "macchiato",
		"레드불", "red bull",
		"몬스터", "monster",
		"핫식스", "hot6",
	}

	for _, pattern := range knownPatterns {
		if strings.Contains(ocrLower, pattern) {
			if err := config.DB.Where("LOWER(name) LIKE ?", "%"+pattern+"%").
				First(&beverage).Error; err == nil {
				return &beverage
			}
		}
	}

	// 3. 이미지의 OCR 텍스트로 기존 이미지 검색
	var existingImage models.BeverageImage
	if err := config.DB.Where("ocr_text LIKE ?", "%"+vision.FullText[:min(50, len(vision.FullText))]+"%").
		First(&existingImage).Error; err == nil {
		config.DB.First(&beverage, existingImage.BeverageID)
		return &beverage
	}

	return nil
}

// createNewBeverageFromVision : Vision 결과로 새 음료 생성
func createNewBeverageFromVision(vision *VisionResult) *models.Beverage {
	caffeineAmount, productName := ExtractCaffeineInfo(vision.FullText)

	if productName == "" {
		// 라벨에서 음료 관련 키워드 찾기
		for _, label := range vision.Labels {
			lower := strings.ToLower(label.Description)
			if strings.Contains(lower, "coffee") || strings.Contains(lower, "drink") ||
				strings.Contains(lower, "beverage") || strings.Contains(lower, "energy") {
				productName = label.Description
				break
			}
		}
	}

	if productName == "" {
		return nil // 음료를 식별할 수 없음
	}

	// 브랜드 추출 (로고에서)
	brand := ""
	if len(vision.Logos) > 0 {
		brand = vision.Logos[0]
	}

	// 카테고리 추정
	category := guessCategoryFromLabels(vision.Labels)

	// 기본 카페인 함량 설정 (추출 못했을 경우)
	if caffeineAmount == 0 {
		caffeineAmount = getDefaultCaffeine(category)
	}

	newBeverage := models.Beverage{
		Name:           productName,
		Brand:          brand,
		CaffeineAmount: caffeineAmount,
		Category:       category,
		IsVerified:     false, // 사용자 제보이므로 미검증
	}

	config.DB.Create(&newBeverage)
	return &newBeverage
}

// saveNewBeverageImage : 새 이미지를 음료에 연결하여 저장
func saveNewBeverageImage(beverageID uint, imageHash string, imageData []byte, vision *VisionResult, userID uint) {
	imagePath, err := SaveImage(imageData, userID)
	if err != nil {
		return
	}

	labelsJSON, _ := json.Marshal(vision.Labels)
	logos := strings.Join(vision.Logos, ",")

	image := models.BeverageImage{
		BeverageID:     beverageID,
		ImageHash:      imageHash,
		ImagePath:      imagePath,
		OCRText:        vision.FullText,
		Labels:         string(labelsJSON),
		Logos:          logos,
		Confidence:     0.8,
		UploadedByUser: userID,
	}

	config.DB.Create(&image)
}

// logRecognition : 인식 로그 저장
func logRecognition(userID uint, imagePath string, recognizedID *uint, confidence float64, visionUsed bool, processingTime int) {
	log := models.RecognitionLog{
		UserID:         userID,
		ImagePath:      imagePath,
		RecognizedID:   recognizedID,
		Confidence:     confidence,
		VisionAPIUsed:  visionUsed,
		ProcessingTime: processingTime,
	}
	config.DB.Create(&log)
}

// guessCategoryFromLabels : 라벨에서 카테고리 추정
func guessCategoryFromLabels(labels []LabelResult) string {
	for _, label := range labels {
		lower := strings.ToLower(label.Description)
		if strings.Contains(lower, "coffee") {
			return "커피"
		}
		if strings.Contains(lower, "energy drink") || strings.Contains(lower, "energy") {
			return "에너지드링크"
		}
		if strings.Contains(lower, "tea") {
			return "차"
		}
		if strings.Contains(lower, "soda") || strings.Contains(lower, "cola") {
			return "탄산음료"
		}
	}
	return "기타"
}

// getDefaultCaffeine : 카테고리별 기본 카페인 함량
func getDefaultCaffeine(category string) float64 {
	defaults := map[string]float64{
		"커피":     100,
		"에너지드링크": 80,
		"차":      30,
		"탄산음료":   35,
		"기타":     50,
	}
	if val, ok := defaults[category]; ok {
		return val
	}
	return 50
}

// Helper function
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
