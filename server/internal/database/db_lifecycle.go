package database

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type DBLifecycleManager struct {
	AppDir       string
	DataDir      string
	PgBinDir     string
	Port         int
	IsPortable   bool
	DatabaseURL  string
	InitDataFile string
}

func NewDBLifecycleManager() (*DBLifecycleManager, error) {
	execPath, err := os.Executable()
	if err != nil {
		execPath, _ = os.Getwd()
	}
	appDir := filepath.Dir(execPath)

	// Check if portable pgsql/bin exists relative to appDir or current working dir
	pgBinDir := filepath.Join(appDir, "pgsql", "bin")
	isPortable := false
	if _, err := os.Stat(filepath.Join(pgBinDir, "postgres.exe")); err == nil {
		isPortable = true
	} else {
		// Also check in current working directory
		cwd, _ := os.Getwd()
		pgBinDirCwd := filepath.Join(cwd, "pgsql", "bin")
		if _, err := os.Stat(filepath.Join(pgBinDirCwd, "postgres.exe")); err == nil {
			pgBinDir = pgBinDirCwd
			appDir = cwd
			isPortable = true
		}
	}

	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	if localAppData == "" {
		localAppData = appDir
	}

	dataDir := filepath.Join(localAppData, "SmartPowerERP", "data")
	port := 15432

	return &DBLifecycleManager{
		AppDir:       appDir,
		DataDir:      dataDir,
		PgBinDir:     pgBinDir,
		Port:         port,
		IsPortable:   isPortable,
		DatabaseURL:  fmt.Sprintf("postgres://postgres:postgres@127.0.0.1:%d/smartpower_db?sslmode=disable", port),
		InitDataFile: filepath.Join(appDir, "schema", "init_schema.sql"),
	}, nil
}

func (m *DBLifecycleManager) EnsureDatabaseReady() (string, error) {
	if !m.IsPortable {
		log.Println("ℹ️ Standard / Development Database Mode active")
		return "", nil
	}

	log.Printf("🚀 Embedded Portable PostgreSQL Engine detected at: %s", m.PgBinDir)
	log.Printf("📂 Database Storage Directory: %s", m.DataDir)

	if err := os.MkdirAll(m.DataDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create database directory: %w", err)
	}

	pgVersionFile := filepath.Join(m.DataDir, "PG_VERSION")
	needsInitCluster := false
	if _, err := os.Stat(pgVersionFile); os.IsNotExist(err) {
		needsInitCluster = true
	}

	flagFile := filepath.Join(m.DataDir, ".db_initialized")
	needsSeed := false
	if _, err := os.Stat(flagFile); os.IsNotExist(err) {
		needsSeed = true
	}

	// 1. Initialize cluster if needed (only if PG_VERSION doesn't exist)
	if needsInitCluster {
		templateDir := filepath.Join(m.AppDir, "data_template")
		templatePgVersion := filepath.Join(templateDir, "PG_VERSION")
		if _, err := os.Stat(templatePgVersion); err == nil {
			log.Println("📦 Fast Initialization: Deploying pre-configured database cluster template...")
			if err := copyDirectory(templateDir, m.DataDir); err != nil {
				log.Printf("⚠️ Template deployment failed (%v), falling back to initdb...", err)
				if err := m.initDB(); err != nil {
					return "", fmt.Errorf("initdb failed: %w", err)
				}
			} else {
				log.Println("✅ Database cluster template deployed successfully in milliseconds!")
				_ = os.WriteFile(flagFile, []byte(time.Now().Format(time.RFC3339)), 0644)
				needsSeed = false
			}
		} else {
			log.Println("⚙️ Initializing new PostgreSQL database cluster (initdb)...")
			if err := m.initDB(); err != nil {
				return "", fmt.Errorf("initdb failed: %w", err)
			}
		}
	}

	// 2. Clean stale PID file if server crashed previously
	m.cleanStalePID()

	// 3. Start PostgreSQL
	log.Printf("🔌 Starting local PostgreSQL engine on 127.0.0.1:%d...", m.Port)
	if err := m.startPostgres(); err != nil {
		return "", fmt.Errorf("failed to start postgres: %w", err)
	}

	// 4. Create database and seed initial schema if first run (when not using template)
	if needsSeed {
		log.Println("📦 First-time run detected: Creating database and importing initial schema...")
		if err := m.createDatabaseAndSeed(); err != nil {
			log.Printf("⚠️ Schema seed warning: %v", err)
		} else {
			_ = os.WriteFile(flagFile, []byte(time.Now().Format(time.RFC3339)), 0644)
			log.Println("✅ Initial database schema and August 2 cycle data imported successfully!")
		}
	}

	return m.DatabaseURL, nil
}

func (m *DBLifecycleManager) initDB() error {
	initdbExe := filepath.Join(m.PgBinDir, "initdb.exe")
	cmd := exec.Command(initdbExe,
		"-D", m.DataDir,
		"-U", "postgres",
		"-E", "UTF8",
		"--locale=C",
		"-A", "trust",
		"--no-sync",
	)
	cmd.Dir = m.PgBinDir
	pathEnv := fmt.Sprintf("PATH=%s;%s", m.PgBinDir, os.Getenv("PATH"))
	cmd.Env = append(os.Environ(), pathEnv)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("initdb error (%v): %s", err, string(out))
	}
	return nil
}

