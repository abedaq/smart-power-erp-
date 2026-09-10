package services

import (
	"fmt"
	"io"
	"log"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"smartpower/internal/config"
)

type BackupService struct {
	cfg *config.Config
}

func NewBackupService(cfg *config.Config) *BackupService {
	return &BackupService{
		cfg: cfg,
	}
}

// RunDailyBackup is kept for backward compatibility and delegates to RunBackup
func (s *BackupService) RunDailyBackup() (string, error) {
	return s.RunBackup()
}

func (s *BackupService) RunBackup() (string, error) {
	backupDir := s.cfg.BackupDir
	if err := os.MkdirAll(backupDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create backup dir: %w", err)
	}

	timestamp := time.Now().Format("2006-01-02_15-04-05")
	backupFileName := fmt.Sprintf("smartpower_db_%s.sql", timestamp)
	targetFilePath := filepath.Join(backupDir, backupFileName)

	pgDumpPath := s.findPgDumpPath()

	// Parse database connection parameters dynamically
	host := "127.0.0.1"
	port := "15432"
	user := "postgres"
	password := "postgres"
	dbName := "smartpower_db"

	if parsedURL, err := url.Parse(s.cfg.DatabaseURL); err == nil {
		if h := parsedURL.Hostname(); h != "" {
			host = h
		}
		if p := parsedURL.Port(); p != "" {
			port = p
		}
		if u := parsedURL.User; u != nil {
			if username := u.Username(); username != "" {
				user = username
			}
			if pass, hasPass := u.Password(); hasPass {
				password = pass
			}
		}
		if path := strings.TrimPrefix(parsedURL.Path, "/"); path != "" {
			dbName = path
		}
	}

	cmd := exec.Command(pgDumpPath,
		"-h", host,
		"-p", port,
		"-U", user,
		"-d", dbName,
		"-f", targetFilePath,
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	cmd.Env = append(os.Environ(), fmt.Sprintf("PGPASSWORD=%s", password))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("pg_dump failed with path '%s': %s (%w)", pgDumpPath, string(output), err)
	}

	log.Printf("[Backup] Successfully created database backup: %s", targetFilePath)

	// Clean older local backups to prevent disk bloat (Keep last 100 copies)
	s.cleanOldBackups(backupDir, 100)

	// Mirror backup to external USB drives and clean old backups on USB
	s.mirrorToUSBDrive(targetFilePath, backupFileName)

	return targetFilePath, nil
}

func (s *BackupService) findPgDumpPath() string {
	execPath, err := os.Executable()
	if err != nil {
		execPath, _ = os.Getwd()
	}
	appDir := filepath.Dir(execPath)
	cwd, _ := os.Getwd()

	candidates := []string{
		filepath.Join(appDir, "pgsql", "bin", "pg_dump.exe"),
		filepath.Join(cwd, "pgsql", "bin", "pg_dump.exe"),
		filepath.Join(appDir, "..", "pgsql", "bin", "pg_dump.exe"),
		filepath.Join("pgsql", "bin", "pg_dump.exe"),
		`C:\Program Files\PostgreSQL\18\bin\pg_dump.exe`,
		`C:\Program Files\PostgreSQL\17\bin\pg_dump.exe`,
		`C:\Program Files\PostgreSQL\16\bin\pg_dump.exe`,
		`C:\Program Files\PostgreSQL\15\bin\pg_dump.exe`,
	}

	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}

	return "pg_dump"
}

func (s *BackupService) mirrorToUSBDrive(srcPath, fileName string) {
	drives := []string{"D:\\", "E:\\", "F:\\", "G:\\", "H:\\"}
	for _, d := range drives {
		if _, err := os.Stat(d); err == nil {
			usbBackupDir := filepath.Join(d, "SmartPower_Backups")
			_ = os.MkdirAll(usbBackupDir, 0755)
			dstPath := filepath.Join(usbBackupDir, fileName)

			srcFile, err := os.Open(srcPath)
			if err != nil {
				continue
			}
			dstFile, err := os.Create(dstPath)
			if err != nil {
				srcFile.Close()
				continue
			}
			_, _ = io.Copy(dstFile, srcFile)
			srcFile.Close()
			dstFile.Close()
			log.Printf("[Backup] Mirrored backup to USB drive: %s", dstPath)

			// Clean older USB backups (Keep last 100 copies)
			s.cleanOldBackups(usbBackupDir, 100)
			break
		}
	}
}

func (s *BackupService) cleanOldBackups(dir string, maxKeep int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}

	type fileInfo struct {
		path    string
		modTime time.Time
	}
	var backups []fileInfo
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasPrefix(entry.Name(), "smartpower_db_") && strings.HasSuffix(entry.Name(), ".sql") {
			info, err := entry.Info()
			if err == nil {
				backups = append(backups, fileInfo{
					path:    filepath.Join(dir, entry.Name()),
					modTime: info.ModTime(),
				})
			}
		}
	}

	if len(backups) <= maxKeep {
		return
	}

	sort.Slice(backups, func(i, j int) bool {
		return backups[i].modTime.Before(backups[j].modTime)
	})

	deleteCount := len(backups) - maxKeep
	for i := 0; i < deleteCount; i++ {
		_ = os.Remove(backups[i].path)
		log.Printf("[Backup] Rotated out old backup: %s", backups[i].path)
	}
}