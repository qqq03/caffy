package models

import (
	"time"

	"gorm.io/gorm"
)

// User : 사용자 정보
type User struct {
	gorm.Model
	Email          string        `json:"email" gorm:"type:varchar(255);uniqueIndex"`
	Password       string        `json:"-" gorm:"type:varchar(255)"` // JSON 응답에서 제외
	Nickname       string        `json:"nickname"`
	Weight         float64       `json:"weight"`          // 체중 (kg)
	MetabolismType int           `json:"metabolism_type"` // 0:Normal(5h), 1:Fast(3h), 2:Slow(8h)
	Logs           []CaffeineLog `json:"logs"`            // 1:N 관계
}

// LoginRequest : 로그인 요청
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

// RegisterRequest : 회원가입 요청
type RegisterRequest struct {
	Email          string  `json:"email" binding:"required,email"`
	Password       string  `json:"password" binding:"required,min=6"`
	Nickname       string  `json:"nickname" binding:"required"`
	Weight         float64 `json:"weight"`
	MetabolismType int     `json:"metabolism_type"`
}

// AuthResponse : 인증 응답
type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

// CaffeineLog : 섭취 기록
type CaffeineLog struct {
	gorm.Model
	UserID     uint      `json:"user_id"`
	DrinkName  string    `json:"drink_name"`  // 예: 아메리카노
	Amount     float64   `json:"amount"`      // 카페인 함량 (mg)
	IntakeAt   time.Time `json:"intake_at"`   // 실제 마신 시간
	BeverageID *uint     `json:"beverage_id"` // 인식된 음료 ID (nullable)
}

// ========================================
// 음료 인식 관련 모델
// ========================================

// Beverage : 음료 정보 (마스터 데이터)
type Beverage struct {
	gorm.Model
	Name           string          `json:"name" gorm:"type:varchar(255);uniqueIndex"` // 음료 이름 (예: 스타벅스 아메리카노)
	Brand          string          `json:"brand" gorm:"type:varchar(100)"`            // 브랜드 (예: 스타벅스, 이디야)
	CaffeineAmount float64         `json:"caffeine_amount"`                           // 카페인 함량 (mg)
	Size           string          `json:"size" gorm:"type:varchar(50)"`              // 사이즈 (Tall, Grande 등)
	Volume         float64         `json:"volume"`                                    // 용량 (ml)
	Category       string          `json:"category" gorm:"type:varchar(50)"`          // 카테고리 (커피, 에너지드링크, 차 등)
	IsVerified     bool            `json:"is_verified" gorm:"default:false"`          // 검증된 데이터 여부
	Images         []BeverageImage `json:"images"`                                    // 1:N 관계
}

// BeverageImage : 음료 이미지 인식 데이터
type BeverageImage struct {
	gorm.Model
	BeverageID     uint    `json:"beverage_id" gorm:"index"`                 // 연결된 음료 ID
	ImageHash      string  `json:"image_hash" gorm:"type:varchar(64);index"` // 이미지 해시 (pHash)
	ImagePath      string  `json:"image_path" gorm:"type:varchar(500)"`      // 저장된 이미지 경로
	OCRText        string  `json:"ocr_text" gorm:"type:text"`                // OCR로 추출된 텍스트
	Labels         string  `json:"labels" gorm:"type:text"`                  // Vision API 라벨 (JSON)
	Logos          string  `json:"logos" gorm:"type:varchar(255)"`           // 인식된 로고
	Confidence     float64 `json:"confidence"`                               // 인식 신뢰도 (0~1)
	UploadedByUser uint    `json:"uploaded_by_user"`                         // 업로드한 사용자 ID
}

// RecognitionLog : 인식 시도 로그 (학습 데이터용)
type RecognitionLog struct {
	gorm.Model
	UserID         uint    `json:"user_id" gorm:"index"`
	ImagePath      string  `json:"image_path" gorm:"type:varchar(500)"` // 원본 이미지 경로
	RecognizedID   *uint   `json:"recognized_id"`                       // 인식된 음료 ID (실패시 null)
	Confidence     float64 `json:"confidence"`                          // 인식 신뢰도
	IsCorrect      *bool   `json:"is_correct"`                          // 사용자 피드백 (맞음/틀림)
	CorrectedID    *uint   `json:"corrected_id"`                        // 사용자가 수정한 음료 ID
	VisionAPIUsed  bool    `json:"vision_api_used"`                     // Vision API 사용 여부
	ProcessingTime int     `json:"processing_time"`                     // 처리 시간 (ms)
}
