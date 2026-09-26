package config

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Version holds the current release version string
var Version = "v4.0.0-PRO"

type Config struct {
	Port            string
	DatabaseURL     string
	JWTSecret       string
	ChromePath      string
	Environment     string
	BackupDir       string
	FrontendDist    string
	SupabaseURL     string
	SupabaseAnonKey string
	EnableCloudSync bool
}

func LoadConfig() *Config {
	envPaths := []string{
		".env",
		"../.env",
		"../../.env",
		filepath.Join("..", "backend", ".env"),
	}

	for _, p := range envPaths {
		if _, err := os.Stat(p); err == nil {
			_ = godotenv.Load(p)
			break
		}
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://postgres:postgres@localhost:5432/smartpower_db?sslmode=disable"
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	if jwtSecret == "" {
		jwtSecret = getOrCreateStationSecret()
	}

	backupDir := os.Getenv("BACKUP_DIR")
	if backupDir == "" {
		backupDir = filepath.Join(".", "backups")
	}

	frontendDist := os.Getenv("FRONTEND_DIST")
	if frontendDist == "" {
		frontendDist = filepath.Join("..", "frontend", "dist")
	}

	supaURL := os.Getenv("SUPABASE_URL")
	if supaURL == "" {
		supaURL = "https://pkuoytiickgbtfeffmxq.supabase.co"
	}

	supaAnonKey := os.Getenv("SUPABASE_ANON_KEY")
	if supaAnonKey == "" {
		supaAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
	}

	return &Config{
		Port:            port,
		DatabaseURL:     dbURL,
		JWTSecret:       jwtSecret,
		ChromePath:      os.Getenv("CHROME_PATH"),
		Environment:     os.Getenv("NODE_ENV"),
		BackupDir:       backupDir,
		FrontendDist:    frontendDist,
		SupabaseURL:     supaURL,
		SupabaseAnonKey: supaAnonKey,
		EnableCloudSync: os.Getenv("ENABLE_CLOUD_SYNC") == "true",
	}
}

func getOrCreateStationSecret() string {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	var secretFile string
	if localAppData != "" {
		dir := filepath.Join(localAppData, "SmartPowerERP")
		_ = os.MkdirAll(dir, 0700)
		secretFile = filepath.Join(dir, ".jwt_secret")
	} else {
		secretFile = ".jwt_secret"
	}

	if data, err := os.ReadFile(secretFile); err == nil {
		secret := strings.TrimSpace(string(data))
		if len(secret) >= 32 {
			return secret
		}
	}

	// توليد مفتاح عشوائي مشفر فائق القوة 256-bit
	b := make([]byte, 32)
	if _, err := rand.Read(b); err == nil {
		generated := hex.EncodeToString(b)
		_ = os.WriteFile(secretFile, []byte(generated), 0600)
		return generated
	}

	// بديل آمن مشتق من الوقت والتسلسل في حال تعذر crypto/rand
	h := sha256.Sum256([]byte(fmt.Sprintf("smartpower-%d-%d", time.Now().UnixNano(), os.Getpid())))
	generated := hex.EncodeToString(h[:])
	_ = os.WriteFile(secretFile, []byte(generated), 0600)
	return generated
}