package licensing

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	SupabaseURL                 = "https://pkuoytiickgbtfeffmxq.supabase.co"
	SupabaseAnonKey             = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
	AppVersion                  = "12.04.5"
	LicenseFileName             = "smartpower_license.dat"
	MasterLicenseSigningSecret  = "b164687942e83b7d1726355a83a4b12d5487779f127786ea3c173bff25214c10"
	DefaultLicenseSigningSecret = "smartpower-default-master-key-2026"
)

// LicenseData هيكل البيانات المخزنة محلياً
type LicenseData struct {
	LicenseKey         string    `json:"license_key"`
	ClientName         string    `json:"client_name"`
	BoundHWID          string    `json:"bound_hwid"`
	Token              string    `json:"token"`
	ExpiresAt          time.Time `json:"expires_at"`
	MaxOfflineDays     int       `json:"max_offline_days"`
	LastHeartbeat      time.Time `json:"last_heartbeat"`
	LastSystemTime     int64     `json:"last_system_time"`
	UsedEmergencyCodes []string  `json:"used_emergency_codes,omitempty"`
}

// LicenseStatus الحالة المعروضة للواجهة والمستخدم
type LicenseStatus struct {
	IsLicensed       bool      `json:"is_licensed"`
	ClientName       string    `json:"client_name"`
	LicenseKey       string    `json:"license_key"`
	MachineHWID      string    `json:"machine_hwid"`
	ExpiresAt        time.Time `json:"expires_at"`
	DaysRemaining    int       `json:"days_remaining"`
	IsExpired        bool      `json:"is_expired"`
	IsOffline        bool      `json:"is_offline"`
	OfflineDaysLeft  int       `json:"offline_days_left"`
	IsTimeTampered   bool      `json:"is_time_tampered"`
	ErrorMessage     string    `json:"error_message,omitempty"`
	LastSyncTime     time.Time `json:"last_sync_time"`
}

type LicenseManager struct {
	mu           sync.RWMutex
	current      *LicenseData
	status       LicenseStatus
	storagePath  string
	httpClient   *http.Client
	stopChan     chan struct{}
}

var (
	globalManager *LicenseManager
	managerOnce   sync.Once
)

// GetLicenseManager يعيد النسخة العامة من مدير التراخيص
func GetLicenseManager() *LicenseManager {
	managerOnce.Do(func() {
		appData := os.Getenv("LOCALAPPDATA")
		if appData == "" {
			appData = "."
		}
		storageDir := filepath.Join(appData, "SmartPowerERP")
		os.MkdirAll(storageDir, 0755)

		globalManager = &LicenseManager{
			storagePath: filepath.Join(storageDir, LicenseFileName),
			httpClient: &http.Client{
				Timeout: 10 * time.Second,
			},
			stopChan: make(chan struct{}),
		}

		globalManager.LoadAndVerify()
		go globalManager.startBackgroundHeartbeat()
	})
	return globalManager
}

