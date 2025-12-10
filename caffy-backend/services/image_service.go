package services

import (
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// GetImageUploadPath : 이미지 저장 경로 (환경변수에서 가져옴)
func GetImageUploadPath() string {
	// 사용자 요청: D드라이브 caffy 이미지 폴더
	return "D:\\caffy\\images"
}

// InitImageStorage : 이미지 저장 폴더 초기화
func InitImageStorage() error {
	return os.MkdirAll(GetImageUploadPath(), 0755)
}

// SaveImage : 이미지 파일 저장
func SaveImage(imageData []byte, userID uint, drinkName string) (string, error) {
	// 기본 경로 가져오기
	basePath := GetImageUploadPath()

	// 유저별 폴더 경로: D:\caffy\images\{userID}
	userDir := filepath.Join(basePath, fmt.Sprintf("%d", userID))

	// 폴더 생성 확인
	if err := os.MkdirAll(userDir, 0755); err != nil {
		return "", fmt.Errorf("폴더 생성 실패: %v", err)
	}

	// 파일명 생성 (YYYYMMDD_HHMMSS_DrinkName.jpg)
	// 음료명에 파일시스템에 사용할 수 없는 문자가 있을 수 있으므로 치환
	safeDrinkName := strings.ReplaceAll(drinkName, " ", "_")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "/", "_")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "\\", "_")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, ":", "")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "*", "")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "?", "")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "\"", "")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "<", "")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, ">", "")
	safeDrinkName = strings.ReplaceAll(safeDrinkName, "|", "")

	if safeDrinkName == "" {
		safeDrinkName = "unknown"
	}

	timestamp := time.Now().Format("20060102_150405")
	filename := fmt.Sprintf("%s_%s.jpg", timestamp, safeDrinkName)
	filePath := filepath.Join(userDir, filename)

	// 파일 저장
	if err := os.WriteFile(filePath, imageData, 0644); err != nil {
		return "", fmt.Errorf("파일 저장 실패: %v", err)
	}

	return filePath, nil
}

// CalculateImageHash : 이미지의 MD5 해시 계산 (간단한 중복 체크용)
// 실제 프로덕션에서는 pHash(perceptual hash) 사용 권장
func CalculateImageHash(imageData []byte) string {
	hash := md5.Sum(imageData)
	return hex.EncodeToString(hash[:])
}

// DeleteImage : 이미지 파일 삭제
func DeleteImage(filePath string) error {
	return os.Remove(filePath)
}

// GetImageData : 이미지 파일 읽기
func GetImageData(filePath string) ([]byte, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	return io.ReadAll(file)
}
