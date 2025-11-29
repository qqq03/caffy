package middleware

import (
	"caffy-backend/config"
	"net/http"

	"github.com/gin-gonic/gin"
)

// CORSMiddleware - CORS 처리 (Credentials 지원)
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		// Origin이 허용 목록에 있는지 확인
		allowed := false
		for _, o := range config.AllowedOrigins {
			if o == origin || o == "*" {
				allowed = true
				break
			}
		}

		// 허용된 Origin이면 헤더 설정
		if allowed && origin != "" {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Credentials", "true")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization")
			c.Header("Access-Control-Max-Age", "86400") // 24시간 캐시
		}

		// Preflight 요청 (OPTIONS) 처리
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent) // 204
			return
		}

		c.Next()
	}
}