// LoadAndVerify يقرأ ملف الترخيص المحلي ويفحصه
func (lm *LicenseManager) LoadAndVerify() LicenseStatus {
	lm.mu.Lock()
	defer lm.mu.Unlock()

	hwid := GetMachineHWID()
	lm.status = LicenseStatus{
		IsLicensed:  false,
		MachineHWID: hwid,
	}

	data, err := os.ReadFile(lm.storagePath)
	if err != nil {
		lm.status.ErrorMessage = "لا يوجد ترخيص مفعل على هذا الجهاز"
		return lm.status
	}

	var lic LicenseData
	if err := json.Unmarshal(data, &lic); err != nil {
		lm.status.ErrorMessage = "ملف الترخيص المحلي تالف أو غير صالح"
		return lm.status
	}

	// 1. التحقق من تطابق بصمة العتاد
	if lic.BoundHWID != hwid {
		lm.status.ErrorMessage = "ملف الترخيص خاص بجهاز آخر ولا يمكن تشغيله على هذا الكمبيوتر"
		return lm.status
	}

	// 2. التحقق من التلاعب بساعة الويندوز (Anti-Clock Tampering)
	nowEpoch := time.Now().Unix()
	if lic.LastSystemTime > 0 && nowEpoch < (lic.LastSystemTime-3600) { // سماحية ساعة واحدة للمناطق الزمنية
		lm.status.IsTimeTampered = true
		lm.status.ErrorMessage = "تم رصد تلاعب في تاريخ ووقت النظام! يرجى ضبط الساعة أو الاتصال بالإنترنت"
		return lm.status
	}

	// 3. التحقق من التوقيع والحمولة
	payload, err := parseAndValidateToken(lic.Token, hwid)
	if err != nil {
		lm.status.ErrorMessage = "شهادة الترخيص غير صالحة أو تم تعديلها: " + err.Error()
		return lm.status
	}

	// 4. التحقق من تاريخ الانتهاء
	now := time.Now()
	daysRemaining := int(time.Until(lic.ExpiresAt).Hours() / 24)
	isExpired := now.After(lic.ExpiresAt)

	// 5. التحقق من مهلة الأوفلاين المسموح بها
	offlineDays := int(now.Sub(lic.LastHeartbeat).Hours() / 24)
	offlineDaysLeft := lic.MaxOfflineDays - offlineDays
	if offlineDaysLeft < 0 {
		offlineDaysLeft = 0
	}

	isOfflineExpired := offlineDays > lic.MaxOfflineDays

	if isExpired {
		lm.status.IsLicensed = false
		lm.status.IsExpired = true
		lm.status.ErrorMessage = fmt.Sprintf("انتهت فترة الاشتراك في %s. يرجى التجديد للاستمرار", lic.ExpiresAt.Format("2006-01-02"))
	} else if isOfflineExpired {
		lm.status.IsLicensed = false
		lm.status.IsOffline = true
		lm.status.ErrorMessage = fmt.Sprintf("انتهت مهلة العمل بدون إنترنت (%d يوماً). يرجى الاتصال بالإنترنت لمزامنة الاشتراك", lic.MaxOfflineDays)
	} else {
		lm.status.IsLicensed = true
	}

	lm.status.ClientName = payload.ClientName
	lm.status.LicenseKey = lic.LicenseKey
	lm.status.ExpiresAt = lic.ExpiresAt
	lm.status.DaysRemaining = daysRemaining
	lm.status.OfflineDaysLeft = offlineDaysLeft
	lm.status.LastSyncTime = lic.LastHeartbeat

	lm.current = &lic

	// تحديث آخر وقت نظام معروف
	lic.LastSystemTime = nowEpoch
	lm.saveLocalLicense(&lic)

	return lm.status
}

// Activate يقوم بتفعيل المفتاح عبر Supabase وربط الجهاز
func (lm *LicenseManager) Activate(licenseKey string) (LicenseStatus, error) {
	licenseKey = strings.ToUpper(strings.TrimSpace(licenseKey))
	if licenseKey == "" {
		return lm.GetStatus(), errors.New("يرجى إدخال مفتاح الترخيص")
	}

	hwid := GetMachineHWID()

	reqBody, _ := json.Marshal(map[string]interface{}{
		"p_license_key": licenseKey,
		"p_hwid":        hwid,
		"p_app_version": AppVersion,
	})

	url := SupabaseURL + "/rest/v1/rpc/activate_license_rpc"
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(reqBody))
	if err != nil {
		return lm.GetStatus(), fmt.Errorf("خطأ في إنشاء الطلب: %v", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+SupabaseAnonKey)

	resp, err := lm.httpClient.Do(req)
	if err != nil {
		return lm.GetStatus(), fmt.Errorf("تعذر الاتصال بخادم التفعيل. تأكد من وجود اتصال بالإنترنت: %v", err)
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return lm.GetStatus(), fmt.Errorf("فشل التفعيل (رمز %d): %s", resp.StatusCode, string(bodyBytes))
	}

	var res struct {
		Success        bool   `json:"success"`
		LicenseKey     string `json:"license_key"`
		ClientName     string `json:"client_name"`
		BoundHWID      string `json:"bound_hwid"`
		ExpiresAt      string `json:"expires_at"`
		MaxOfflineDays int    `json:"max_offline_days"`
		Token          string `json:"token"`
		Message        string `json:"message"`
		ErrorCode      string `json:"error_code"`
	}

	if err := json.Unmarshal(bodyBytes, &res); err != nil {
		return lm.GetStatus(), fmt.Errorf("خطأ في قراءة استجابة السيرفر: %v", err)
	}

	if !res.Success {
		return lm.GetStatus(), errors.New(res.Message)
	}

	expTime, err := time.Parse(time.RFC3339, res.ExpiresAt)
	if err != nil {
		expTime = time.Now().AddDate(0, 1, 0)
	}

	if res.MaxOfflineDays <= 0 {
		res.MaxOfflineDays = 14
	}

	lic := LicenseData{
		LicenseKey:     res.LicenseKey,
		ClientName:     res.ClientName,
		BoundHWID:      res.BoundHWID,
		Token:          res.Token,
		ExpiresAt:      expTime,
		MaxOfflineDays: res.MaxOfflineDays,
		LastHeartbeat:  time.Now(),
		LastSystemTime: time.Now().Unix(),
	}

	if err := lm.saveLocalLicense(&lic); err != nil {
		return lm.GetStatus(), fmt.Errorf("تعذر حفظ الترخيص محلياً: %v", err)
	}

	return lm.LoadAndVerify(), nil
}

