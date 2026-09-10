package licensing

import (
	"crypto/sha256"
	"fmt"
	"os"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

var (
	cachedHWID string
	hwidMutex  sync.Mutex
)

var (
	modkernel32              = syscall.NewLazyDLL("kernel32.dll")
	procGetVolumeInformation = modkernel32.NewProc("GetVolumeInformationW")
	procGetComputerName      = modkernel32.NewProc("GetComputerNameW")
	procGetSystemInfo        = modkernel32.NewProc("GetNativeSystemInfo")
)

type systemInfo struct {
	wProcessorArchitecture      uint16
	wReserved                   uint16
	dwPageSize                  uint32
	lpMinimumApplicationAddress uintptr
	lpMaximumApplicationAddress uintptr
	dwActiveProcessorMask       uintptr
	dwNumberOfProcessors        uint32
	dwProcessorType             uint32
	dwAllocationGranularity     uint32
	wProcessorLevel             uint16
	wProcessorRevision          uint16
}

// GetMachineHWID يستخرج بصمة العتاد الفريدة للجهاز عبر Win32 API المباشر ويحفظها في الذاكرة
func GetMachineHWID() string {
	hwidMutex.Lock()
	defer hwidMutex.Unlock()

	if cachedHWID != "" {
		return cachedHWID
	}

	var rawComponents []string

	if runtime.GOOS == "windows" {
		rawComponents = append(rawComponents, getWindowsDiskVolumeSerial())
		rawComponents = append(rawComponents, getWindowsSystemArch())
		rawComponents = append(rawComponents, getWindowsComputerIdentity())
	} else {
		// Fallback للأنظمة الأخرى أثناء التطوير
		hostname, _ := os.Hostname()
		rawComponents = append(rawComponents, "FALLBACK-DEVICE-"+runtime.GOARCH+"-"+hostname)
	}

	combined := strings.Join(rawComponents, "#")
	if strings.Trim(strings.ReplaceAll(combined, "#", ""), " ") == "" {
		combined = "SMARTPOWER-STATIC-DEV-DEVICE-2026"
	}

	hash := sha256.Sum256([]byte(combined))
	hexStr := strings.ToUpper(fmt.Sprintf("%x", hash))

	// تنسيق معرف فريد وأنيق: HWID-XXXX-XXXX-XXXX-XXXX
	cachedHWID = fmt.Sprintf("HWID-%s-%s-%s-%s",
		hexStr[0:4],
		hexStr[4:8],
		hexStr[8:12],
		hexStr[12:16],
	)

	return cachedHWID
}

func getWindowsDiskVolumeSerial() string {
	systemDrive := os.Getenv("SystemDrive")
	if systemDrive == "" {
		systemDrive = "C:"
	}
	rootPath, err := syscall.UTF16PtrFromString(systemDrive + "\\")
	if err != nil {
		return "VOL_UNKNOWN"
	}

	var volumeSerialNumber uint32
	r1, _, _ := procGetVolumeInformation.Call(
		uintptr(unsafe.Pointer(rootPath)),
		0,
		0,
		uintptr(unsafe.Pointer(&volumeSerialNumber)),
		0,
		0,
		0,
		0,
	)

	if r1 != 0 {
		return fmt.Sprintf("VOL-%08X", volumeSerialNumber)
	}
	return "VOL_UNAVAILABLE"
}

func getWindowsSystemArch() string {
	var si systemInfo
	procGetSystemInfo.Call(uintptr(unsafe.Pointer(&si)))
	return fmt.Sprintf("ARCH-%d-LVL-%d-REV-%d-CORES-%d",
		si.wProcessorArchitecture,
		si.wProcessorLevel,
		si.wProcessorRevision,
		si.dwNumberOfProcessors,
	)
}

func getWindowsComputerIdentity() string {
	var buffer [256]uint16
	var size uint32 = uint32(len(buffer))
	r1, _, _ := procGetComputerName.Call(
		uintptr(unsafe.Pointer(&buffer[0])),
		uintptr(unsafe.Pointer(&size)),
	)
	if r1 != 0 {
		return "PC-" + syscall.UTF16ToString(buffer[:size])
	}
	return "PC-" + os.Getenv("COMPUTERNAME")
}
