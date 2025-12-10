package models

import (
	"time"

	"gorm.io/gorm"
)

// User : 사용자 정보
type User struct {
	gorm.Model
	Email           string  `json:"email" gorm:"type:varchar(255);uniqueIndex"`
	Password        string  `json:"-" gorm:"type:varchar(255)"` // JSON 응답에서 제외
	Nickname        string  `json:"nickname"`
	Weight          float64 `json:"weight"`            // 체중 (kg)
	Height          float64 `json:"height"`            // 키 (cm)
	Gender          int     `json:"gender"`            // 0:남성, 1:여성
	IsSmoker        bool    `json:"is_smoker"`         // 흡연 여부
	IsPregnant      bool    `json:"is_pregnant"`       // 임신 여부 (여성만 해당)
	ExercisePerWeek int     `json:"exercise_per_week"` // 주당 운동 횟수
	MetabolismType  int     `json:"metabolism_type"`   // 0:Normal(5h), 1:Fast(3h), 2:Slow(8h)

	// 개인화된 학습 파라미터
	PersonalHalfLife   float64 `json:"personal_half_life" gorm:"default:5.0"` // 학습된 개인 반감기 (시간)
	LearningConfidence float64 `json:"learning_confidence" gorm:"default:0"`  // 학습 신뢰도 (0~1)
	TotalFeedbacks     int     `json:"total_feedbacks" gorm:"default:0"`      // 누적 피드백 횟수

	// 사용자 설정
	ViewPeriodDays int `json:"view_period_days" gorm:"default:7"` // 조회 기간 (일): 1, 3, 7

	Logs           []CaffeineLog      `json:"logs"`            // 1:N 관계
	SenseFeedbacks []CaffeineFeedback `json:"sense_feedbacks"` // 체감 피드백
}

// LoginRequest : 로그인 요청
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

// RegisterRequest : 회원가입 요청
type RegisterRequest struct {
	Email           string  `json:"email" binding:"required,email"`
	Password        string  `json:"password" binding:"required,min=6"`
	Nickname        string  `json:"nickname"`
	Weight          float64 `json:"weight"`
	Height          float64 `json:"height"`            // 키 (cm)
	Gender          int     `json:"gender"`            // 0:남성, 1:여성
	IsSmoker        bool    `json:"is_smoker"`         // 흡연 여부
	IsPregnant      bool    `json:"is_pregnant"`       // 임신 여부
	ExercisePerWeek int     `json:"exercise_per_week"` // 주당 운동 횟수
	MetabolismType  int     `json:"metabolism_type"`
}

// AuthResponse : 인증 응답
type AuthResponse struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

// CaffeineLog : 섭취 기록
type CaffeineLog struct {
	gorm.Model
	UserID         uint      `json:"user_id"`
	DrinkName      string    `json:"drink_name"`                      // 예: 아메리카노
	OriginalAmount float64   `json:"original_amount"`                 // 원래 카페인 함량 (mg)
	ConsumedRatio  float64   `json:"consumed_ratio" gorm:"default:1"` // 실제 마신 비율 (0.0~1.0)
	Amount         float64   `json:"amount"`                          // 실제 섭취량 (original * ratio)
	IntakeAt       time.Time `json:"intake_at"`                       // 실제 마신 시간
	BeverageID     *uint     `json:"beverage_id"`                     // 인식된 음료 ID (nullable)
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
	BeverageID     *uint   `json:"beverage_id" gorm:"index"`                 // 연결된 음료 ID (nullable)
	ImageHash      string  `json:"image_hash" gorm:"type:varchar(64);index"` // 이미지 해시 (pHash)
	ImagePath      string  `json:"image_path" gorm:"type:varchar(500)"`      // 저장된 이미지 경로
	DrinkName      string  `json:"drink_name" gorm:"type:varchar(255)"`      // 음료 이름 (LLM 인식 결과)
	CaffeineAmount int     `json:"caffeine_amount"`                          // 카페인량 (mg)
	OCRText        string  `json:"ocr_text" gorm:"type:text"`                // OCR로 추출된 텍스트
	Labels         string  `json:"labels" gorm:"type:text"`                  // Vision API 라벨 (JSON)
	Logos          string  `json:"logos" gorm:"type:varchar(255)"`           // 인식된 로고
	Confidence     float64 `json:"confidence"`                               // 인식 신뢰도 (0~1)
	Source         string  `json:"source" gorm:"type:varchar(20)"`           // "user", "llm", "admin"
	UsageCount     int     `json:"usage_count" gorm:"default:0"`             // 사용 횟수 (인기도)
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

// ========================================
// 개인별 카페인 대사 학습 모델
// ========================================

// CaffeineFeedback : 사용자 체감 피드백 (학습 데이터)
type CaffeineFeedback struct {
	gorm.Model
	UserID            uint      `json:"user_id" gorm:"index"`
	FeedbackAt        time.Time `json:"feedback_at"`                               // 피드백 시점
	SenseLevel        int       `json:"sense_level"`                               // 체감 각성도 (1~5: 졸림~매우각성)
	PredictedLevel    float64   `json:"predicted_level"`                           // 예측된 카페인 잔류량 (mg)
	ActualFeeling     string    `json:"actual_feeling" gorm:"type:varchar(100)"`   // 실제 느낌 (텍스트)
	HoursAfterLast    float64   `json:"hours_after_last"`                          // 마지막 섭취 후 경과 시간
	LastIntakeAmount  float64   `json:"last_intake_amount"`                        // 마지막 섭취량
	IsUsedForLearning bool      `json:"is_used_for_learning" gorm:"default:false"` // 학습에 사용됨
}

// LearningHistory : 학습 히스토리 (모델 버전 관리)
type LearningHistory struct {
	gorm.Model
	UserID           uint    `json:"user_id" gorm:"index"`
	PreviousHalfLife float64 `json:"previous_half_life"`              // 이전 반감기
	NewHalfLife      float64 `json:"new_half_life"`                   // 새 반감기
	DataPointsUsed   int     `json:"data_points_used"`                // 사용된 데이터 포인트 수
	Improvement      float64 `json:"improvement"`                     // 개선도 (MSE 감소율)
	Reason           string  `json:"reason" gorm:"type:varchar(255)"` // 학습 이유
}

// PersonalModel : 개인별 확장 대사 모델 (고급)
type PersonalModel struct {
	gorm.Model
	UserID uint `json:"user_id" gorm:"uniqueIndex"`

	// 기본 파라미터
	BaseHalfLife      float64 `json:"base_half_life" gorm:"default:5.0"`     // 기본 반감기
	AbsorptionRate    float64 `json:"absorption_rate" gorm:"default:1.0"`    // 흡수율 (0.5~1.5)
	SensitivityFactor float64 `json:"sensitivity_factor" gorm:"default:1.0"` // 민감도 (0.5~2.0)

	// 시간대별 보정
	MorningModifier   float64 `json:"morning_modifier" gorm:"default:1.0"`   // 오전 보정 (6-12시)
	AfternoonModifier float64 `json:"afternoon_modifier" gorm:"default:1.0"` // 오후 보정 (12-18시)
	EveningModifier   float64 `json:"evening_modifier" gorm:"default:1.0"`   // 저녁 보정 (18-24시)

	// 학습 메타데이터
	LastTrainedAt     time.Time `json:"last_trained_at"`
	TrainingDataCount int       `json:"training_data_count"`
	ModelAccuracy     float64   `json:"model_accuracy"` // 모델 정확도 (0~1)
	ModelVersion      int       `json:"model_version" gorm:"default:1"`
}
