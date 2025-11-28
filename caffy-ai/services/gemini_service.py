"""
Gemini Vision API 서비스
"""

import os
import base64
import json
import httpx
from typing import Optional


class GeminiService:
    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY")
        if not self.api_key:
            raise ValueError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다")
        
        self.model = "gemini-2.0-flash"
        self.base_url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
    
    async def analyze_image(self, image_bytes: bytes) -> dict:
        """
        이미지 바이트에서 음료를 인식합니다.
        """
        base64_image = base64.b64encode(image_bytes).decode("utf-8")
        return await self._call_gemini(base64_image)
    
    async def analyze_base64_image(self, base64_image: str) -> dict:
        """
        Base64 인코딩된 이미지에서 음료를 인식합니다.
        """
        # data:image/jpeg;base64, 접두사 제거
        if "," in base64_image:
            base64_image = base64_image.split(",")[1]
        
        return await self._call_gemini(base64_image)
    
    async def _call_gemini(self, base64_image: str) -> dict:
        """
        Gemini API를 호출하여 이미지를 분석합니다.
        """
        prompt = """이 이미지에서 카페인 음료를 분석해주세요.

다음 JSON 형식으로 응답해주세요:
{
  "found": true/false,
  "drink_name": "음료 이름 (한글)",
  "brand": "브랜드명",
  "caffeine_amount": 카페인 함량(mg, 정수),
  "confidence": 확신도 (0.0~1.0)
}

규칙:
1. 음료가 보이지 않으면 found: false
2. 카페인 함량을 모르면 일반적인 수치로 추정
3. 에스프레소 1샷 = 약 75mg
4. 아메리카노 = 약 150mg
5. 에너지드링크는 제품별로 다름

JSON만 반환하세요."""

        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {
                        "inline_data": {
                            "mime_type": "image/jpeg",
                            "data": base64_image
                        }
                    }
                ]
            }]
        }
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{self.base_url}?key={self.api_key}",
                json=payload
            )
            
            if response.status_code != 200:
                raise Exception(f"Gemini API 오류: {response.status_code} - {response.text}")
            
            result = response.json()
            
            # 응답 파싱
            try:
                text = result["candidates"][0]["content"]["parts"][0]["text"]
                
                # JSON 추출
                text = text.strip()
                if text.startswith("```json"):
                    text = text[7:]
                if text.startswith("```"):
                    text = text[3:]
                if text.endswith("```"):
                    text = text[:-3]
                
                parsed = json.loads(text.strip())
                
                return {
                    "found": parsed.get("found", False),
                    "drink_name": parsed.get("drink_name"),
                    "brand": parsed.get("brand"),
                    "caffeine_amount": parsed.get("caffeine_amount"),
                    "confidence": parsed.get("confidence", 0.0),
                    "source": "gemini"
                }
            except (KeyError, json.JSONDecodeError) as e:
                return {
                    "found": False,
                    "drink_name": None,
                    "brand": None,
                    "caffeine_amount": None,
                    "confidence": 0.0,
                    "source": "gemini",
                    "error": str(e)
                }
