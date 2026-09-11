package main

import (
	"fmt"
	"io"
	"log"
	"mime"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/handlers"
	"smartpower/internal/middleware"
	"smartpower/internal/models"
	"smartpower/internal/services"
	"smartpower/internal/ui"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/filesystem"
	"github.com/gofiber/fiber/v2/middleware/logger"
	fiberRecover "github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/jchv/go-webview2"
)

func init() {
	_ = mime.AddExtensionType(".css", "text/css; charset=utf-8")
	_ = mime.AddExtensionType(".js", "application/javascript; charset=utf-8")
	_ = mime.AddExtensionType(".mjs", "application/javascript; charset=utf-8")
	_ = mime.AddExtensionType(".json", "application/json; charset=utf-8")
	_ = mime.AddExtensionType(".svg", "image/svg+xml")
	_ = mime.AddExtensionType(".png", "image/png")
	_ = mime.AddExtensionType(".jpg", "image/jpeg")
	_ = mime.AddExtensionType(".jpeg", "image/jpeg")
	_ = mime.AddExtensionType(".ico", "image/x-icon")
	_ = mime.AddExtensionType(".woff", "font/woff")
	_ = mime.AddExtensionType(".woff2", "font/woff2")
	_ = mime.AddExtensionType(".ttf", "font/ttf")
}

var (
	kernel32DLL             = syscall.NewLazyDLL("kernel32.dll")
	user32DLL               = syscall.NewLazyDLL("user32.dll")
	procCreateMutexW        = kernel32DLL.NewProc("CreateMutexW")
	procCloseHandle         = kernel32DLL.NewProc("CloseHandle")
	procSetStdHandle        = kernel32DLL.NewProc("SetStdHandle")
	procMessageBoxW         = user32DLL.NewProc("MessageBoxW")
	procFindWindowW         = user32DLL.NewProc("FindWindowW")
	procEnumWindows         = user32DLL.NewProc("EnumWindows")
	procGetWindowTextW      = user32DLL.NewProc("GetWindowTextW")
	procIsWindowVisible     = user32DLL.NewProc("IsWindowVisible")
	procShowWindow          = user32DLL.NewProc("ShowWindow")
	procSetForegroundWindow = user32DLL.NewProc("SetForegroundWindow")
)

const (
	ERROR_ALREADY_EXISTS = 183
	SW_RESTORE           = 9
	stdOutputHandle      = uint32(0xFFFFFFF5) // -11
	stdErrorHandle       = uint32(0xFFFFFFF4) // -12
)

func setWindowsStdHandle(nStdHandle uint32, handle uintptr) {
	if runtime.GOOS == "windows" {
		procSetStdHandle.Call(uintptr(nStdHandle), handle)
	}
}

func acquireSingleInstanceMutex() (uintptr, error) {
	if runtime.GOOS != "windows" {
		return 0, nil
	}

	// 1. If port 3000 is listening and responds, an actual instance is actively running
	conn, err := net.DialTimeout("tcp", "127.0.0.1:3000", 300*time.Millisecond)
	if err == nil {
		conn.Close()
		return 0, fmt.Errorf("ALREADY_RUNNING")
	}

	mutexName, _ := syscall.UTF16PtrFromString("Local\\SmartPowerERP_SingleInstance_Mutex")
	handle, _, errCall := procCreateMutexW.Call(0, 1, uintptr(unsafe.Pointer(mutexName)))
	if handle == 0 {
		return 0, fmt.Errorf("failed to create mutex: %v", errCall)
	}

	return handle, nil
}

func focusExistingWindow() {
	if runtime.GOOS != "windows" {
		return
	}

	// 1. Direct FindWindowW matching common application window titles
	knownTitles := []string{"SmartPower ERP", "SmartPower Utility ERP", "SmartPower"}
	for _, t := range knownTitles {
		titlePtr, err := syscall.UTF16PtrFromString(t)
		if err == nil {
			hwnd, _, _ := procFindWindowW.Call(0, uintptr(unsafe.Pointer(titlePtr)))
			if hwnd != 0 {
				procShowWindow.Call(hwnd, SW_RESTORE)
				procSetForegroundWindow.Call(hwnd)
				return
			}
		}
	}

	// 2. Fallback to EnumWindows to find any visible window containing "SmartPower" in title
	cb := syscall.NewCallback(func(hwnd uintptr, lparam uintptr) uintptr {
		if r, _, _ := procIsWindowVisible.Call(hwnd); r == 0 {
			return 1
		}
		var buf [512]uint16
		r, _, _ := procGetWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), 512)
		if r > 0 {
			title := syscall.UTF16ToString(buf[:r])
			if strings.Contains(strings.ToLower(title), "smartpower") {
				procShowWindow.Call(hwnd, SW_RESTORE)
				procSetForegroundWindow.Call(hwnd)
				return 0
			}
		}
		return 1
	})
	procEnumWindows.Call(cb, 0)
}

