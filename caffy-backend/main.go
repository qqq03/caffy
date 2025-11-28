package main

import (
	"caffy-backend/config"
	"caffy-backend/controllers"
	"caffy-backend/services"
	"log"

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

	// 정적 파일 서빙 (업로드된 이미지)
	r.Static("/uploads", config.UploadPath)

	// 4. API 라우팅 정의
	api := r.Group("/api")
	{
		// 기존 API
		api.POST("/users", controllers.CreateUser)           // 사용자 등록
		api.POST("/logs", controllers.AddLog)                // 마심
		api.GET("/status/:id", controllers.GetCurrentStatus) // 내 상태 확인

		// 이미지 인식 API
		api.POST("/recognize", controllers.RecognizeImage) // 이미지로 음료 인식

		// 음료 관리 API
		api.GET("/beverages", controllers.GetAllBeverages)        // 전체 음료 목록
		api.GET("/beverages/search", controllers.SearchBeverages) // 음료 검색
		api.GET("/beverages/:id", controllers.GetBeverage)        // 특정 음료 조회
		api.POST("/beverages", controllers.CreateBeverage)        // 음료 등록
		api.PUT("/beverages/:id", controllers.UpdateBeverage)     // 음료 수정

		// 피드백 & 통계
		api.POST("/feedback", controllers.SubmitFeedback)              // 인식 피드백
		api.GET("/stats/recognition", controllers.GetRecognitionStats) // 인식 통계
	}

	// 6. 서버 실행
	log.Printf("🚀 서버 시작: http://localhost:%s", config.ServerPort)
	r.Run(":" + config.ServerPort)
}