// ActivateOfflineCode يقوم بتفعيل كود طوارئ أوفلاين تم توليده من الإدارة مع التحقق التشفيري الكامل
func (lm *LicenseManager) ActivateOfflineCode(emergencyCode string) (LicenseStatus, error) {
	emergencyCode = strings.ToUpper(strings.TrimSpace(emergencyCode))
	if !strings.HasPrefix(emergencyCode, "EMG-") {
		return lm.GetStatus(), errors.New("صيغة كود الطوارئ غير صحيحة (يجب أن يبدأ بـ EMG-)")
	}

	lm.mu.Lock()
	if lm.current == nil {
		lm.mu.Unlock()
		return lm.GetStatus(), errors.New("يجب تفعيل البرنامج لمرة واحدة على الأقل قبل استخدام كود الطوارئ")
	}

	// 1. فحص عدم تكرار استخدام نفس الكود (Anti-Replay Protection)
	for _, used := range lm.current.UsedEmergencyCodes {
		if used == emergencyCode {
			lm.mu.Unlock()
			return lm.GetStatus(), errors.New("تم استخدام كود الطوارئ هذا مسبقاً ولا يمكن إعادة تفعيله مرة أخرى")
		}
	}

	// 2. فحص التوقيع الرياضي المشفر لكود الطوارئ
	// الصيغة القياسية: EMG-{days}-{hash12}
	// الصيغة السابقة: EMG-{hash16}
	extendDays := 15
	isValidCode := false

	candidateSecrets := []string{
		os.Getenv("LICENSE_SIGNING_SECRET"),
		MasterLicenseSigningSecret,
		DefaultLicenseSigningSecret,
	}

	parts := strings.Split(emergencyCode, "-")
	if len(parts) == 3 {
		// EMG-{days}-{hash12}
		if d, err := strconv.Atoi(parts[1]); err == nil && d > 0 && d <= 90 {
			extendDays = d
			expectedPayload := fmt.Sprintf("EMERGENCY|%s|%s|%d", lm.current.LicenseKey, lm.current.BoundHWID, extendDays)
			for _, sec := range candidateSecrets {
				if sec == "" {
					continue
				}
				mac := hmac.New(sha256.New, []byte(sec))
				mac.Write([]byte(expectedPayload))
				expectedSig := strings.ToUpper(hex.EncodeToString(mac.Sum(nil)))
				if len(expectedSig) >= 12 && subtle.ConstantTimeCompare([]byte(expectedSig[:12]), []byte(parts[2])) == 1 {
					isValidCode = true
					break
				}
			}
		}
	} else if len(parts) == 2 && len(parts[1]) == 16 {
		// EMG-{hash16}
		expectedPayload := fmt.Sprintf("EMERGENCY|%s|%s|%d", lm.current.LicenseKey, lm.current.BoundHWID, 15)
		for _, sec := range candidateSecrets {
			if sec == "" {
				continue
			}
			mac := hmac.New(sha256.New, []byte(sec))
			mac.Write([]byte(expectedPayload))
			expectedSig := strings.ToUpper(hex.EncodeToString(mac.Sum(nil)))
			if len(expectedSig) >= 16 && subtle.ConstantTimeCompare([]byte(expectedSig[:16]), []byte(parts[1])) == 1 {
				isValidCode = true
				break
			}
		}
	}

	if !isValidCode {
		lm.mu.Unlock()
		return lm.GetStatus(), errors.New("كود الطوارئ غير صالح أو غير مخصص لهذا الجهاز")
	}

	// تسجيل الكود في قائمة الأكواد المستهلكة محلياً لمنع تكراره
	lm.current.UsedEmergencyCodes = append(lm.current.UsedEmergencyCodes, emergencyCode)

	// تمديد الترخيص محلياً بالأيام المقررة
	baseTime := time.Now()
	if lm.current.ExpiresAt.After(baseTime) {
		baseTime = lm.current.ExpiresAt
	}
	lm.current.ExpiresAt = baseTime.AddDate(0, 0, extendDays)
	lm.current.LastHeartbeat = time.Now()
	lm.current.LastSystemTime = time.Now().Unix()

	// تحديث التوكن ليعكس التاريخ الجديد منعاً لرفضه أثناء التحقق الدوري
	newExpiresEpoch := lm.current.ExpiresAt.Unix()
	newIssuedAt := time.Now().Unix()
	newPayloadStr := fmt.Sprintf("%s|%s|%s|%d|%d|%d",
		lm.current.LicenseKey,
		lm.current.BoundHWID,
		lm.current.ClientName,
		newExpiresEpoch,
		lm.current.MaxOfflineDays,
		newIssuedAt,
	)
	mac := hmac.New(sha256.New, []byte(MasterLicenseSigningSecret))
	mac.Write([]byte(newPayloadStr))
	newSig := hex.EncodeToString(mac.Sum(nil))
	lm.current.Token = base64.StdEncoding.EncodeToString([]byte(newPayloadStr)) + "." + newSig

	lm.saveLocalLicense(lm.current)
	lm.mu.Unlock()

	return lm.LoadAndVerify(), nil
}

