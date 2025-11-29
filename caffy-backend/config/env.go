package config

import (
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

// 환경변수 값들
var (
	// DB 설정
	DBUsername string
	DBPassword string
	DBHost     string
	DBPort     string
	DBName     string

	// Google Vision API
	GoogleVisionAPIKey string

	// 서버 설정
	ServerPort     string
	GinMode        string
	AllowedOrigins []string // CORS 허용 Origin 목록

	// 업로드 설정
	UploadPath     string
	MaxImageSizeMB int

	// JWT 설정
	JWTSecret      string
	JWTExpireHours int
)

// LoadEnv : .env 파일에서 환경변수 로드
func LoadEnv() {
	// .env 파일 로드 (없으면 시스템 환경변수 사용)
	err := godotenv.Load()
	if err != nil {
		log.Println("⚠️ .env 파일을 찾을 수 없습니다. 시스템 환경변수를 사용합니다.")
	} else {
		log.Println("✅ .env 파일 로드 완료")
	}

	// DB 설정
	DBUsername = getEnv("DB_USERNAME", "root")
	DBPassword = getEnv("DB_PASSWORD", "")
	DBHost = getEnv("DB_HOST", "127.0.0.1")
	DBPort = getEnv("DB_PORT", "3306")
	DBName = getEnv("DB_NAME", "caffy_db")

	// Google Vision API
	GoogleVisionAPIKey = getEnv("GOOGLE_VISION_API_KEY", "")

	// 서버 설정
	ServerPort = getEnv("SERVER_PORT", "8080")
	GinMode = getEnv("GIN_MODE", "debug")
	AllowedOrigins = getEnvAsSlice("ALLOWED_ORIGINS", []string{"http://localhost:8080", "http://localhost:3000"})

	// 업로드 설정
	UploadPath = getEnv("UPLOAD_PATH", "./uploads/images")
	MaxImageSizeMB = getEnvAsInt("MAX_IMAGE_SIZE_MB", 10)

	// JWT 설정
	JWTSecret = getEnv("JWT_SECRET", "your-secret-key-change-in-production")
	JWTExpireHours = getEnvAsInt("JWT_EXPIRE_HOURS", 72)
}

// getEnv : 환경변수 가져오기 (기본값 지원)
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvAsInt : 환경변수를 int로 가져오기
func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

// getEnvAsSlice : 환경변수를 슬라이스로 가져오기 (쉼표로 구분)
func getEnvAsSlice(key string, defaultValue []string) []string {
	if value := os.Getenv(key); value != "" {
		var result []string
		for _, s := range strings.Split(value, ",") {
			trimmed := strings.TrimSpace(s)
			if trimmed != "" {
				result = append(result, trimmed)
			}
		}
		if len(result) > 0 {
			return result
		}
	}
	return defaultValue
}

// GetDSN : MySQL 연결 문자열 생성
func GetDSN() string {
	return DBUsername + ":" + DBPassword + "@tcp(" + DBHost + ":" + DBPort + ")/" + DBName + "?charset=utf8mb4&parseTime=True&loc=Local"
}
