package services

import (
	"fmt"
	"testing"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

func TestHash(t *testing.T) {
	h, err := bcrypt.GenerateFromPassword([]byte("admin123"), bcrypt.DefaultCost)
	if err != nil {
		t.Fatal(err)
	}

	err = bcrypt.CompareHashAndPassword(h, []byte("admin123"))
	if err != nil {
		t.Fatalf("Compare failed: %v", err)
	}
}

// 1. اختبارات وحدة نقية لـ JWT (Pure Unit Tests - No DB required)

func TestAuthService_GenerateAndValidateToken_Success(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret-super-secure-key-12345"}
	authSvc := &AuthService{cfg: cfg}

	user := &models.User{
		ID:       999,
		Username: "accountant_ali",
		FullName: "علي المحاسب",
		Role:     "ACCOUNTANT",
		IsActive: true,
	}

	token, err := authSvc.GenerateToken(user)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}
	if token == "" {
		t.Fatalf("expected non-empty token")
	}

	claims, err := authSvc.ValidateToken(token)
	if err != nil {
		t.Fatalf("ValidateToken failed: %v", err)
	}

	if claims.UserID != 999 {
		t.Errorf("expected UserID 999, got %d", claims.UserID)
	}
	if claims.Username != "accountant_ali" {
		t.Errorf("expected Username accountant_ali, got %s", claims.Username)
	}
	if claims.Role != "ACCOUNTANT" {
		t.Errorf("expected Role ACCOUNTANT, got %s", claims.Role)
	}
}

func TestAuthService_ValidateToken_Expired(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret-super-secure-key-12345"}
	authSvc := &AuthService{cfg: cfg}

	// إنشاء توكن منتهي الصلاحية يدوياً
	claims := JWTClaims{
		UserID:   101,
		Username: "expired_user",
		FullName: "مستخدم منتهي",
		Role:     "CASHIER",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)), // منتهي قبل ساعة
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
			Issuer:    "smartpower-erp",
		},
	}
	tokenObj := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := tokenObj.SignedString([]byte(cfg.JWTSecret))
	if err != nil {
		t.Fatalf("failed to sign expired token: %v", err)
	}

	_, err = authSvc.ValidateToken(tokenString)
	if err == nil {
		t.Fatalf("expected error for expired token, but got nil")
	}
}

func TestAuthService_ValidateToken_TamperedSignature(t *testing.T) {
	cfgValid := &config.Config{JWTSecret: "correct-secret-key-12345"}
	cfgAttacker := &config.Config{JWTSecret: "fake-attacker-secret-99999"}

	authSvcValid := &AuthService{cfg: cfgValid}
	authSvcAttacker := &AuthService{cfg: cfgAttacker}

	user := &models.User{
		ID:       55,
		Username: "admin_clone",
		FullName: "هاكر",
		Role:     "ADMIN",
	}

	// التوكن موقّع بمفتاح مختلف
	tamperedToken, err := authSvcAttacker.GenerateToken(user)
	if err != nil {
		t.Fatalf("failed to generate attacker token: %v", err)
	}

	// محاولة المصادقة بالمفتاح الحقيقي
	_, err = authSvcValid.ValidateToken(tamperedToken)
	if err == nil {
		t.Fatalf("expected error for tampered signature, but got nil")
	}
}

func TestAuthService_ValidateToken_Malformed(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret-key"}
	authSvc := &AuthService{cfg: cfg}

	malformedTokens := []string{
		"",
		"not-a-token",
		"header.payload",
		"Bearer abc.123",
	}

	for _, mt := range malformedTokens {
		_, err := authSvc.ValidateToken(mt)
		if err == nil {
			t.Errorf("expected error for malformed token %q, got nil", mt)
		}
	}
}

// 2. اختبارات خدمة تسجيل الدخول Login (Isolation with Transaction Rollback)