// GetStatus يعيد الحالة الحالية للترخيص
func (lm *LicenseManager) GetStatus() LicenseStatus {
	lm.mu.RLock()
	defer lm.mu.RUnlock()
	return lm.status
}

// TriggerSync يقوم بمزامنة فورية مع السحابة ويعيد الحالة المحدثة
func (lm *LicenseManager) TriggerSync() LicenseStatus {
	lm.performHeartbeat()
	return lm.GetStatus()
}

func (lm *LicenseManager) saveLocalLicense(lic *LicenseData) error {
	data, err := json.MarshalIndent(lic, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(lm.storagePath, data, 0600)
}

func (lm *LicenseManager) startBackgroundHeartbeat() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	// محاولة أولية بعد 5 ثوانٍ من التشغيل
	time.Sleep(5 * time.Second)
	lm.performHeartbeat()

	for {
		select {
		case <-ticker.C:
			lm.performHeartbeat()
		case <-lm.stopChan:
			return
		}
	}
}

func (lm *LicenseManager) performHeartbeat() {
	lm.mu.RLock()
	if lm.current == nil || lm.current.LicenseKey == "" {
		lm.mu.RUnlock()
		return
	}
	key := lm.current.LicenseKey
	hwid := lm.current.BoundHWID
	lm.mu.RUnlock()

	reqBody, _ := json.Marshal(map[string]interface{}{
		"p_license_key": key,
		"p_hwid":        hwid,
		"p_app_version": AppVersion,
	})

	url := SupabaseURL + "/rest/v1/rpc/heartbeat_license_rpc"
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(reqBody))
	if err != nil {
		return
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", SupabaseAnonKey)
	req.Header.Set("Authorization", "Bearer "+SupabaseAnonKey)

	resp, err := lm.httpClient.Do(req)
	if err != nil {
		return // لا يوجد إنترنت، يستمر بنظام الأوفلاين
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		var res struct {
			Success   bool   `json:"success"`
			Token     string `json:"token"`
			ExpiresAt string `json:"expires_at"`
			IsActive  bool   `json:"is_active"`
			ErrorCode string `json:"error_code"`
			Message   string `json:"message"`
		}
		body, _ := io.ReadAll(resp.Body)
		if err := json.Unmarshal(body, &res); err == nil {
			if !res.Success {
				if res.ErrorCode == "INACTIVE" || res.ErrorCode == "NOT_FOUND" || res.ErrorCode == "HWID_MISMATCH" {
					lm.mu.Lock()
					lm.status.IsLicensed = false
					if res.Message != "" {
						lm.status.ErrorMessage = res.Message
					} else {
						lm.status.ErrorMessage = "تم إيقاف هذا الاشتراك من قبل الإدارة"
					}
					lm.current = nil
					os.Remove(lm.storagePath)
					lm.mu.Unlock()
				}
				return
			}

			lm.mu.Lock()
			if lm.current != nil {
				if expTime, err := time.Parse(time.RFC3339, res.ExpiresAt); err == nil {
					lm.current.ExpiresAt = expTime
				}
				lm.current.Token = res.Token
				lm.current.LastHeartbeat = time.Now()
				lm.current.LastSystemTime = time.Now().Unix()
				lm.saveLocalLicense(lm.current)
			}
			lm.mu.Unlock()
			lm.LoadAndVerify()
		}
	}
}

