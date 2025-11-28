package services

import (
	"caffy-backend/config"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

// GetImageUploadPath : 이미지 저장 경로 (환경변수에서 가져옴)
func GetImageUploadPath() string {
	return config.UploadPath
}

// InitImageStorage : 이미지 저장 폴더 초기화
func InitImageStorage() error {
	return os.MkdirAll(GetImageUploadPath(), 0755)
}

// SaveImage : 이미지 파일 저장
func SaveImage(imageData []byte, userID uint) (string, error) {
	// 폴더 생성 확인
	if err := InitImageStorage(); err != nil {
		return "", fmt.Errorf("폴더 생성 실패: %v", err)
	}

	// 파일명 생성 (timestamp_userid_hash.jpg)
	hash := CalculateImageHash(imageData)
	filename := fmt.Sprintf("%d_%d_%s.jpg", time.Now().Unix(), userID, hash[:8])
	filePath := filepath.Join(GetImageUploadPath(), filename)

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
