package services

import (
	"errors"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type AuthService struct {
	cfg *config.Config
	db  *gorm.DB
}

func NewAuthService(cfg *config.Config) *AuthService {
	return &AuthService{
		cfg: cfg,
		db:  database.DB,
	}
}

type JWTClaims struct {
	UserID   int64  `json:"user_id"`
	Username string `json:"username"`
	FullName string `json:"full_name"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

func (s *AuthService) Login(username, password string) (*models.User, string, error) {
	var user models.User
	if err := s.db.Where("username = ?", username).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, "", errors.New("invalid credentials")
		}
		return nil, "", err
	}

	if !user.IsActive {
		return nil, "", errors.New("user account is inactive")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		return nil, "", errors.New("invalid credentials")
	}

	token, err := s.GenerateToken(&user)
	if err != nil {
		return nil, "", err
	}

	// Log audit
	s.db.Create(&models.AuditLog{
		UserID:  &user.ID,
		Action:  "LOGIN",
		Entity:  "USER",
		Details: strPtr("تسجيل دخول ناجح لمستخدم النظام"),
	})

	return &user, token, nil
}

func (s *AuthService) GenerateToken(user *models.User) (string, error) {
	claims := JWTClaims{
		UserID:   user.ID,
		Username: user.Username,
		FullName: user.FullName,
		Role:     user.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(7 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "smartpower-erp",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(s.cfg.JWTSecret))
}

func (s *AuthService) ValidateToken(tokenString string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(s.cfg.JWTSecret), nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*JWTClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

func (s *AuthService) HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

func strPtr(s string) *string {
	return &s
}