type tokenPayload struct {
	LicenseKey     string
	HWID           string
	ClientName     string
	ExpiresEpoch   int64
	MaxOfflineDays int
	IssuedAt       int64
}

func parseAndValidateToken(tokenStr string, expectedHWID string) (*tokenPayload, error) {
	parts := strings.Split(tokenStr, ".")
	if len(parts) != 2 {
		return nil, errors.New("بنية التوكن غير متوافقة")
	}

	payloadBytes, err := base64.StdEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, errors.New("فشل فك ترميز حمولة التوكن")
	}

	rawSig := strings.ToLower(strings.TrimSpace(parts[1]))
	if len(rawSig) != 64 {
		return nil, errors.New("التوقيع الرقمي للتوكن مفقود أو غير مكتمل")
	}

	// 1. التحقق الجنائي من التوقيع الرقمي HMAC-SHA256
	candidateSecrets := []string{
		os.Getenv("LICENSE_SIGNING_SECRET"),
		MasterLicenseSigningSecret,
		DefaultLicenseSigningSecret,
	}

	sigMatched := false
	for _, sec := range candidateSecrets {
		if sec == "" {
			continue
		}
		mac := hmac.New(sha256.New, []byte(sec))
		mac.Write(payloadBytes)
		computedSig := hex.EncodeToString(mac.Sum(nil))
		if subtle.ConstantTimeCompare([]byte(computedSig), []byte(rawSig)) == 1 {
			sigMatched = true
			break
		}
	}

	if !sigMatched {
		return nil, errors.New("التوقيع الرقمي للترخيص غير صالح أو تم التلاعب بمحتواه")
	}

	fields := strings.Split(string(payloadBytes), "|")
	if len(fields) < 6 {
		return nil, errors.New("حقول التوكن غير مكتملة")
	}

	payload := &tokenPayload{
		LicenseKey: fields[0],
		HWID:       fields[1],
		ClientName: fields[2],
	}

	if payload.HWID != expectedHWID {
		return nil, errors.New("العتاد المسجل في التوكن لا يطابق هذا الكمبيوتر")
	}

	if exp, err := strconv.ParseInt(fields[3], 10, 64); err == nil {
		payload.ExpiresEpoch = exp
	}
	if maxOff, err := strconv.Atoi(fields[4]); err == nil {
		payload.MaxOfflineDays = maxOff
	}
	if issued, err := strconv.ParseInt(fields[5], 10, 64); err == nil {
		payload.IssuedAt = issued
	}

	return payload, nil
}
