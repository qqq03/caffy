package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
)

// LLMRecognitionResult : LLM 음료 인식 결과
type LLMRecognitionResult struct {
	DrinkName      string  `json:"drink_name"`
	CaffeineAmount int     `json:"caffeine_amount"`
	Confidence     float64 `json:"confidence"`
	Description    string  `json:"description"`
	Brand          string  `json:"brand"`
	Category       string  `json:"category"`
}

// RecognizeDrinkWithLLM : Gemini Vision API로 음료 인식
func RecognizeDrinkWithLLM(imageBase64 string) (*LLMRecognitionResult, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY not set")
	}

	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=%s", apiKey)

	prompt := `이 이미지에서 음료를 분석해주세요.
다음 JSON 형식으로만 응답하세요 (다른 텍스트 없이):
{
  "drink_name": "음료 이름 (한글)",
  "caffeine_amount": 카페인량(mg, 숫자만),
  "confidence": 확신도(0.0~1.0),
  "description": "간단한 설명",
  "brand": "브랜드명 (있으면)",
  "category": "커피/에너지드링크/차/탄산음료/기타"
}

카페인량 참고:
- 에스프레소 1샷: 75mg
- 아메리카노 (톨): 150mg
- 아메리카노 (그란데): 225mg
- 라떼/카푸치노: 75-100mg
- 콜드브루 (톨): 200mg
- 콜드브루 (벤티): 310mg
- 스타벅스 벤티 사이즈: +50% 카페인
- 레드불 250ml: 80mg
- 몬스터 355ml: 160mg
- 핫식스: 60mg
- 녹차: 30-50mg
- 콜라 355ml: 35mg

음료가 아니거나 인식 불가능하면 caffeine_amount를 0으로 설정하세요.`

	requestBody := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"parts": []map[string]interface{}{
					{"text": prompt},
					{
						"inline_data": map[string]string{
							"mime_type": "image/jpeg",
							"data":      imageBase64,
						},
					},
				},
			},
		},
		"generationConfig": map[string]interface{}{
			"temperature":     0.1,
			"maxOutputTokens": 500,
		},
	}

	jsonBody, _ := json.Marshal(requestBody)
	resp, err := http.Post(url, "application/json", bytes.NewBuffer(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("Gemini API 호출 실패: %v", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	// 응답 파싱
	var geminiResp struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error"`
	}

	if err := json.Unmarshal(body, &geminiResp); err != nil {
		return nil, fmt.Errorf("응답 파싱 실패: %v", err)
	}

	if geminiResp.Error != nil {
		return nil, fmt.Errorf("Gemini API 에러: %s", geminiResp.Error.Message)
	}

	if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("Gemini 응답 없음")
	}

	responseText := geminiResp.Candidates[0].Content.Parts[0].Text

	// JSON 추출 (```json ... ``` 제거)
	responseText = strings.TrimPrefix(responseText, "```json")
	responseText = strings.TrimPrefix(responseText, "```")
	responseText = strings.TrimSuffix(responseText, "```")
	responseText = strings.TrimSpace(responseText)

	// JSON 블록만 추출
	responseText = extractJSON(responseText)

	var result LLMRecognitionResult
	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		// JSON 파싱 실패 시 기본값
		return &LLMRecognitionResult{
			DrinkName:      "알 수 없는 음료",
			CaffeineAmount: 0,
			Confidence:     0,
			Description:    responseText,
			Category:       "기타",
		}, nil
	}

	return &result, nil
}

// extractJSON : 텍스트에서 JSON 블록만 추출
func extractJSON(text string) string {
	re := regexp.MustCompile(`\{[\s\S]*\}`)
	match := re.FindString(text)
	if match != "" {
		return match
	}
	return text
}

// RecognizeDrinkWithOpenAI : OpenAI GPT-4o Vision (대안)
func RecognizeDrinkWithOpenAI(imageBase64 string) (*LLMRecognitionResult, error) {
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY not set")
	}

	url := "https://api.openai.com/v1/chat/completions"

	prompt := `이 이미지에서 음료를 분석해주세요. JSON 형식으로만 응답:
{"drink_name": "음료명", "caffeine_amount": mg숫자, "confidence": 0.0-1.0, "description": "설명", "brand": "브랜드", "category": "카테고리"}`

	requestBody := map[string]interface{}{
		"model": "gpt-4o",
		"messages": []map[string]interface{}{
			{
				"role": "user",
				"content": []map[string]interface{}{
					{"type": "text", "text": prompt},
					{
						"type": "image_url",
						"image_url": map[string]string{
							"url": fmt.Sprintf("data:image/jpeg;base64,%s", imageBase64),
						},
					},
				},
			},
		},
		"max_tokens": 500,
	}

	jsonBody, _ := json.Marshal(requestBody)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	var openaiResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.Unmarshal(body, &openaiResp); err != nil {
		return nil, err
	}

	if len(openaiResp.Choices) == 0 {
		return nil, fmt.Errorf("OpenAI 응답 없음")
	}

	responseText := openaiResp.Choices[0].Message.Content
	responseText = extractJSON(responseText)

	var result LLMRecognitionResult
	if err := json.Unmarshal([]byte(responseText), &result); err != nil {
		return &LLMRecognitionResult{
			DrinkName:      "알 수 없는 음료",
			CaffeineAmount: 0,
			Confidence:     0,
			Description:    responseText,
			Category:       "기타",
		}, nil
	}

	return &result, nil
}
