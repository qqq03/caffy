"""
Caffy AI Server
- 음료 이미지 인식 (Gemini API)
- 학습 데이터셋 관리
- 향후 자체 모델 학습/추론
"""

import os
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from dotenv import load_dotenv
import uvicorn

from services.gemini_service import GeminiService
from services.dataset_service import DatasetService

load_dotenv()

app = FastAPI(
    title="Caffy AI Server",
    description="카페인 음료 인식 AI 서버",
    version="1.0.0"
)

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 서비스 초기화
gemini_service = GeminiService()
dataset_service = DatasetService()


# ============ 모델 정의 ============

class RecognitionResult(BaseModel):
    found: bool
    drink_name: str | None = None
    brand: str | None = None
    caffeine_amount: int | None = None
    confidence: float = 0.0
    source: str = "gemini"


class DatasetItem(BaseModel):
    image_path: str
    drink_name: str
    brand: str | None = None
    caffeine_amount: int
    verified: bool = False


class LabelRequest(BaseModel):
    image_id: str
    drink_name: str
    brand: str | None = None
    caffeine_amount: int


# ============ API 엔드포인트 ============

@app.get("/")
async def root():
    return {"message": "Caffy AI Server Running 🤖☕"}


@app.get("/health")
async def health_check():
    return {"status": "healthy"}


# 이미지 인식 (Gemini API)
@app.post("/recognize", response_model=RecognitionResult)
async def recognize_image(file: UploadFile = File(...)):
    """
    이미지에서 음료를 인식하고 카페인 함량을 추정합니다.
    """
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="이미지 파일만 업로드 가능합니다")
    
    try:
        image_bytes = await file.read()
        result = await gemini_service.analyze_image(image_bytes)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"인식 실패: {str(e)}")


# Base64 이미지 인식 (Go 서버 연동용)
class Base64ImageRequest(BaseModel):
    image_base64: str


@app.post("/recognize/base64", response_model=RecognitionResult)
async def recognize_base64_image(request: Base64ImageRequest):
    """
    Base64 인코딩된 이미지에서 음료를 인식합니다.
    Go 서버에서 호출할 때 사용.
    """
    try:
        result = await gemini_service.analyze_base64_image(request.image_base64)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"인식 실패: {str(e)}")


# 학습 데이터 저장
@app.post("/dataset/save")
async def save_to_dataset(
    file: UploadFile = File(...),
    drink_name: str = None,
    brand: str = None,
    caffeine_amount: int = None
):
    """
    인식된 이미지를 학습 데이터셋에 저장합니다.
    """
    try:
        image_bytes = await file.read()
        item = await dataset_service.save_image(
            image_bytes=image_bytes,
            drink_name=drink_name,
            brand=brand,
            caffeine_amount=caffeine_amount,
            filename=file.filename
        )
        return {"message": "저장 완료", "item": item}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"저장 실패: {str(e)}")


# 학습 데이터셋 조회
@app.get("/dataset")
async def get_dataset(skip: int = 0, limit: int = 100, verified_only: bool = False):
    """
    저장된 학습 데이터셋을 조회합니다.
    """
    items = await dataset_service.get_all(skip=skip, limit=limit, verified_only=verified_only)
    return {"items": items, "total": len(items)}


# 라벨링 (데이터 검증)
@app.post("/dataset/label")
async def label_dataset_item(request: LabelRequest):
    """
    데이터셋 항목에 라벨을 추가/수정합니다.
    """
    try:
        item = await dataset_service.update_label(
            image_id=request.image_id,
            drink_name=request.drink_name,
            brand=request.brand,
            caffeine_amount=request.caffeine_amount
        )
        return {"message": "라벨링 완료", "item": item}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"라벨링 실패: {str(e)}")


# 데이터셋 통계
@app.get("/dataset/stats")
async def get_dataset_stats():
    """
    데이터셋 통계를 조회합니다.
    """
    stats = await dataset_service.get_stats()
    return stats


# 모델 학습 트리거 (향후 구현)
@app.post("/train")
async def trigger_training():
    """
    자체 모델 학습을 시작합니다. (향후 구현 예정)
    """
    return {
        "message": "학습 기능은 아직 준비 중입니다",
        "status": "not_implemented"
    }


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8081))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
