package config

import (
	"os"
	"path/filepath"

	"github.com/joho/godotenv"
)

type Config struct {
	Port         string
	DatabaseURL  string
	JWTSecret    string
	ChromePath   string
	Environment  string
	BackupDir    string
	FrontendDist string
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
		jwtSecret = "smartpower-super-secret-jwt-key-2026-production"
	}

	backupDir := os.Getenv("BACKUP_DIR")
	if backupDir == "" {
		backupDir = filepath.Join(".", "backups")
	}

	frontendDist := os.Getenv("FRONTEND_DIST")
	if frontendDist == "" {
		frontendDist = filepath.Join("..", "frontend", "dist")
	}

	return &Config{
		Port:         port,
		DatabaseURL:  dbURL,
		JWTSecret:    jwtSecret,
		ChromePath:   os.Getenv("CHROME_PATH"),
		Environment:  os.Getenv("NODE_ENV"),
		BackupDir:    backupDir,
		FrontendDist: frontendDist,
	}
}