package main

import (
	"caffy-backend/config"
	"caffy-backend/controllers"
	"caffy-backend/middleware"
	"caffy-backend/services"
	"log"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

func main() {
	// 1. 환경변수 로드 (.env 파일)
	config.LoadEnv()

	// 2. DB 연결
	config.Connect()

	// 3. 이미지 저장소 초기화
	services.InitImageStorage()

	// 4. Gin 모드 설정
	gin.SetMode(config.GinMode)

	// 5. Gin 라우터 설정
	r := gin.Default()

	// CORS 설정 (Flutter 웹 앱 허용)
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		AllowCredentials: true,
	}))

	// 정적 파일 서빙 (업로드된 이미지)
	r.Static("/uploads", config.UploadPath)

	// API 라우팅 정의
	api := r.Group("/api")
	{
		// ========== 인증 API (공개) ==========
		api.POST("/auth/register", controllers.Register) // 회원가입
		api.POST("/auth/login", controllers.Login)       // 로그인

		// ========== 인증 필요 API ==========
		protected := api.Group("")
		protected.Use(middleware.AuthMiddleware())
		{
			// 사용자 정보
			protected.GET("/me", controllers.GetMe)                    // 내 정보 조회
			protected.PUT("/me", controllers.UpdateMe)                 // 내 정보 수정
			protected.POST("/me/password", controllers.ChangePassword) // 비밀번호 변경

			// 카페인 관련
			protected.POST("/logs", controllers.AddLog)                  // 마심
			protected.GET("/logs", controllers.GetMyLogs)                // 섭취 기록 히스토리
			protected.PUT("/logs/:id", controllers.UpdateLog)            // 섭취 기록 수정
			protected.DELETE("/logs/:id", controllers.DeleteLog)         // 섭취 기록 삭제
			protected.GET("/status", controllers.GetMyStatus)            // 내 상태 확인 (토큰 기반)
			protected.PUT("/settings/period", controllers.SetViewPeriod) // 조회 기간 설정

			// 이미지 인식 API
			protected.POST("/recognize", controllers.RecognizeImage)            // 이미지로 음료 인식 (기존)
			protected.POST("/recognize/smart", controllers.SmartRecognizeImage) // 스마트 인식 (DB→LLM)

			// 피드백
			protected.POST("/feedback", controllers.SubmitFeedback) // 인식 피드백

			// ========== 개인별 학습 API ==========
			protected.POST("/learning/feedback", controllers.SubmitSenseFeedback)        // 체감 피드백 제출
			protected.GET("/learning/stats", controllers.GetLearningStats)               // 학습 통계 조회
			protected.POST("/learning/train", controllers.TriggerBatchLearning)          // 배치 학습
			protected.GET("/learning/prediction", controllers.GetPersonalizedPrediction) // 개인화 예측
		}

		// ========== 공개 API ==========
		// 음료 정보 조회 (인증 불필요)
		api.GET("/beverages", controllers.GetAllBeverages)        // 전체 음료 목록
		api.GET("/beverages/search", controllers.SearchBeverages) // 음료 검색
		api.GET("/beverages/:id", controllers.GetBeverage)        // 특정 음료 조회
		api.POST("/beverages", controllers.CreateBeverage)        // 음료 등록
		api.PUT("/beverages/:id", controllers.UpdateBeverage)     // 음료 수정

		// 통계
		api.GET("/stats/recognition", controllers.GetRecognitionStats) // 인식 통계
	}

	// 6. 서버 실행
	log.Printf("🚀 서버 시작: http://localhost:%s", config.ServerPort)
	r.Run(":" + config.ServerPort)
}
