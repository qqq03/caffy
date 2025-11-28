package config

import (
	"caffy-backend/models"
	"log"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

var DB *gorm.DB

func Connect() {
	// .env에서 로드된 환경변수 사용
	dsn := GetDSN()

	// GORM 연결 시도
	database, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})

	if err != nil {
		// 연결 실패 시 에러 로그 출력하고 프로그램 종료
		log.Fatal("❌ MySQL 연결 실패! .env 파일을 확인해주세요: ", err)
	}

	log.Println("✅ MySQL 연결 성공!")

	// 테이블 자동 생성 (Auto Migration)
	// User, CaffeineLog 테이블이 없으면 자동으로 생성해줍니다.
	database.AutoMigrate(
		&models.User{},
		&models.CaffeineLog{},
		&models.Beverage{},       // 음료 마스터 데이터
		&models.BeverageImage{},  // 음료 이미지 인식 데이터
		&models.RecognitionLog{}, // 인식 시도 로그
	)

	DB = database
}