func showInfoMessageBox(title, message string) {
	if runtime.GOOS == "windows" {
		lpText, _ := syscall.UTF16PtrFromString(message)
		lpCaption, _ := syscall.UTF16PtrFromString(title)

		// MB_OK (0x00000000) | MB_ICONINFORMATION (0x00000040) | MB_SYSTEMMODAL (0x00001000)
		procMessageBoxW.Call(0, uintptr(unsafe.Pointer(lpText)), uintptr(unsafe.Pointer(lpCaption)), 0x00001040)
	}
}

type RotatingLogWriter struct {
	mu          sync.Mutex
	logDir      string
	logFile     *os.File
	currentSize int64
	maxSize     int64 // 10 MB
}

func NewRotatingLogWriter() (*RotatingLogWriter, error) {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	if localAppData == "" {
		localAppData = "."
	}
	logDir := filepath.Join(localAppData, "SmartPowerERP", "logs")
	_ = os.MkdirAll(logDir, 0755)

	w := &RotatingLogWriter{
		logDir:  logDir,
		maxSize: 10 * 1024 * 1024,
	}
	if err := w.openCurrentLog(); err != nil {
		return nil, err
	}
	return w, nil
}

func (w *RotatingLogWriter) openCurrentLog() error {
	logFilePath := filepath.Join(w.logDir, "server.log")
	fi, err := os.Stat(logFilePath)
	if err == nil {
		w.currentSize = fi.Size()
		if w.currentSize >= w.maxSize {
			_ = w.rotate()
		}
	}

	f, err := os.OpenFile(logFilePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return err
	}
	w.logFile = f
	return nil
}

func (w *RotatingLogWriter) rotate() error {
	if w.logFile != nil {
		_ = w.logFile.Close()
	}
	logFilePath := filepath.Join(w.logDir, "server.log")
	oldLogPath := filepath.Join(w.logDir, "server.log.old")
	_ = os.Remove(oldLogPath)
	_ = os.Rename(logFilePath, oldLogPath)
	w.currentSize = 0
	return nil
}

func (w *RotatingLogWriter) Write(p []byte) (n int, err error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.currentSize+int64(len(p)) >= w.maxSize {
		_ = w.rotate()
		_ = w.openCurrentLog()
		os.Stderr = w.logFile
		os.Stdout = w.logFile
		if w.logFile != nil {
			setWindowsStdHandle(stdErrorHandle, w.logFile.Fd())
			setWindowsStdHandle(stdOutputHandle, w.logFile.Fd())
		}
	}

	if w.logFile == nil {
		return 0, os.ErrInvalid
	}
	n, err = w.logFile.Write(p)
	w.currentSize += int64(n)
	return n, err
}

func (w *RotatingLogWriter) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.logFile != nil {
		return w.logFile.Close()
	}
	return nil
}

func initLogging() *RotatingLogWriter {
	w, err := NewRotatingLogWriter()
	if err == nil {
		mw := io.MultiWriter(os.Stdout, w)
		log.SetOutput(mw)
		os.Stderr = w.logFile
		os.Stdout = w.logFile
		if w.logFile != nil {
			setWindowsStdHandle(stdErrorHandle, w.logFile.Fd())
			setWindowsStdHandle(stdOutputHandle, w.logFile.Fd())
		}
		return w
	}
	return nil
}

func SafeGo(workerName string, fn func()) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				buf := make([]byte, 4096)
				n := runtime.Stack(buf, false)
				log.Printf("❌ [PANIC RECOVERED in %s] %v\nStack:\n%s", workerName, r, string(buf[:n]))
			}
		}()
		fn()
	}()
}

