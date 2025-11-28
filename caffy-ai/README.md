# 🤖 Caffy AI Server

> 카페인 음료 인식을 위한 Python AI 서버

## 🛠️ 기술 스택

- **Framework**: FastAPI
- **AI**: Google Gemini Vision API
- **HTTP Client**: httpx (async)

## 📁 구조

```
caffy-ai/
├── main.py                 # FastAPI 엔트리포인트
├── services/
│   ├── gemini_service.py   # Gemini API 연동
│   └── dataset_service.py  # 학습 데이터셋 관리
├── dataset/                # 학습 데이터 저장소
│   ├── images/             # 이미지 파일
│   └── labels.json         # 라벨 정보
├── requirements.txt
└── .env
```

## 🚀 실행 방법

```bash
# 가상환경 생성
python -m venv venv
venv\Scripts\activate  # Windows
# source venv/bin/activate  # Mac/Linux

# 의존성 설치
pip install -r requirements.txt

# 환경변수 설정
cp .env.example .env
# .env 파일에 GEMINI_API_KEY 입력

# 서버 실행
python main.py
# 또는
uvicorn main:app --reload --port 8081
```

## 📡 API 엔드포인트

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/` | 서버 상태 |
| GET | `/health` | 헬스체크 |
| POST | `/recognize` | 이미지 파일 인식 |
| POST | `/recognize/base64` | Base64 이미지 인식 |
| POST | `/dataset/save` | 학습 데이터 저장 |
| GET | `/dataset` | 데이터셋 조회 |
| POST | `/dataset/label` | 데이터 라벨링 |
| GET | `/dataset/stats` | 데이터셋 통계 |
| POST | `/train` | 모델 학습 (예정) |

## 🔗 Go 서버 연동

Go 서버에서 Python AI 서버 호출:

```go
// AI 서버 URL
aiServerURL := "http://localhost:8081"

// Base64 이미지 인식 요청
resp, err := http.Post(
    aiServerURL + "/recognize/base64",
    "application/json",
    bytes.NewBuffer(jsonBody),
)
```

## 📊 Swagger 문서

서버 실행 후 접속:
- http://localhost:8081/docs (Swagger UI)
- http://localhost:8081/redoc (ReDoc)
