package controllers

import (
	"caffy-backend/config"
	"caffy-backend/middleware"
	"caffy-backend/models"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// Register : 회원가입
func Register(c *gin.Context) {
	var input models.RegisterRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 이메일 중복 체크
	var existingUser models.User
	if err := config.DB.Where("email = ?", input.Email).First(&existingUser).Error; err == nil {
		c.JSON(http.StatusConflict, gin.H{"error": "이미 사용 중인 이메일입니다"})
		return
	}

	// 비밀번호 해시화
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "비밀번호 처리 실패"})
		return
	}

	// 닉네임이 없으면 이메일 앞부분 사용
	nickname := input.Nickname
	if nickname == "" {
		nickname = strings.Split(input.Email, "@")[0]
	}

	// 기본값 설정
	weight := input.Weight
	if weight == 0 {
		weight = 70.0
	}
	height := input.Height
	if height == 0 {
		height = 170.0
	}

	// 사용자 생성
	user := models.User{
		Email:           input.Email,
		Password:        string(hashedPassword),
		Nickname:        nickname,
		Weight:          weight,
		Height:          height,
		Gender:          input.Gender,
		IsSmoker:        input.IsSmoker,
		IsPregnant:      input.IsPregnant,
		ExercisePerWeek: input.ExercisePerWeek,
		MetabolismType:  input.MetabolismType,
	}

	if err := config.DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "사용자 생성 실패"})
		return
	}

	// JWT 토큰 발급
	token, err := middleware.GenerateToken(user.ID, user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "토큰 생성 실패"})
		return
	}

	c.JSON(http.StatusCreated, models.AuthResponse{
		Token: token,
		User:  user,
	})
}

// Login : 로그인
func Login(c *gin.Context) {
	var input models.LoginRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 사용자 조회
	var user models.User
	if err := config.DB.Where("email = ?", input.Email).First(&user).Error; err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "이메일 또는 비밀번호가 틀립니다"})
		return
	}

	// 비밀번호 확인
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(input.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "이메일 또는 비밀번호가 틀립니다"})
		return
	}

	// JWT 토큰 발급
	token, err := middleware.GenerateToken(user.ID, user.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "토큰 생성 실패"})
		return
	}

	c.JSON(http.StatusOK, models.AuthResponse{
		Token: token,
		User:  user,
	})
}

// GetMe : 내 정보 조회
func GetMe(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "사용자를 찾을 수 없습니다"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// UpdateMe : 내 정보 수정
func UpdateMe(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "사용자를 찾을 수 없습니다"})
		return
	}

	var input map[string]interface{}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// 업데이트 (부분 수정 지원)
	if v, ok := input["nickname"].(string); ok {
		user.Nickname = v
	}
	if v, ok := input["weight"].(float64); ok {
		user.Weight = v
	}
	if v, ok := input["height"].(float64); ok {
		user.Height = v
	}
	if v, ok := input["gender"].(float64); ok { // JSON 숫자는 float64로 언마샬링됨
		user.Gender = int(v)
	}
	if v, ok := input["is_smoker"].(bool); ok {
		user.IsSmoker = v
	}
	if v, ok := input["is_pregnant"].(bool); ok {
		user.IsPregnant = v
	}
	if v, ok := input["exercise_per_week"].(float64); ok {
		user.ExercisePerWeek = int(v)
	}
	if v, ok := input["metabolism_type"].(float64); ok {
		user.MetabolismType = int(v)
	}

	config.DB.Save(&user)
	c.JSON(http.StatusOK, user)
}

// ChangePassword : 비밀번호 변경
func ChangePassword(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var input struct {
		CurrentPassword string `json:"current_password" binding:"required"`
		NewPassword     string `json:"new_password" binding:"required,min=6"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	if err := config.DB.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "사용자를 찾을 수 없습니다"})
		return
	}

	// 현재 비밀번호 확인
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(input.CurrentPassword)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "현재 비밀번호가 틀립니다"})
		return
	}

	// 새 비밀번호 해시화
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(input.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "비밀번호 처리 실패"})
		return
	}

	user.Password = string(hashedPassword)
	config.DB.Save(&user)

	c.JSON(http.StatusOK, gin.H{"message": "비밀번호가 변경되었습니다"})
}
