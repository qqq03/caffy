package services

import (
	"bytes"
	"caffy-backend/config"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// GetVisionAPIKey : 환경변수에서 API 키 가져오기
func GetVisionAPIKey() string {
	return config.GoogleVisionAPIKey
}

// VisionResponse : Google Vision API 응답 구조체
type VisionResponse struct {
	Responses []struct {
		TextAnnotations []struct {
			Description string `json:"description"`
			Locale      string `json:"locale,omitempty"`
		} `json:"textAnnotations"`
		LabelAnnotations []struct {
			Description string  `json:"description"`
			Score       float64 `json:"score"`
		} `json:"labelAnnotations"`
		LogoAnnotations []struct {
			Description string  `json:"description"`
			Score       float64 `json:"score"`
		} `json:"logoAnnotations"`
		Error *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	} `json:"responses"`
}

// VisionResult : 정제된 Vision API 결과
type VisionResult struct {
	FullText string        `json:"full_text"` // OCR 전체 텍스트
	Labels   []LabelResult `json:"labels"`    // 라벨 (커피, 음료 등)
	Logos    []string      `json:"logos"`     // 인식된 로고 (스타벅스 등)
	Error    string        `json:"error,omitempty"`
}

type LabelResult struct {
	Description string  `json:"description"`
	Score       float64 `json:"score"`
}

// AnalyzeImage : Google Vision API로 이미지 분석
func AnalyzeImage(imageData []byte) (*VisionResult, error) {
	apiKey := GetVisionAPIKey()
	if apiKey == "" {
		return nil, fmt.Errorf("GOOGLE_VISION_API_KEY 환경변수가 설정되지 않았습니다. .env 파일을 확인하세요")
	}

	// Base64 인코딩
	base64Image := base64.StdEncoding.EncodeToString(imageData)

	// API 요청 본문 구성
	requestBody := map[string]interface{}{
		"requests": []map[string]interface{}{
			{
				"image": map[string]string{
					"content": base64Image,
				},
				"features": []map[string]interface{}{
					{"type": "TEXT_DETECTION", "maxResults": 50},
					{"type": "LABEL_DETECTION", "maxResults": 20},
					{"type": "LOGO_DETECTION", "maxResults": 10},
				},
			},
		},
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("JSON 생성 실패: %v", err)
	}

	// API 호출
	url := fmt.Sprintf("https://vision.googleapis.com/v1/images:annotate?key=%s", apiKey)
	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("Vision API 호출 실패: %v", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("응답 읽기 실패: %v", err)
	}

	// 응답 파싱
	var visionResp VisionResponse
	if err := json.Unmarshal(body, &visionResp); err != nil {
		return nil, fmt.Errorf("응답 파싱 실패: %v", err)
	}

	// 결과 정제
	result := &VisionResult{}

	if len(visionResp.Responses) > 0 {
		response := visionResp.Responses[0]

		// 에러 체크
		if response.Error != nil {
			result.Error = response.Error.Message
			return result, nil
		}

		// OCR 텍스트 추출 (첫 번째 항목이 전체 텍스트)
		if len(response.TextAnnotations) > 0 {
			result.FullText = response.TextAnnotations[0].Description
		}

		// 라벨 추출
		for _, label := range response.LabelAnnotations {
			result.Labels = append(result.Labels, LabelResult{
				Description: label.Description,
				Score:       label.Score,
			})
		}

		// 로고 추출
		for _, logo := range response.LogoAnnotations {
			result.Logos = append(result.Logos, logo.Description)
		}
	}

	return result, nil
}

// ExtractCaffeineInfo : OCR 텍스트에서 카페인 정보 추출
func ExtractCaffeineInfo(ocrText string) (caffeineAmount float64, productName string) {
	lines := strings.Split(ocrText, "\n")

	// 카페인 함량 패턴 찾기 (예: "카페인 150mg", "caffeine 150mg")
	for _, line := range lines {
		lower := strings.ToLower(line)

		// 카페인/caffeine 키워드 찾기
		if strings.Contains(lower, "카페인") || strings.Contains(lower, "caffeine") {
			// 숫자 추출 시도
			var mg float64
			if _, err := fmt.Sscanf(lower, "%*s %f", &mg); err == nil && mg > 0 {
				caffeineAmount = mg
			}
			// mg 앞의 숫자 찾기
			for i, c := range lower {
				if c >= '0' && c <= '9' {
					var num float64
					fmt.Sscanf(lower[i:], "%f", &num)
					if num > 0 && num < 1000 { // 합리적인 범위
						caffeineAmount = num
						break
					}
				}
			}
		}
	}

	// 제품명은 첫 몇 줄에서 추출 (보통 상단에 있음)
	if len(lines) > 0 {
		productName = strings.TrimSpace(lines[0])
		if len(productName) > 100 {
			productName = productName[:100]
		}
	}

	return caffeineAmount, productName
}

// SetVisionAPIKey : API 키 설정 (테스트용)
func SetVisionAPIKey(key string) {
	config.GoogleVisionAPIKey = key
}