func showFatalMessageBox(title, message string) {
	if runtime.GOOS == "windows" {
		user32 := syscall.NewLazyDLL("user32.dll")
		messageBoxW := user32.NewProc("MessageBoxW")

		lpText, _ := syscall.UTF16PtrFromString(message)
		lpCaption, _ := syscall.UTF16PtrFromString(title)

		// MB_OK (0x00000000) | MB_ICONERROR (0x00000010) | MB_SYSTEMMODAL (0x00001000)
		messageBoxW.Call(0, uintptr(unsafe.Pointer(lpText)), uintptr(unsafe.Pointer(lpCaption)), 0x00001010)
	}
}

func cleanupOldBinaries() {
	execPath, err := os.Executable()
	if err != nil {
		return
	}
	appDir := filepath.Dir(execPath)
	entries, err := os.ReadDir(appDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(strings.ToLower(entry.Name()), ".old") {
			oldPath := filepath.Join(appDir, entry.Name())
			if err := os.Remove(oldPath); err == nil {
				log.Printf("🧹 Cleaned up legacy update binary: %s", oldPath)
			}
		}
	}
}

var shutdownOnce sync.Once

func main() {
	// 0. Single-Instance Mutex Check (Local User Session Scope)
	mutexHandle, err := acquireSingleInstanceMutex()
	if err != nil && err.Error() == "ALREADY_RUNNING" {
		log.Println("⚠️ Another instance of SmartPower ERP is already running. Focusing window and exiting...")
		focusExistingWindow()
		showInfoMessageBox(
			"SmartPower ERP",
			"برنامج SmartPower ERP يعمل بالفعل في شريط المهام أو عبر نافذة أخرى.\n\nلا يمكن فتح أكثر من نسخة في نفس الوقت لتجنب تضارب البيانات.",
		)
		if mutexHandle != 0 {
			procCloseHandle.Call(mutexHandle)
		}
		os.Exit(0)
	} else if err != nil {
		log.Printf("⚠️ Warning creating single instance mutex: %v", err)
	}

	logFile := initLogging()
	if logFile != nil {
		defer logFile.Close()
	}

	// 0.1 Clean up legacy .old binaries from previous atomic updates
	cleanupOldBinaries()

	log.Println("==================================================")
	log.Println("🚀 SmartPower Utility ERP - Standalone Go Engine")
	log.Println("==================================================")

	// 1. Load Configuration
	cfg := config.LoadConfig()

	// 1.1 Embedded Database Lifecycle Management
	dbManager, err := database.NewDBLifecycleManager()
	if err != nil {
		log.Printf("⚠️ DB Lifecycle Manager initialization warning: %v", err)
	} else {
		dbURL, err := dbManager.EnsureDatabaseReady()
		if err != nil {
			errMsg := fmt.Sprintf("تعذر تشغيل وتجهيز قاعدة البيانات المدمجة:\n%v\n\nيرجى مراجعة ملف السجل في: %%LOCALAPPDATA%%\\SmartPowerERP\\logs\\server.log", err)
			log.Printf("❌ Failed to ensure embedded database readiness: %v", err)
			showFatalMessageBox("SmartPower ERP - خطأ في قاعدة البيانات", errMsg)
			if mutexHandle != 0 {
				procCloseHandle.Call(mutexHandle)
			}
			os.Exit(1)
		}
		if dbURL != "" {
			cfg.DatabaseURL = dbURL
			log.Printf("🔌 Connected to embedded PostgreSQL engine on: %s", dbURL)
		}
	}
	defer func() {
		if dbManager != nil {
			_ = dbManager.Stop()
		}
	}()

	// 2. Initialize Database Connection
	db, err := database.InitDB(cfg)
	if err != nil {
		errMsg := fmt.Sprintf("فشل الاتصال بقاعدة البيانات:\n%v\n\nيرجى مراجعة ملف السجل.", err)
		log.Printf("❌ Database connection failed: %v", err)
		showFatalMessageBox("SmartPower ERP - خطأ في الاتصال", errMsg)
		os.Exit(1)
	}

	// 3. Seed initial admin user if table is empty
	var userCount int64
	db.Model(&models.User{}).Count(&userCount)
	if userCount == 0 {
		authSvc := services.NewAuthService(cfg)
		hashedPwd, _ := authSvc.HashPassword("password123")
		adminUser := models.User{
			Username:     "admin",
			PasswordHash: hashedPwd,
			FullName:     "مدير النظام",
			Role:         "ADMIN",
			IsActive:     true,
		}
		db.Create(&adminUser)
		log.Println("👤 Seeded initial default admin user: admin / password123")
	}

	// 4. Initialize Core Services
	eventHub := services.NewEventHub()
	authService := services.NewAuthService(cfg)
	customerService := services.NewCustomerService()
	_ = customerService.EnsureAllCustomersHaveActiveInvoice()
	readingService := services.NewReadingService()
	billingService := services.NewBillingService()
	_ = billingService.DeduplicateInvoices()
	paymentService := services.NewPaymentService()
	renderService := services.NewInvoiceRenderService(cfg)
	excelService := services.NewExcelService(readingService, billingService)
	backupService := services.NewBackupService(cfg)
	whatsappService, err := services.NewWhatsAppService(db, cfg, renderService)
	if err != nil {
		log.Printf("⚠️ Warning initializing WhatsApp Service: %v", err)
	} else {
		whatsappService.SetEventHub(eventHub)
		whatsappService.Start()
		log.Println("📱 Initialized and started WhatsApp Web Service Engine")
	}

	// 4.1 Initialize and start Live Cloud Sync Engine
	cloudSyncService := services.NewCloudSyncService(db, cfg)
	cloudSyncService.Start()

	// 4.2 Initialize Auto-Updater Service
	updateService := services.NewUpdateService(cfg, eventHub, nil)

	// 4.3 Initialize Diagnostics & Support Service
	diagnosticsService := services.NewDiagnosticsService(cfg)

	// 5. Initialize Handlers
	h := handlers.NewHandlers(
		authService,
		customerService,
		readingService,
		billingService,
		paymentService,
		renderService,
		excelService,
		backupService,
		whatsappService,
		updateService,
		eventHub,
	)
	h.SetDiagnosticsService(diagnosticsService)

	// 6. Setup Fiber Web Application
	app := fiber.New(fiber.Config{
		AppName:      "SmartPower ERP Standalone",
		BodyLimit:    50 * 1024 * 1024,
		ServerHeader: "SmartPower-Engine",
	})

	app.Use(fiberRecover.New(fiberRecover.Config{
		EnableStackTrace: true,
		StackTraceHandler: func(c *fiber.Ctx, e interface{}) {
			buf := make([]byte, 4096)
			n := runtime.Stack(buf, false)
			log.Printf("❌ [HTTP PANIC RECOVERED] %s %s | Error: %v\nStack:\n%s", c.Method(), c.Path(), e, string(buf[:n]))
		},
	}))
	app.Use(logger.New())
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
		AllowMethods: "GET, POST, PUT, DELETE, OPTIONS",
	}))

	// Define Centralized Graceful Shutdown Function
	doShutdown := func() {
		shutdownOnce.Do(func() {
			// 1. مؤقت الإعدام القسري (Watchdog) - 4 ثوانٍ لضمان عدم بقاء العملية معلقة تحت أي ظرف
			go func() {
				time.Sleep(4 * time.Second)
				log.Println("⚠️ Watchdog timeout reached during shutdown. Force exiting...")
				os.Exit(0)
			}()

			log.Println("🛑 Graceful shutdown initiated...")

			// 2. تحرير قفل الـ Mutex فوراً في أول جزء من الثانية للسماح بإعادة التشغيل اللحظي
			if mutexHandle != 0 && runtime.GOOS == "windows" {
				procCloseHandle.Call(mutexHandle)
				mutexHandle = 0
				log.Println("🔓 Single instance mutex released.")
			}

			// 3. إيقاف خادم الويب وتحرير المنفذ
			if app != nil {
				if err := app.Shutdown(); err != nil {
					log.Printf("⚠️ Error shutting down web server: %v", err)
				}
			}
			if cloudSyncService != nil {
				cloudSyncService.Stop()
			}

			// 4. إيقاف محرك قاعدة البيانات وحفظ الملفات
			log.Println("🛑 Stopping embedded database engine cleanly...")
			if dbManager != nil {
				if err := dbManager.Stop(); err != nil {
					log.Printf("⚠️ Error stopping embedded database: %v", err)
				}
			}

			log.Println("✅ SmartPower ERP engine cleanly stopped.")
			if logFile != nil {
				_ = logFile.Close()
			}
			os.Exit(0)
		})
	}
	updateService.SetShutdownFn(doShutdown)

	// 7. Register API Routes
	api := app.Group("/api")

	// Realtime SSE Event Stream
	api.Get("/realtime/stream", h.StreamEvents)
	api.Get("/events", h.StreamEvents)

	// Auto-Update Engine routes
	api.Get("/system/check-updates", h.CheckUpdates)
	api.Get("/system/update-status", h.GetUpdateStatus)
	api.Post("/system/download-update", h.DownloadUpdate)
	api.Post("/system/apply-update", h.ApplyUpdate)
	api.Post("/system/update-ui", middleware.AuthRequired(authService), h.UpdateUI)

	// Cloud Sync endpoints
	api.Get("/system/sync-status", func(c *fiber.Ctx) error {
		return c.JSON(cloudSyncService.GetStatus())
	})
	api.Post("/system/sync-now", func(c *fiber.Ctx) error {
		cloudSyncService.TriggerSync()
		return c.JSON(fiber.Map{"status": "triggered", "message": "Cloud sync triggered"})
	})

	// System Shutdown & Lifecycle
	api.Post("/system/shutdown", func(c *fiber.Ctx) error {
		log.Println("🛑 Shutdown requested via POST /api/system/shutdown")
		SafeGo("APIShutdown", func() {
			time.Sleep(150 * time.Millisecond)
			doShutdown()
		})
		return c.JSON(fiber.Map{"status": "ok", "message": "SmartPower ERP server is shutting down..."})
	})
	api.Get("/system/shutdown", func(c *fiber.Ctx) error {
		log.Println("🛑 Shutdown requested via GET /api/system/shutdown")
		SafeGo("APIShutdown", func() {
			time.Sleep(150 * time.Millisecond)
			doShutdown()
		})
		return c.JSON(fiber.Map{"status": "ok", "message": "SmartPower ERP server is shutting down..."})
	})

	// System & Network Info
	api.Get("/system/network-info", h.GetNetworkInfo)
	api.Post("/system/diagnostics/upload", h.UploadDiagnostics)
	api.Post("/system/diagnostics/export", h.ExportDiagnostics)

	// License routes (Public for activation & check)
	api.Get("/license/status", h.GetLicenseStatus)
	api.Get("/license/hwid", h.GetMachineHWID)
	api.Post("/license/activate", h.ActivateLicense)
	api.Post("/license/emergency-code", h.ActivateEmergencyCode)

	// Auth routes
	api.Post("/auth/login", h.Login)
	api.Get("/auth/me", middleware.AuthRequired(authService), h.GetMe)

	// User management & Audit Logs
	api.Get("/users", middleware.AuthRequired(authService), h.GetUsers)
	api.Post("/users", middleware.AuthRequired(authService), h.CreateUser)
	api.Put("/users/:id", middleware.AuthRequired(authService), h.UpdateUser)
	api.Post("/users/:id/reset-password", middleware.AuthRequired(authService), h.ResetUserPassword)
	api.Get("/audit", h.GetAuditLogs)
	api.Get("/audit/logs", h.GetAuditLogs)
	api.Get("/audit-logs", h.GetAuditLogs)
	api.Post("/audit/activity", middleware.AuthRequired(authService), h.LogActivity)

	// Customer routes
	api.Get("/customers", h.GetAllCustomers)
	api.Get("/customers/next-subscriber-number", h.GetNextSubscriberNumber)
	api.Get("/customers/next-number", h.GetNextSubscriberNumber)
	api.Get("/customers/routes", h.GetRoutes)
	api.Get("/customers/regions", h.GetRegions)
	api.Get("/customers/:id", h.GetCustomer)
	api.Post("/customers", middleware.AuthRequired(authService), h.CreateCustomer)
	api.Put("/customers/:id", middleware.AuthRequired(authService), h.UpdateCustomer)
	api.Patch("/customers/:id", middleware.AuthRequired(authService), h.UpdateCustomer)
	api.Patch("/customers/:id/grid-cell", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Put("/customers/:id/grid-cell", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Patch("/customers/:id/cell-update", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Put("/customers/:id/cell-update", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Delete("/customers/:id", middleware.AuthRequired(authService), h.DeleteCustomer)

	// Reading routes
	api.Get("/readings", h.GetReadings)
	api.Get("/today-readings", h.GetReadings)
	api.Post("/readings", middleware.AuthRequired(authService), h.CreateReading)
	api.Post("/readings/:id/approve-and-whatsapp", middleware.AuthRequired(authService), h.ApproveReadingAndWhatsApp)
	api.Post("/readings/approve/:id", middleware.AuthRequired(authService), h.ApproveReading)
	api.Post("/readings/reject/:id", middleware.AuthRequired(authService), h.RejectReading)
	api.Put("/readings/:id", middleware.AuthRequired(authService), h.UpdateReading)
	api.Put("/readings/:id/cell-update", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Patch("/readings/:id/cell-update", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Post("/readings/approve-all", middleware.AuthRequired(authService), h.ApproveAllReadings)

	// Payment routes
	api.Get("/payments", h.GetPayments)
	api.Post("/payments", middleware.AuthRequired(authService), h.CreatePayment)
	api.Post("/payments/:id/send-whatsapp", middleware.AuthRequired(authService), h.SendPaymentWhatsApp)
	api.Post("/payments/approve/:id", middleware.AuthRequired(authService), h.ApprovePayment)
	api.Post("/payments/reject/:id", middleware.AuthRequired(authService), h.RejectPayment)

	// Invoices & Billing routes
	api.Get("/invoices", h.GetInvoices)
	api.Get("/invoices/cycles", h.GetBillingCycles)
	api.Get("/invoices/:id", h.GetInvoice)
	api.Get("/invoices/:id/render", h.RenderInvoice)
	api.Put("/invoices/:id/cell-update", middleware.AuthRequired(authService), h.UpdateGridCell)
	api.Patch("/invoices/:id/cell-update", middleware.AuthRequired(authService), h.UpdateGridCell)

	// Settings & Plans
	api.Get("/settings", h.GetSettings)
	api.Put("/settings", middleware.AuthRequired(authService), h.UpdateSettings)
	api.Get("/plans", h.GetPlans)

	// WhatsApp Gateway routes
	api.Get("/whatsapp/status", h.GetWhatsAppStatus)
	api.Get("/whatsapp/messages", h.GetWhatsAppMessages)
	api.Get("/whatsapp/stream", h.GetWhatsAppMessages)
	api.Post("/whatsapp/send-test", middleware.AuthRequired(authService), h.SendTestWhatsApp)
	api.Post("/whatsapp/restart", h.RestartWhatsApp)
	api.Post("/whatsapp/logout", h.LogoutWhatsApp)
	api.Post("/whatsapp/connect", h.ConnectWhatsApp)
	api.Post("/whatsapp/send-invoice", middleware.AuthRequired(authService), h.SendInvoiceWhatsApp)
	api.Post("/whatsapp/send-warning", middleware.AuthRequired(authService), h.SendWarningWhatsApp)
	api.Post("/whatsapp/send-bulk-warnings", middleware.AuthRequired(authService), h.SendBulkWarningsWhatsApp)
	api.Delete("/whatsapp/queue/pending", h.ClearPendingWhatsAppQueue)
	api.Post("/whatsapp/queue/clear", h.ClearPendingWhatsAppQueue)
	api.Delete("/whatsapp/queue", h.ClearPendingWhatsAppQueue)
	api.Post("/whatsapp/queue/retry-all", h.RetryAllWhatsAppQueue)
	api.Delete("/whatsapp/messages/:id", h.DeleteWhatsAppMessage)
	api.Post("/whatsapp/messages/:id/retry", h.RetryWhatsAppMessage)
	api.Delete("/whatsapp/messages", h.ClearAllWhatsAppMessages)

	// Analytics routes
	api.Get("/analytics/monthly-performance", h.GetMonthlyPerformance)
	api.Get("/analytics/dashboard-summary", h.GetDashboardSummary)
	api.Get("/analytics/routes-progress", h.GetRoutesProgress)
	api.Get("/analytics/overdue-report", h.GetOverdueReport)

	// Excel Import / Export
	api.Post("/import/readings", middleware.AuthRequired(authService), h.ImportExcel)
	api.Get("/export/cycle", h.ExportCycleExcel)
	api.Get("/export/cycle/:id", h.ExportCycleExcel)
	api.Get("/export/billing-cycle/:id", h.ExportCycleExcel)

	// Backup trigger
	api.Post("/backup/now", middleware.AuthRequired(authService), h.TriggerBackup)

	// 8. Dynamic UI Overlay & Embedded Frontend Distribution
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	customUIDist := ""
	if localAppData != "" {
		candidate := filepath.Join(localAppData, "SmartPowerERP", "custom_ui", "dist")
		if fi, err := os.Stat(candidate); err == nil && fi.IsDir() {
			if _, err := os.Stat(filepath.Join(candidate, "index.html")); err == nil {
				customUIDist = candidate
				log.Printf("🎨 Dynamic Custom UI Overlay active: %s", customUIDist)
			}
		}
	}

	embeddedFS := ui.GetFS()

	// Direct handler for /assets/* guaranteeing correct MIME types and preventing HTML fallback
	app.Get("/assets/*", func(c *fiber.Ctx) error {
		filePath := strings.TrimPrefix(c.Path(), "/")
		if idx := strings.Index(filePath, "assets/"); idx != -1 {
			filePath = filePath[idx:]
		}

		var content []byte
		var err error

		// 1. Check custom UI dist on disk first
		if customUIDist != "" {
			diskAsset := filepath.Join(customUIDist, filePath)
			if fi, sErr := os.Stat(diskAsset); sErr == nil && !fi.IsDir() {
				content, err = os.ReadFile(diskAsset)
			}
		}

		// 2. Fallback to embedded filesystem
		if content == nil {
			fileData, fErr := embeddedFS.Open(filePath)
			if fErr != nil {
				return c.Status(fiber.StatusNotFound).SendString("Asset not found")
			}
			defer fileData.Close()

			content, err = io.ReadAll(fileData)
			if err != nil {
				return c.Status(fiber.StatusInternalServerError).SendString("Error reading asset")
			}
		}

		p := strings.ToLower(filePath)
		if strings.HasSuffix(p, ".css") {
			c.Set("Content-Type", "text/css; charset=utf-8")
		} else if strings.HasSuffix(p, ".js") || strings.HasSuffix(p, ".mjs") {
			c.Set("Content-Type", "application/javascript; charset=utf-8")
		} else if strings.HasSuffix(p, ".svg") {
			c.Set("Content-Type", "image/svg+xml")
		} else if strings.HasSuffix(p, ".woff2") {
			c.Set("Content-Type", "font/woff2")
		} else if strings.HasSuffix(p, ".woff") {
			c.Set("Content-Type", "font/woff")
		} else if strings.HasSuffix(p, ".ttf") {
			c.Set("Content-Type", "font/ttf")
		} else if strings.HasSuffix(p, ".png") {
			c.Set("Content-Type", "image/png")
		} else if strings.HasSuffix(p, ".ico") {
			c.Set("Content-Type", "image/x-icon")
		}

		c.Set("Cache-Control", "public, max-age=31536000, immutable")
		return c.Send(content)
	})

	if customUIDist != "" {
		app.Use("/", filesystem.New(filesystem.Config{
			Root:         http.Dir(customUIDist),
			Index:        "index.html",
			NotFoundFile: "index.html",
			MaxAge:       3600,
		}))
	} else {
		app.Use("/", filesystem.New(filesystem.Config{
			Root:         embeddedFS,
			Index:        "index.html",
			NotFoundFile: "index.html", // SPA client-side router fallback
			MaxAge:       3600,
		}))
	}


	// 9. Schedule Automatic Backup Ticker (Every 10 Minutes)
	SafeGo("BackupScheduler", func() {
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			log.Println("[Backup] Executing scheduled database backup (10-minute interval)...")
			if path, err := backupService.RunBackup(); err != nil {
				log.Printf("[Backup] Backup error: %v", err)
			} else {
				log.Printf("[Backup] Periodic backup completed: %s", path)
			}
		}
	})

	// 10. Auto-open native webview window on start
	SafeGo("NativeWindowLauncher", func() {
		time.Sleep(800 * time.Millisecond)
		openNativeWindow(fmt.Sprintf("http://localhost:%s", cfg.Port), doShutdown)
	})

	// 11. Graceful Shutdown Signal Interceptor
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	SafeGo("ShutdownSignalInterceptor", func() {
		<-quit
		log.Println("🛑 OS Shutdown signal received (SIGINT/SIGTERM). Stopping SmartPower ERP...")
		doShutdown()
	})

	// 12. Start Server Listener (LAN & Localhost)
	cleanPort := strings.TrimPrefix(cfg.Port, ":")
	addr := fmt.Sprintf("0.0.0.0:%s", cleanPort)
	log.Printf("🌐 Server listening on http://%s (Localhost & LAN Mobile Access)", addr)
	if err := app.Listen(addr); err != nil {
		errMsg := fmt.Sprintf("فشل تشغيل خادم الويب على المنفذ %s:\n%v\n\nقد يكون المنفذ مستخدماً من قبل برنامج آخر.", cleanPort, err)
		log.Printf("❌ Server listen error: %v", err)
		showFatalMessageBox("SmartPower ERP - خطأ في تشغيل السيرفر", errMsg)
		doShutdown()
	}
}

func findModernBrowserPath() string {
	localAppData := os.Getenv("LOCALAPPDATA")
	programFiles := os.Getenv("ProgramFiles")
	programFilesX86 := os.Getenv("ProgramFiles(x86)")

	candidates := []string{
		filepath.Join(localAppData, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(programFiles, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(programFilesX86, `Microsoft\Edge\Application\msedge.exe`),
		`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`,
		`C:\Program Files\Microsoft\Edge\Application\msedge.exe`,
		filepath.Join(localAppData, `Google\Chrome\Application\chrome.exe`),
		filepath.Join(programFiles, `Google\Chrome\Application\chrome.exe`),
		filepath.Join(programFilesX86, `Google\Chrome\Application\chrome.exe`),
		`C:\Program Files\Google\Chrome\Application\chrome.exe`,
		`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`,
	}

	for _, p := range candidates {
		if p != "" {
			if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
				return p
			}
		}
	}

	// Try querying Windows Registry for msedge.exe or chrome.exe App Path
	registryKeys := []string{
		`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe`,
		`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe`,
	}

	for _, key := range registryKeys {
		regCmd := exec.Command("reg", "query", key, "/ve")
		regCmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
		if out, err := regCmd.Output(); err == nil {
			lines := strings.Split(string(out), "\n")
			for _, l := range lines {
				if strings.Contains(l, "REG_SZ") {
					parts := strings.SplitN(l, "REG_SZ", 2)
					if len(parts) == 2 {
						browserPath := strings.TrimSpace(parts[1])
						if fi, err := os.Stat(browserPath); err == nil && !fi.IsDir() {
							return browserPath
						}
					}
				}
			}
		}
	}

	return ""
}

func openNativeWindow(url string, onWindowClose func()) {
	if runtime.GOOS == "windows" {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()

		localAppData := os.Getenv("LOCALAPPDATA")
		if localAppData == "" {
			localAppData = os.Getenv("APPDATA")
		}
		if localAppData == "" {
			localAppData = "."
		}
		profileDir := filepath.Join(localAppData, "SmartPowerERP", "webview_profile")
		_ = os.MkdirAll(profileDir, 0755)

		// 1. Direct Embedded Win32 WebView2
		w := webview2.NewWithOptions(webview2.WebViewOptions{
			Debug:     false,
			DataPath:  profileDir,
			AutoFocus: true,
			WindowOptions: webview2.WindowOptions{
				Title:  "SmartPower ERP",
				Width:  1440,
				Height: 900,
				Center: true,
			},
		})

		if w != nil {
			defer w.Destroy()
			w.SetTitle("SmartPower ERP")
			w.SetSize(1440, 900, webview2.HintNone)
			w.Navigate(url)
			log.Println("🖥️ Launched native embedded Win32 WebView2 application window")
			w.Run()
			log.Println("🛑 Native embedded window closed by user. Initiating backend shutdown...")
			if onWindowClose != nil {
				onWindowClose()
			}
			return
		}

		// 2. Fallback to external Edge / Chrome app mode if WebView2 COM creation returned nil
		log.Println("⚠️ Embedded WebView2 initialization returned nil, falling back to modern browser...")
		browserPath := findModernBrowserPath()
		if browserPath != "" {
			edgeProfileDir := filepath.Join(localAppData, "SmartPowerERP", "edge_profile")
			_ = os.MkdirAll(edgeProfileDir, 0755)

			cmd := exec.Command(browserPath,
				fmt.Sprintf("--app=%s", url),
				fmt.Sprintf("--user-data-dir=%s", edgeProfileDir),
				"--window-size=1440,900",
				"--hide-crash-restore-bubble",
				"--disable-background-mode",
				"--disable-features=msStartupBoost,TranslateUI",
				"--no-first-run",
				"--no-default-browser-check",
			)
			if err := cmd.Start(); err == nil {
				log.Printf("🖥️ Launched application window via: %s (%s)", filepath.Base(browserPath), url)
				_ = cmd.Wait()
				log.Println("🛑 Modern browser window closed by user. Initiating backend shutdown...")
				if onWindowClose != nil {
					onWindowClose()
				}
				return
			}
		}

		// Fallback to opening default system browser
		_ = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
		log.Printf("🖥️ Opened web interface in default browser: %s", url)
		return
	}

	if runtime.GOOS == "darwin" {
		_ = exec.Command("open", url).Start()
	} else {
		_ = exec.Command("xdg-open", url).Start()
	}
}