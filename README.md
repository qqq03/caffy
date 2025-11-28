# ☕ Caffy - 스마트 카페인 트래커

> 당신의 카페인 섭취를 과학적으로 관리하세요!

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Go](https://img.shields.io/badge/Go-00ADD8?style=for-the-badge&logo=go&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)

## 📖 소개

Caffy는 카페인 섭취량을 실시간으로 추적하고, 개인화된 대사율을 학습하여 최적의 수면 시간을 예측하는 카페인 트래킹 모바일 앱

### ✨ 주요 기능

- **📸 AI 음료 인식**: 사진만 찍으면 음료와 카페인 함량을 자동 인식 (Google Gemini Vision)
- **📊 실시간 체내 카페인 그래프**: 흡수/대사 곡선을 반영한 정확한 시각화
- **🌙 수면 예측 대시보드**: 목표 수면 시간에 맞춘 추가 섭취 가능량 계산
- **🧠 개인화 학습**: 피드백 기반으로 개인 반감기 자동 조정
- **💾 스마트 DB 매칭**: 동일 음료 재촬영 시 즉시 인식 (이미지 해시)

## 🏗️ 프로젝트 구조

```
caffy/
├── caffy_app/          # Flutter 프론트엔드
│   ├── lib/
│   │   ├── screens/    # 화면 (홈, 로그인)
│   │   ├── services/   # API, 인증 서비스
│   │   └── widgets/    # 재사용 위젯
│   └── ...
│
├── caffy-backend/      # Go 백엔드
│   ├── controllers/    # API 핸들러
│   ├── models/         # DB 스키마
│   ├── services/       # 비즈니스 로직
│   ├── middleware/     # JWT 인증
│   └── config/         # DB, 환경설정
│
└── README.md           # 이 파일
```

## 🚀 시작하기

### 요구사항

- **Flutter**: 3.10.1+
- **Go**: 1.25+
- **MySQL**: 8.0+
- **Google Gemini API Key**

### 백엔드 설정

```bash
cd caffy-backend

# 환경변수 설정
cp .env.example .env
# .env 파일에 DB 정보, JWT_SECRET, GEMINI_API_KEY 입력

# 의존성 설치 & 실행
go mod tidy
go run main.go
```

### 프론트엔드 설정

```bash
cd caffy_app

# 환경변수 설정
cp .env.example .env
# .env 파일에 API_URL 입력

# 의존성 설치 & 실행
flutter pub get
flutter run
```

## 📱 스크린샷

| 홈 화면 | 수면 대시보드 | 음료 인식 |
|--------|-------------|----------|
| 실시간 카페인량 | 수면 목표 시간 설정 | AI 자동 인식 |

## 🧪 카페인 계산 모델

### 흡수 단계 (0~45분)
```
농도 = 섭취량 × sin(경과시간/45분 × π/2)
```

### 대사 단계 (45분~)
```
잔류량 = 섭취량 × (0.5)^((경과시간-0.75)/반감기)
```

### 대사 타입별 반감기
| 타입 | 반감기 | 해당 조건 |
|-----|-------|----------|
| 빠름 | 3시간 | 흡연자 |
| 보통 | 5시간 | 일반 성인 |
| 느림 | 8시간 | 임산부, 피임약 복용 등 |

## 👨‍💻 개발자

- **qqq03** - [GitHub](https://github.com/qqq03)