func (m *DBLifecycleManager) cleanStalePID() {
	pidFile := filepath.Join(m.DataDir, "postmaster.pid")
	data, err := os.ReadFile(pidFile)
	if err != nil {
		return
	}

	lines := strings.Split(string(data), "\n")
	if len(lines) > 0 {
		pid, err := strconv.Atoi(strings.TrimSpace(lines[0]))
		if err == nil {
			chk := exec.Command("tasklist", "/FI", fmt.Sprintf("PID eq %d", pid))
			chk.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
			out, _ := chk.Output()
			if !strings.Contains(string(out), fmt.Sprintf("%d", pid)) {
				log.Printf("🧹 Removing stale postmaster.pid (PID %d is no longer active)", pid)
				_ = os.Remove(pidFile)
			}
		}
	}
}

func (m *DBLifecycleManager) startPostgres() error {
	dsn := fmt.Sprintf("postgres://postgres:postgres@127.0.0.1:%d/postgres?sslmode=disable", m.Port)
	if db, err := sql.Open("pgx", dsn); err == nil {
		ctxPre, cancelPre := context.WithTimeout(context.Background(), 1*time.Second)
		if err := db.PingContext(ctxPre); err == nil {
			db.Close()
			cancelPre()
			log.Println("🔌 Embedded PostgreSQL engine is already running and healthy.")
			return nil
		}
		cancelPre()
		db.Close()
	}

	pgCtl := filepath.Join(m.PgBinDir, "pg_ctl.exe")
	logFile := filepath.Join(m.DataDir, "server.log")

	cmd := exec.Command(pgCtl,
		"-D", m.DataDir,
		"-l", logFile,
		"-o", fmt.Sprintf("-p %d -h 127.0.0.1", m.Port),
		"-w",
		"-t", "20",
		"start",
	)
	cmd.Dir = m.PgBinDir
	pathEnv := fmt.Sprintf("PATH=%s;%s", m.PgBinDir, os.Getenv("PATH"))
	cmd.Env = append(os.Environ(), pathEnv)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	cmd.Stdout = nil
	cmd.Stderr = nil
	_ = cmd.Run()

	// Health check loop waiting for database readiness (allows up to 60s for crash recovery / WAL replay)
	dsn = fmt.Sprintf("postgres://postgres:postgres@127.0.0.1:%d/postgres?sslmode=disable", m.Port)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("timeout waiting for embedded postgres to become ready")
		default:
			db, err := sql.Open("pgx", dsn)
			if err == nil {
				if err = db.PingContext(ctx); err == nil {
					db.Close()
					return nil
				}
				db.Close()
			}
			time.Sleep(300 * time.Millisecond)
		}
	}
}

func (m *DBLifecycleManager) createDatabaseAndSeed() error {
	// Create database if not exists
	dsnRoot := fmt.Sprintf("postgres://postgres:postgres@127.0.0.1:%d/postgres?sslmode=disable", m.Port)
	dbRoot, err := sql.Open("pgx", dsnRoot)
	if err != nil {
		return err
	}
	defer dbRoot.Close()

	var dbExists int
	_ = dbRoot.QueryRow("SELECT 1 FROM pg_database WHERE datname = 'smartpower_db'").Scan(&dbExists)
	if dbExists == 0 {
		_, _ = dbRoot.Exec("CREATE DATABASE smartpower_db")
	}

	// Seed schema if file exists
	if _, err := os.Stat(m.InitDataFile); err == nil {
		psqlExe := filepath.Join(m.PgBinDir, "psql.exe")
		if _, err := os.Stat(psqlExe); err == nil {
			cmd := exec.Command(psqlExe,
				"-h", "127.0.0.1",
				"-p", strconv.Itoa(m.Port),
				"-U", "postgres",
				"-d", "smartpower_db",
				"-f", m.InitDataFile,
			)
			cmd.Dir = m.PgBinDir
			pathEnv := fmt.Sprintf("PATH=%s;%s", m.PgBinDir, os.Getenv("PATH"))
			cmd.Env = append(os.Environ(), pathEnv)
			cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
			out, err := cmd.CombinedOutput()
			if err != nil {
				return fmt.Errorf("psql import error: %v, output: %s", err, string(out))
			}
		}
	}
	return nil
}

func (m *DBLifecycleManager) Stop() error {
	if !m.IsPortable {
		return nil
	}
	log.Println("🛑 Stopping embedded PostgreSQL server gracefully...")
	pgCtl := filepath.Join(m.PgBinDir, "pg_ctl.exe")
	cmd := exec.Command(pgCtl, "-D", m.DataDir, "-m", "fast", "stop")
	cmd.Dir = m.PgBinDir
	pathEnv := fmt.Sprintf("PATH=%s;%s", m.PgBinDir, os.Getenv("PATH"))
	cmd.Env = append(os.Environ(), pathEnv)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	cmd.Stdout = nil
	cmd.Stderr = nil
	_ = cmd.Run()
	return nil
}

func copyDirectory(srcDir, dstDir string) error {
	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		relPath, err := filepath.Rel(srcDir, path)
		if err != nil {
			return err
		}
		targetPath := filepath.Join(dstDir, relPath)
		if info.IsDir() {
			return os.MkdirAll(targetPath, info.Mode())
		}
		base := info.Name()
		if base == "postmaster.pid" || base == "postmaster.opts" || strings.HasPrefix(base, "server.log") {
			return nil
		}
		srcFile, err := os.Open(path)
		if err != nil {
			return err
		}
		defer srcFile.Close()

		dstFile, err := os.OpenFile(targetPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, info.Mode())
		if err != nil {
			return err
		}
		defer dstFile.Close()

		_, err = io.Copy(dstFile, srcFile)
		return err
	})
}
