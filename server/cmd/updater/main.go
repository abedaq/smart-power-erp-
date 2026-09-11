package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"syscall"
	"time"
	"unsafe"
)

var (
	kernel32DLL             = syscall.NewLazyDLL("kernel32.dll")
	shell32DLL              = syscall.NewLazyDLL("shell32.dll")
	procOpenProcess         = kernel32DLL.NewProc("OpenProcess")
	procWaitForSingleObject = kernel32DLL.NewProc("WaitForSingleObject")
	procCloseHandle         = kernel32DLL.NewProc("CloseHandle")
	procShellExecuteW       = shell32DLL.NewProc("ShellExecuteW")
)

const (
	SYNCHRONIZE   = uint32(0x00100000)
	INFINITE      = uint32(0xFFFFFFFF)
	WAIT_OBJECT_0 = uint32(0x00000000)
	WAIT_TIMEOUT  = uint32(0x00000102)
	SW_SHOWNORMAL = 1
)

func initLogger() (*os.File, error) {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		localAppData = os.Getenv("APPDATA")
	}
	if localAppData == "" {
		localAppData = "."
	}
	logDir := filepath.Join(localAppData, "SmartPowerERP", "logs")
	_ = os.MkdirAll(logDir, 0755)

	logFilePath := filepath.Join(logDir, "updater.log")
	f, err := os.OpenFile(logFilePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return nil, err
	}
	log.SetOutput(f)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
	return f, nil
}

func waitForPID(pid int, timeoutMs uint32) bool {
	if pid <= 0 {
		return true
	}

	if runtime.GOOS != "windows" {
		time.Sleep(2 * time.Second)
		return true
	}

	handle, _, _ := procOpenProcess.Call(
		uintptr(SYNCHRONIZE),
		uintptr(0), // FALSE
		uintptr(uint32(pid)),
	)

	if handle == 0 {
		log.Printf("[Updater] Process PID %d does not exist or already terminated.", pid)
		return true
	}
	defer procCloseHandle.Call(handle)

	log.Printf("[Updater] Waiting for PID %d to terminate (timeout: %d ms)...", pid, timeoutMs)
	ret, _, _ := procWaitForSingleObject.Call(handle, uintptr(timeoutMs))
	if uint32(ret) == WAIT_OBJECT_0 {
		log.Printf("[Updater] PID %d terminated successfully.", pid)
		return true
	}

	log.Printf("[Updater] Wait timed out or failed for PID %d (result: 0x%X).", pid, ret)
	return false
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0755)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

func launchApplication(exePath, workDir string) error {
	if runtime.GOOS == "windows" {
		verbPtr, _ := syscall.UTF16PtrFromString("open")
		filePtr, _ := syscall.UTF16PtrFromString(exePath)
		dirPtr, _ := syscall.UTF16PtrFromString(workDir)

		ret, _, _ := procShellExecuteW.Call(
			0,
			uintptr(unsafe.Pointer(verbPtr)),
			uintptr(unsafe.Pointer(filePtr)),
			0,
			uintptr(unsafe.Pointer(dirPtr)),
			uintptr(SW_SHOWNORMAL),
		)

		if ret <= 32 {
			return fmt.Errorf("ShellExecuteW failed with code %d", ret)
		}
		return nil
	}

	return nil
}

func main() {
	logFile, _ := initLogger()
	if logFile != nil {
		defer logFile.Close()
	}

	log.Println("==================================================")
	log.Println("🚀 SmartPower ERP Native Silent Updater Helper")
	log.Println("==================================================")

	pidFlag := flag.Int("pid", 0, "PID of the running SmartPowerERP process to wait for")
	targetFlag := flag.String("target", "", "Path to the target executable to replace")
	newFlag := flag.String("new", "", "Path to the new downloaded executable")
	workDirFlag := flag.String("workdir", "", "Working directory for restarted executable")
	flag.Parse()

	targetExe := filepath.Clean(*targetFlag)
	newExe := filepath.Clean(*newFlag)
	workDir := *workDirFlag
	if workDir == "" && targetExe != "" {
		workDir = filepath.Dir(targetExe)
	}

	log.Printf("[Updater] Parameters: PID=%d, Target=%s, New=%s, WorkDir=%s", *pidFlag, targetExe, newExe, workDir)

	if targetExe == "" || newExe == "" {
		log.Println("❌ [Updater Error] Missing required target or new executable paths.")
		os.Exit(1)
	}

	// 1. Verify new binary exists and has non-zero size
	fi, err := os.Stat(newExe)
	if err != nil || fi.Size() == 0 {
		log.Printf("❌ [Updater Error] New binary %s is missing or empty: %v", newExe, err)
		os.Exit(1)
	}

	// 2. Wait for previous process to exit using Win32 API
	if *pidFlag > 0 {
		_ = waitForPID(*pidFlag, 25000)
	}
	// Extra safety delay ensuring all locks and sockets are released
	time.Sleep(1000 * time.Millisecond)

	// 3. Execute atomic rename replacement
	oldBackup := targetExe + ".old"
	_ = os.Remove(oldBackup)

	swapSuccess := false
	maxRetries := 12

	for i := 1; i <= maxRetries; i++ {
		log.Printf("[Updater] Attempt %d/%d: Renaming target executable to .old...", i, maxRetries)
		// Step A: Rename running or closed target to target.old
		if _, err := os.Stat(targetExe); err == nil {
			err = os.Rename(targetExe, oldBackup)
			if err != nil {
				log.Printf("[Updater] Rename target to .old failed (%v), retrying...", err)
				time.Sleep(500 * time.Millisecond)
				continue
			}
		}

		// Step B: Move newExe to targetExe
		log.Printf("[Updater] Moving new executable %s to target %s...", newExe, targetExe)
		err = os.Rename(newExe, targetExe)
		if err != nil {
			// Fallback: copy file
			log.Printf("[Updater] Rename newExe failed (%v), attempting copy fallback...", err)
			if cErr := copyFile(newExe, targetExe); cErr != nil {
				log.Printf("[Updater] Copy fallback also failed: %v", cErr)
				// Rollback: restore old backup
				if _, statErr := os.Stat(oldBackup); statErr == nil {
					_ = os.Rename(oldBackup, targetExe)
				}
				time.Sleep(500 * time.Millisecond)
				continue
			}
			_ = os.Remove(newExe)
		}

		swapSuccess = true
		log.Println("✅ [Updater] Binary swap completed successfully!")
		break
	}

	if !swapSuccess {
		log.Println("❌ [Updater Critical] Binary swap failed after all retries. Restoring backup if possible...")
		if _, statErr := os.Stat(oldBackup); statErr == nil {
			_ = os.Rename(oldBackup, targetExe)
		}
	}

	// 4. Launch updated application safely
	log.Printf("[Updater] Launching updated application: %s in %s", targetExe, workDir)
	time.Sleep(500 * time.Millisecond)
	if err := launchApplication(targetExe, workDir); err != nil {
		log.Printf("❌ [Updater Error] Failed to launch application: %v", err)
	} else {
		log.Println("✅ [Updater] Application launched successfully.")
	}

	log.Println("🚀 [Updater] Process complete. Exiting helper.")
	os.Exit(0)
}