func TestAuthService_Login_Scenarios(t *testing.T) {
	cfg := config.LoadConfig()
	db, err := database.InitDB(cfg)
	if err != nil {
		t.Fatalf("failed to connect to db: %v", err)
	}

	tx := db.Begin()
	defer tx.Rollback()

	authSvc := &AuthService{cfg: cfg, db: tx}

	// تشفير كلمة المرور التجريبية
	hash, err := authSvc.HashPassword("CorrectPassword123")
	if err != nil {
		t.Fatalf("HashPassword failed: %v", err)
	}

	uniqueSuffix := time.Now().UnixNano()

	// مستخدم نشط
	activeUser := models.User{
		Username:     fmt.Sprintf("active_usr_%d", uniqueSuffix),
		PasswordHash: hash,
		FullName:     "مستخدم نشط للتجارب",
		Role:         "CASHIER",
		IsActive:     true,
	}
	if err := tx.Create(&activeUser).Error; err != nil {
		t.Fatalf("failed to create active user: %v", err)
	}

	// مستخدم معطل
	inactiveUser := models.User{
		Username:     fmt.Sprintf("inactive_usr_%d", uniqueSuffix),
		PasswordHash: hash,
		FullName:     "مستخدم معطل للتجارب",
		Role:         "CASHIER",
		IsActive:     false,
	}
	if err := tx.Create(&inactiveUser).Error; err != nil {
		t.Fatalf("failed to create inactive user: %v", err)
	}
	if err := tx.Model(&inactiveUser).Update("is_active", false).Error; err != nil {
		t.Fatalf("failed to set is_active false: %v", err)
	}

	// الحالة 1: تسجيل دخول ناجح
	t.Run("Success Login", func(t *testing.T) {
		u, token, err := authSvc.Login(activeUser.Username, "CorrectPassword123")
		if err != nil {
			t.Fatalf("expected successful login, got err: %v", err)
		}
		if u == nil || u.ID != activeUser.ID {
			t.Fatalf("unexpected user returned: %+v", u)
		}
		if token == "" {
			t.Fatalf("expected valid JWT token, got empty")
		}

		claims, err := authSvc.ValidateToken(token)
		if err != nil {
			t.Fatalf("ValidateToken on returned token failed: %v", err)
		}
		if claims.Username != activeUser.Username {
			t.Fatalf("claims username mismatch: %s vs %s", claims.Username, activeUser.Username)
		}
	})

	// الحالة 2: مستخدم معطل IsActive = false
	t.Run("Inactive User Rejected", func(t *testing.T) {
		_, _, err := authSvc.Login(inactiveUser.Username, "CorrectPassword123")
		if err == nil {
			t.Fatalf("expected inactive user to be rejected, got nil error")
		}
		if err.Error() != "user account is inactive" {
			t.Fatalf("expected 'user account is inactive', got: %v", err)
		}
	})

	// الحالة 3: كلمة مرور خاطئة
	t.Run("Wrong Password", func(t *testing.T) {
		_, _, err := authSvc.Login(activeUser.Username, "WrongPassword999")
		if err == nil {
			t.Fatalf("expected wrong password to fail, got nil error")
		}
		if err.Error() != "invalid credentials" {
			t.Fatalf("expected 'invalid credentials', got: %v", err)
		}
	})

	// الحالة 4: مستخدم غير موجود
	t.Run("Non-existent User", func(t *testing.T) {
		_, _, err := authSvc.Login("completely_unknown_user_9999", "any_pass")
		if err == nil {
			t.Fatalf("expected non-existent user to fail, got nil error")
		}
		if err.Error() != "invalid credentials" {
			t.Fatalf("expected 'invalid credentials', got: %v", err)
		}
	})

	// الحالة 5: اسم مستخدم أو كلمة مرور فارغة
	t.Run("Empty Credentials", func(t *testing.T) {
		_, _, err := authSvc.Login("", "")
		if err == nil {
			t.Fatalf("expected empty credentials to fail, got nil error")
		}

		_, _, err = authSvc.Login(activeUser.Username, "")
		if err == nil {
			t.Fatalf("expected empty password to fail, got nil error")
		}
	})
}