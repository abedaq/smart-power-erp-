package services

import (
	"context"
	"encoding/base64"
	"fmt"
	"html"
	"log"
	"math"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/database"
	"smartpower/internal/models"

	"github.com/chromedp/chromedp"
	"gorm.io/gorm"
)

type InvoiceRenderService struct {
	cfg         *config.Config
	db          *gorm.DB
	renderMu    sync.Mutex
	allocCtx    context.Context
	cancelAlloc context.CancelFunc
	idleTimer   *time.Timer
}

func NewInvoiceRenderService(cfg *config.Config) *InvoiceRenderService {
	return &InvoiceRenderService{
		cfg: cfg,
		db:  database.DB,
	}
}

func getStationLogoBase64() string {
	paths := []string{
		"station_logo.png",
		"../station_logo.png",
		"frontend/public/station_logo.png",
		"../frontend/public/station_logo.png",
		"frontend/dist/station_logo.png",
		"../frontend/dist/station_logo.png",
		"dist/station_logo.png",
		"../dist/station_logo.png",
		"internal/ui/dist/station_logo.png",
		"../internal/ui/dist/station_logo.png",
		"d:/elctercity/frontend/public/station_logo.png",
	}
	for _, p := range paths {
		if b, err := os.ReadFile(p); err == nil && len(b) > 0 {
			return "data:image/png;base64," + base64.StdEncoding.EncodeToString(b)
		}
	}
	return ""
}

func formatMoney(v float64) string {
	negative := v < 0
	if negative {
		v = -v
	}
	integerPart := int64(v)
	str := fmt.Sprintf("%d", integerPart)
	n := len(str)
	if n <= 3 {
		if negative {
			return "-" + str
		}
		return str
	}
	var res []byte
	rem := n % 3
	if rem > 0 {
		res = append(res, str[:rem]...)
		if rem < n {
			res = append(res, ',')
		}
	}
	for i := rem; i < n; i += 3 {
		res = append(res, str[i:i+3]...)
		if i+3 < n {
			res = append(res, ',')
		}
	}
	out := string(res)
	if negative {
		return "-" + out
	}
	return out
}

func (s *InvoiceRenderService) ensureBrowserLocked() error {
	if s.allocCtx != nil && s.allocCtx.Err() == nil {
		return nil
	}

	s.resetBrowserLocked()

	opts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.DisableGPU,
		chromedp.NoSandbox,
		chromedp.Headless,
		chromedp.WindowSize(1100, 750),
	)

	localAppData := os.Getenv("LOCALAPPDATA")
	programFiles := os.Getenv("ProgramFiles")
	programFilesX86 := os.Getenv("ProgramFiles(x86)")

	chromePaths := []string{
		filepath.Join(localAppData, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(localAppData, `Google\Chrome\Application\chrome.exe`),
		filepath.Join(programFiles, `Microsoft\Edge\Application\msedge.exe`),
		filepath.Join(programFilesX86, `Microsoft\Edge\Application\msedge.exe`),
		`C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`,
		`C:\Program Files\Microsoft\Edge\Application\msedge.exe`,
		filepath.Join(programFiles, `Google\Chrome\Application\chrome.exe`),
		filepath.Join(programFilesX86, `Google\Chrome\Application\chrome.exe`),
		`C:\Program Files\Google\Chrome\Application\chrome.exe`,
		`C:\Program Files (x86)\Google\Chrome\Application\chrome.exe`,
	}
	for _, cp := range chromePaths {
		if cp != "" {
			if _, err := os.Stat(cp); err == nil {
				opts = append(opts, chromedp.ExecPath(cp))
				break
			}
		}
	}

	s.allocCtx, s.cancelAlloc = chromedp.NewExecAllocator(context.Background(), opts...)
	log.Println("🌐 [Invoice Render Worker] Persistent headless browser worker spawned.")
	return nil
}

func (s *InvoiceRenderService) resetBrowserLocked() {
	if s.cancelAlloc != nil {
		s.cancelAlloc()
		s.cancelAlloc = nil
	}
	s.allocCtx = nil
}

func (s *InvoiceRenderService) renderHTMLToPNG(htmlContent string, elementSelector string) ([]byte, error) {
	s.renderMu.Lock()
	defer s.renderMu.Unlock()

	if s.idleTimer != nil {
		s.idleTimer.Stop()
	}

	defer func() {
		// Reset 5-minute idle timer to close headless browser when not in use
		s.idleTimer = time.AfterFunc(5*time.Minute, func() {
			s.renderMu.Lock()
			defer s.renderMu.Unlock()
			if s.allocCtx != nil {
				log.Println("💤 [Invoice Render Worker] Idle timeout reached (5m). Terminating browser worker to free RAM.")
				s.resetBrowserLocked()
			}
		})
	}()

	renderOnce := func() ([]byte, error) {
		if err := s.ensureBrowserLocked(); err != nil {
			return nil, err
		}

		tabCtx, cancelTab := chromedp.NewContext(s.allocCtx)
		defer cancelTab()

		timeoutCtx, cancelTimeout := context.WithTimeout(tabCtx, 15*time.Second)
		defer cancelTimeout()

		var buf []byte
		err := chromedp.Run(timeoutCtx,
			chromedp.Navigate("about:blank"),
			chromedp.ActionFunc(func(ctx context.Context) error {
				tmpFile := filepath.Join(os.TempDir(), fmt.Sprintf("render_%d_%d.html", os.Getpid(), time.Now().UnixNano()))
				defer os.Remove(tmpFile)

				if err := os.WriteFile(tmpFile, []byte(htmlContent), 0644); err != nil {
					return err
				}

				fileURL := "file:///" + filepath.ToSlash(tmpFile)
				return chromedp.Navigate(fileURL).Do(ctx)
			}),
			chromedp.WaitVisible(elementSelector, chromedp.ByID),
			chromedp.Screenshot(elementSelector, &buf, chromedp.ByID),
		)
		if err != nil {
			return nil, err
		}
		return buf, nil
	}

	// First attempt
	buf, err := renderOnce()
	if err != nil {
		// Auto-Recovery Guard: In case of browser crash or closed pipe, reset allocator and retry once
		log.Printf("⚠️ [Invoice Render Worker] Browser render error (%v). Auto-recovering fresh browser worker...", err)
		s.resetBrowserLocked()
		buf, err = renderOnce()
		if err != nil {
			s.resetBrowserLocked()
			return nil, fmt.Errorf("failed to render image after auto-recovery: %w", err)
		}
		log.Println("✅ [Invoice Render Worker] Auto-recovery successful, rendered image.")
	}

	return buf, nil
}

func (s *InvoiceRenderService) RenderInvoicePNG(invoiceID int64) ([]byte, error) {
	var invoice models.Invoice
	err := s.db.Preload("Customer").
		Preload("Customer.SubscriptionPlan").
		Preload("MeterReading").
		First(&invoice, invoiceID).Error
	if err != nil {
		return nil, fmt.Errorf("invoice not found: %w", err)
	}

	var settings models.SystemSettings
	if err := s.db.First(&settings).Error; err != nil {
		settings.StationName = "محطة الضياء لتوليد الطاقة الكهربائية"
		settings.StationPhone = strPtr("783270260 _ 736955883")
		settings.BankAccounts = strPtr("3052001225")
	}

	htmlContent := s.generateInvoiceHTML(&invoice, &settings)
	return s.renderHTMLToPNG(htmlContent, "#invoice-card")
}

func cleanAndFormatStationPhones(p1, p2 *string) string {
	clean := func(p *string) string {
		if p == nil {
			return ""
		}
		s := strings.TrimSpace(*p)
		s = strings.TrimPrefix(s, "+967")
		s = strings.TrimPrefix(s, "00967")
		s = strings.TrimSpace(s)
		s = strings.ReplaceAll(s, " ", "")
		s = strings.ReplaceAll(s, "-", "")
		return s
	}

	c1 := clean(p1)
	c2 := clean(p2)

	if strings.Contains(c1, "_") {
		parts := strings.Split(c1, "_")
		if len(parts) == 2 {
			pA := clean(&parts[0])
			pB := clean(&parts[1])
			if pA != "" && pB != "" {
				return fmt.Sprintf("%s _ %s", pA, pB)
			}
		}
	}

	if c1 != "" && c2 != "" && c1 != c2 {
		return fmt.Sprintf("%s _ %s", c1, c2)
	}
	if c1 == "783270260" || (strings.Contains(c1, "783270260") && strings.Contains(c1, "736955883")) {
		return "783270260 _ 736955883"
	}
	if c1 != "" {
		return c1
	}
	if c2 != "" {
		return c2
	}
	return "783270260 _ 736955883"
}

func cleanBankAccount(b *string) string {
	if b == nil || strings.TrimSpace(*b) == "" {
		return "3052001225"
	}
	s := strings.TrimSpace(*b)
	if idx := strings.LastIndex(s, ":"); idx != -1 {
		num := strings.TrimSpace(s[idx+1:])
		if num != "" {
			return num
		}
	}
	return s
}

func (s *InvoiceRenderService) generateInvoiceHTML(inv *models.Invoice, set *models.SystemSettings) string {
	stationName := set.StationName
	if stationName == "" || stationName == "محطة الطاقة الذكية" {
		stationName = "محطة الضياء لتوليد الطاقة الكهربائية"
	}
	stationPhone := cleanAndFormatStationPhones(set.StationPhone, set.StationPhoneAlt)
	bankAccount := cleanBankAccount(set.BankAccounts)

	custName := "-"
	subNo := "-"
	meterNo := "-"
	routeNo := "-"
	address := "-"
	if inv.Customer != nil {
		if inv.Customer.FullName != "" {
			custName = inv.Customer.FullName
		}
		if inv.Customer.SubscriberNumber != "" {
			subNo = inv.Customer.SubscriberNumber
		}
		if inv.Customer.MeterNumber != nil && *inv.Customer.MeterNumber != "" {
			meterNo = *inv.Customer.MeterNumber
		}
		if inv.Customer.RouteNumber != nil && *inv.Customer.RouteNumber != "" {
			routeNo = *inv.Customer.RouteNumber
		}
		if inv.Customer.Address != nil && *inv.Customer.Address != "" {
			address = *inv.Customer.Address
		}
	}
	custName = html.EscapeString(custName)
	address = html.EscapeString(address)

	invNo := fmt.Sprintf("%d", inv.ID)
	if inv.InvoiceNumber != nil && *inv.InvoiceNumber != "" {
		invNo = *inv.InvoiceNumber
	}

	cycle := "الدورة الحالية"
	if inv.BillingCycle != nil && *inv.BillingCycle != "" {
		cycle = *inv.BillingCycle
	}
	cycleName := strings.TrimSpace(cycle)
	cycleName = strings.TrimPrefix(cycleName, "دورة")
	cycleName = strings.TrimSpace(cycleName)
	cycleTitle := fmt.Sprintf(`<span style="color: #dc2626;">فاتورة استهلاك كهرباء دورة </span><span style="color: #1e3a8a;">%s</span>`, cycleName)

	dateStr := time.Now().Format("02/01/2006")
	if inv.CreatedAt != nil && !inv.CreatedAt.IsZero() {
		dateStr = inv.CreatedAt.Format("02/01/2006")
	}

	logoBase64 := getStationLogoBase64()
	logoImgHTML := ""
	if logoBase64 != "" {
		logoImgHTML = fmt.Sprintf(`<img src="%s" style="width: 48px; height: 48px; object-fit: contain;" alt="logo" />`, logoBase64)
	}

	// Main Table Values
	prevStr := ""
	if inv.PreviousReading > 0 {
		prevStr = formatMoney(inv.PreviousReading)
	}
	currStr := ""
	if inv.CurrentReading > 0 {
		currStr = formatMoney(inv.CurrentReading)
	}
	consStr := ""
	if inv.Consumption > 0 {
		consStr = formatMoney(inv.Consumption)
	}
	feeStr := ""
	if inv.FixedFeeSnapshot > 0 {
		feeStr = formatMoney(inv.FixedFeeSnapshot)
	}

	kwhPrice := inv.KwhPriceSnapshot
	if kwhPrice <= 0 {
		if inv.Customer != nil && inv.Customer.SubscriptionPlan != nil && inv.Customer.SubscriptionPlan.KwhPrice > 0 {
			kwhPrice = inv.Customer.SubscriptionPlan.KwhPrice
		} else if set.DefaultKwhPrice > 0 {
			kwhPrice = set.DefaultKwhPrice
		} else {
			kwhPrice = 1400
		}
	}

	valStr := ""
	consVal := inv.ConsumptionValue
	if consVal <= 0 && inv.Consumption > 0 {
		consVal = inv.Consumption * kwhPrice
	}
	if consVal > 0 {
		valStr = formatMoney(consVal)
	}
	arrStr := ""
	if inv.Arrears != 0 {
		arrStr = formatMoney(inv.Arrears)
	}
	dueStr := ""
	if inv.TotalDue != 0 {
		dueStr = formatMoney(inv.TotalDue)
	}

	// Financial Settlement Texts
	var remainingText string
	var remColor string
	if inv.RemainingAmount > 0 {
		remainingText = fmt.Sprintf("+%s ر.ي (متبقي عليك)", formatMoney(inv.RemainingAmount))
		remColor = "#b91c1c"
	} else if inv.RemainingAmount < 0 {
		remainingText = fmt.Sprintf("-%s ر.ي (دائن لك)", formatMoney(-inv.RemainingAmount))
		remColor = "#047857"
	} else {
		remainingText = "0 ر.ي (خالص)"
		remColor = "#047857"
	}

	couponRemLabel := "المتبقي عليك:"
	couponRemVal := fmt.Sprintf("+%s ر.ي", formatMoney(inv.RemainingAmount))
	if inv.RemainingAmount < 0 {
		couponRemLabel = "رصيد دائن لك:"
		couponRemVal = fmt.Sprintf("-%s ر.ي", formatMoney(-inv.RemainingAmount))
	} else if inv.RemainingAmount == 0 {
		couponRemVal = "0 ر.ي"
	}

	paidStr := formatMoney(inv.PaidAmount)

	return fmt.Sprintf(`<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&display=swap');
  * { box-sizing: border-box; font-family: 'Cairo', Tahoma, sans-serif; margin: 0; padding: 0; font-feature-settings: "lnum" 1, "zero" 0; font-variant-numeric: lining-nums tabular-nums; }
  body { background: #fff; padding: 6px; display: flex; justify-content: center; }
  .invoice-card { width: 960px; background: #fff; border: 2px solid #000; padding: 8px; }
  .grid-container { display: grid; grid-template-columns: 5fr 7fr; gap: 0; align-items: stretch; }
  .coupon-stub { padding-left: 12px; padding-right: 4px; display: flex; flex-direction: column; justify-content: space-between; }
  .main-stub { border-right: 2px solid #000; padding-right: 12px; padding-left: 4px; display: flex; flex-direction: column; justify-content: space-between; }
  .header-box { display: flex; align-items: flex-start; justify-content: space-between; border-bottom: 2px solid #000; padding-bottom: 4px; margin-bottom: 6px; }
  .station-title { font-size: 13px; font-weight: 900; color: #000; text-align: center; }
  .station-phone { font-size: 12px; font-weight: 800; color: #1d4ed8; font-family: 'Cairo', Tahoma, sans-serif; direction: ltr; margin: 2px 0; text-align: center; }
  .bank-acc { font-size: 10.5px; font-weight: 900; color: #000; text-align: center; }
  .cust-info { font-size: 10.5px; font-weight: 900; line-height: 1.5; margin-bottom: 4px; color: #000; }
  .red-title { text-align: center; font-weight: 900; color: #dc2626; font-size: 11px; margin: 5px 0; }
  .red-title-main { text-align: center; font-weight: 900; color: #dc2626; font-size: 12px; margin: 5px 0; }
  table.custom-table { width: 100%%; border-collapse: collapse; text-align: center; border: 2px solid #000; margin-bottom: 6px; }
  table.custom-table th, table.custom-table td { border: 1px solid #000; }
  table.custom-table th { font-size: 9.5px; font-weight: 900; background: #fff; padding: 3px 2px; }
  table.custom-table td { font-size: 10.5px; font-weight: 900; font-family: 'Cairo', Tahoma, sans-serif; padding: 4px 2px; color: #000; }
  .summary-coupon { border: 1px solid #000; background: #f8fafc; padding: 4px; margin-bottom: 6px; font-size: 9.5px; font-weight: 900; }
  .summary-coupon-row { display: flex; justify-content: space-between; padding: 2px 0; }
  .summary-card { border: 2px solid #000; background: #f8fafc; padding: 5px; margin-bottom: 6px; font-size: 10px; font-weight: 900; }
  .summary-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; text-align: center; }
  .policy-box { color: #dc2626; font-size: 9px; font-weight: 900; line-height: 1.35; margin: 5px 0; }
  .sig-row { display: flex; justify-content: space-between; font-size: 10.5px; font-weight: 900; padding: 0 12px; margin-top: 10px; }
  .date-footer { font-size: 10px; font-weight: 900; font-family: 'Cairo', Tahoma, sans-serif; text-align: left; border-top: 1px solid #000; padding-top: 4px; margin-top: 6px; color: #000; }
</style>
</head>
<body>
<div id="invoice-card" class="invoice-card">
  <div class="grid-container">
    
    <!-- Part 1 (RIGHT SIDE): Collector Coupon -->
    <div class="coupon-stub">
      <div>
        <div class="header-box">
          <div style="flex: 1; text-align: center;">
            <div class="station-title">%s</div>
            <div class="station-phone">%s</div>
          </div>
          <div style="padding-top: 2px;">
            %s
          </div>
        </div>

        <div class="cust-info">
          <div><span>اسم المشترك : </span><b>%s</b></div>
          <div><span>العنوان : </span><span>%s</span></div>
          <div><span>رقم المشترك : </span><span>%s</span></div>
          <div><span>رقم العداد : </span><span>%s</span></div>
        </div>

        <div class="red-title">%s</div>

        <table class="custom-table">
          <thead>
            <tr>
              <th colspan="2">قــــــراءة العداد</th>
              <th rowspan="2">الفارق</th>
              <th rowspan="2">متأخرات وغرامات</th>
              <th rowspan="2">الاجمالي</th>
            </tr>
            <tr>
              <th>ق.السابقة</th>
              <th>ق.الحالية</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
            </tr>
          </tbody>
        </table>

        <div class="summary-coupon">
          <div class="summary-coupon-row">
            <span>المبلغ المسدد:</span>
            <span style="color: #065f46;">%s ر.ي</span>
          </div>
          <div class="summary-coupon-row" style="border-top: 1px solid rgba(0,0,0,0.3); padding-top: 2px;">
            <span>%s</span>
            <span style="color: %s;">%s</span>
          </div>
        </div>
      </div>

      <div class="sig-row">
        <div style="text-align: center;">
          <div>المحصل</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">....................</div>
        </div>
        <div style="text-align: center;">
          <div>الحسابات</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">....................</div>
        </div>
      </div>
    </div>

    <!-- Part 2 (LEFT SIDE): Main Invoice -->
    <div class="main-stub">
      <div>
        <div class="header-box">
          <div style="flex: 1; text-align: center;">
            <div class="station-title" style="font-size: 15px;">%s</div>
            <div class="station-phone" style="font-size: 13px;">%s</div>
            <div class="bank-acc">يمكنك الإيداع على الحساب %s</div>
          </div>
          <div style="padding-top: 2px;">
            %s
          </div>
        </div>

        <div class="cust-info">
          <div style="display: flex; justify-content: space-between;">
            <div><span>اسم المشترك : </span><b>%s</b></div>
            <div><span>رقم الفاتورة : </span><b>%s</b></div>
          </div>
          <div><span>العنوان : </span><span>%s</span></div>
          <div><span>رقم المشترك : </span><span>%s</span></div>
          <div style="display: flex; justify-content: space-between;">
            <div><span>رقم العداد : </span><span>%s</span></div>
            <div style="padding-left: 12px;"><span>رقم خط السير : </span><b>%s</b></div>
          </div>
        </div>

        <div class="red-title-main">%s</div>

        <table class="custom-table" style="font-size: 10px;">
          <thead>
            <tr>
              <th colspan="2">قــــــراءة العداد</th>
              <th rowspan="2">الفارق</th>
              <th rowspan="2">اشتراك</th>
              <th rowspan="2">القيمـة</th>
              <th rowspan="2">متأخرات</th>
              <th rowspan="2">الاجمالي</th>
            </tr>
            <tr>
              <th>ق. السابقة</th>
              <th>ق. الحالية</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
            </tr>
          </tbody>
        </table>

        <div class="summary-card">
          <div class="summary-grid">
            <div style="border-left: 1px solid #000; padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #475569;">إجمالي المستحق</span>
              <span style="font-size: 11px; font-weight: 900;">%s ر.ي</span>
            </div>
            <div style="border-left: 1px solid #000; padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #065f46;">المبلغ المسدد</span>
              <span style="font-size: 11px; font-weight: 900; color: #047857;">%s ر.ي</span>
            </div>
            <div style="padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #475569;">الرصيد المتبقي</span>
              <span style="font-size: 11px; font-weight: 900; color: %s;">%s</span>
            </div>
          </div>
        </div>

        <div class="policy-box">
          <div>o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.</div>
          <div>o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.</div>
          <div>o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان ألف ريال</div>
          <div>o يتحمل المشترك مديونية أي موقف إن لم يكن هناك سند رسمي مختوم بختم المحطة.</div>
          <div>o سعر الكيلوواط / ساعة %s ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.</div>
        </div>
      </div>

      <div class="sig-row">
        <div style="text-align: center;">
          <div>المحصل</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">..........................</div>
        </div>
        <div style="text-align: center;">
          <div>الحسابات</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">..........................</div>
        </div>
      </div>
    </div>

  </div>

  <div class="date-footer">
    التاريخ : %s
  </div>
</div>
</body>
</html>`,
		// Coupon Stub
		stationName, stationPhone, logoImgHTML,
		custName, address, subNo, meterNo,
		cycleTitle,
		prevStr, currStr, consStr, arrStr, dueStr,
		paidStr,
		couponRemLabel, remColor, couponRemVal,

		// Main Stub
		stationName, stationPhone, bankAccount, logoImgHTML,
		custName, invNo, address, subNo, meterNo, routeNo,
		cycleTitle,
		prevStr, currStr, consStr, feeStr, valStr, arrStr, dueStr,
		dueStr, paidStr, remColor, remainingText,
		formatMoney(kwhPrice),

		// Date
		dateStr,
	)
}

func (s *InvoiceRenderService) RenderPaymentReceiptPNG(paymentID int64) ([]byte, error) {
	var payment models.Payment
	err := s.db.Preload("Customer").
		Preload("Customer.SubscriptionPlan").
		Preload("Invoice").
		First(&payment, paymentID).Error
	if err != nil {
		return nil, fmt.Errorf("payment not found: %w", err)
	}

	var invoice models.Invoice
	if payment.Invoice != nil && payment.Invoice.ID > 0 {
		invoice = *payment.Invoice
	} else if payment.CustomerID != nil {
		s.db.Preload("Customer").
			Where("customer_id = ?", *payment.CustomerID).
			Order("id desc").
			First(&invoice)
	}

	var settings models.SystemSettings
	if err := s.db.First(&settings).Error; err != nil {
		settings.StationName = "محطة الضياء لتوليد الطاقة الكهربائية"
		settings.StationPhone = strPtr("783270260 _ 736955883")
		settings.BankAccounts = strPtr("3052001225")
	}

	var remainingBalance float64
	s.db.Model(&models.Invoice{}).
		Where("customer_id = ? AND status IN ('Unpaid', 'Partially_Paid')", payment.CustomerID).
		Select("COALESCE(SUM(remaining_amount), 0)").Scan(&remainingBalance)

	htmlContent := s.generateReceiptHTML(&payment, &invoice, &settings, remainingBalance)
	return s.renderHTMLToPNG(htmlContent, "#receipt-card")
}

func (s *InvoiceRenderService) generateReceiptHTML(payment *models.Payment, inv *models.Invoice, set *models.SystemSettings, remainingBalance float64) string {
	stationName := set.StationName
	if stationName == "" || stationName == "محطة الطاقة الذكية" {
		stationName = "محطة الضياء لتوليد الطاقة الكهربائية"
	}
	stationPhone := cleanAndFormatStationPhones(set.StationPhone, set.StationPhoneAlt)
	bankAccount := cleanBankAccount(set.BankAccounts)

	custName := "-"
	subNo := "-"
	meterNo := "-"
	routeNo := "-"
	address := "-"
	if payment.Customer != nil {
		if payment.Customer.FullName != "" {
			custName = payment.Customer.FullName
		}
		if payment.Customer.SubscriberNumber != "" {
			subNo = payment.Customer.SubscriberNumber
		}
		if payment.Customer.MeterNumber != nil && *payment.Customer.MeterNumber != "" {
			meterNo = *payment.Customer.MeterNumber
		}
		if payment.Customer.RouteNumber != nil && *payment.Customer.RouteNumber != "" {
			routeNo = *payment.Customer.RouteNumber
		}
		if payment.Customer.Address != nil && *payment.Customer.Address != "" {
			address = *payment.Customer.Address
		}
	}
	custName = html.EscapeString(custName)
	address = html.EscapeString(address)

	receiptNo := fmt.Sprintf("REC-%06d", payment.ID)
	if payment.ReceiptNumber != nil && *payment.ReceiptNumber != "" {
		receiptNo = *payment.ReceiptNumber
	}

	cycleTitle := `<span style="color: #dc2626;">فاتورة استهلاك كهرباء - سند سداد رسمي</span>`
	if inv != nil && inv.BillingCycle != nil && *inv.BillingCycle != "" {
		cName := strings.TrimSpace(*inv.BillingCycle)
		cName = strings.TrimPrefix(cName, "دورة")
		cName = strings.TrimSpace(cName)
		cycleTitle = fmt.Sprintf(`<span style="color: #dc2626;">فاتورة استهلاك كهرباء دورة </span><span style="color: #1e3a8a;">%s</span><span style="color: #dc2626;"> - سند سداد رسمي</span>`, cName)
	}

	dateStr := time.Now().Format("02/01/2006")
	if payment.PaymentDate != nil {
		dateStr = payment.PaymentDate.Format("02/01/2006")
	}

	logoBase64 := getStationLogoBase64()
	logoImgHTML := ""
	if logoBase64 != "" {
		logoImgHTML = fmt.Sprintf(`<img src="%s" style="width: 48px; height: 48px; object-fit: contain;" alt="logo" />`, logoBase64)
	}

	// Readings and numbers
	prevReading := 0.0
	currReading := 0.0
	consumption := 0.0
	fixedFee := 0.0
	consumptionVal := 0.0
	arrears := 0.0
	totalDue := 0.0
	kwhPrice := 1400.0

	if inv != nil && inv.ID > 0 {
		prevReading = inv.PreviousReading
		currReading = inv.CurrentReading
		consumption = inv.Consumption
		fixedFee = inv.FixedFeeSnapshot
		kwhPrice = inv.KwhPriceSnapshot
		if kwhPrice <= 0 {
			if payment.Customer != nil && payment.Customer.SubscriptionPlan != nil && payment.Customer.SubscriptionPlan.KwhPrice > 0 {
				kwhPrice = payment.Customer.SubscriptionPlan.KwhPrice
			} else if set.DefaultKwhPrice > 0 {
				kwhPrice = set.DefaultKwhPrice
			} else {
				kwhPrice = 1400
			}
		}
		consumptionVal = inv.ConsumptionValue
		if consumptionVal <= 0 && consumption > 0 {
			consumptionVal = consumption * kwhPrice
		}
		arrears = inv.Arrears
		totalDue = inv.TotalDue
	} else {
		if payment.Customer != nil && payment.Customer.SubscriptionPlan != nil && payment.Customer.SubscriptionPlan.KwhPrice > 0 {
			kwhPrice = payment.Customer.SubscriptionPlan.KwhPrice
		} else if set.DefaultKwhPrice > 0 {
			kwhPrice = set.DefaultKwhPrice
		}
		totalDue = payment.AmountPaid + remainingBalance
	}

	// Financial invariant: calculate remaining balance accurately
	var remaining float64
	if inv != nil && inv.ID > 0 {
		if payment.AmountPaid >= totalDue && remainingBalance <= 0 {
			overpaid := math.Round((payment.AmountPaid-totalDue)*100) / 100
			if overpaid > 0 {
				remaining = -overpaid
			} else {
				remaining = 0
			}
		} else if inv.RemainingAmount == 0 && payment.AmountPaid > 0 && remainingBalance == 0 {
			remaining = 0
		} else if remainingBalance > 0 {
			remaining = remainingBalance
		} else {
			remaining = math.Round((totalDue-payment.AmountPaid)*100) / 100
		}
	} else {
		remaining = remainingBalance
	}

	prevStr := ""
	if prevReading > 0 {
		prevStr = formatMoney(prevReading)
	}
	currStr := ""
	if currReading > 0 {
		currStr = formatMoney(currReading)
	}
	consStr := ""
	if consumption > 0 {
		consStr = formatMoney(consumption)
	}
	feeStr := ""
	if fixedFee > 0 {
		feeStr = formatMoney(fixedFee)
	}
	valStr := ""
	if consumptionVal > 0 {
		valStr = formatMoney(consumptionVal)
	}
	arrStr := ""
	if arrears != 0 {
		arrStr = formatMoney(arrears)
	}
	dueStr := ""
	if totalDue != 0 {
		dueStr = formatMoney(totalDue)
	}

	paidStr := formatMoney(payment.AmountPaid)

	var remainingText string
	var remColor string
	if remaining > 0 {
		remainingText = fmt.Sprintf("+%s ر.ي (متبقي عليك)", formatMoney(remaining))
		remColor = "#b91c1c"
	} else if remaining < 0 {
		remainingText = fmt.Sprintf("-%s ر.ي (دائن لك)", formatMoney(-remaining))
		remColor = "#047857"
	} else {
		remainingText = "0 ر.ي (خالص)"
		remColor = "#047857"
	}

	couponRemLabel := "المتبقي بعد السداد:"
	couponRemVal := fmt.Sprintf("+%s ر.ي", formatMoney(remaining))
	if remaining < 0 {
		couponRemLabel = "الرصيد الدائن:"
		couponRemVal = fmt.Sprintf("-%s ر.ي", formatMoney(-remaining))
	} else if remaining == 0 {
		couponRemVal = "0 ر.ي (خالص)"
	}

	return fmt.Sprintf(`<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&display=swap');
  * { box-sizing: border-box; font-family: 'Cairo', Tahoma, sans-serif; margin: 0; padding: 0; font-feature-settings: "lnum" 1, "zero" 0; font-variant-numeric: lining-nums tabular-nums; }
  body { background: #fff; padding: 6px; display: flex; justify-content: center; }
  .receipt-card { width: 960px; background: #fff; border: 2px solid #000; padding: 8px; }
  .grid-container { display: grid; grid-template-columns: 5fr 7fr; gap: 0; align-items: stretch; }
  .coupon-stub { padding-left: 12px; padding-right: 4px; display: flex; flex-direction: column; justify-content: space-between; }
  .main-stub { border-right: 2px solid #000; padding-right: 12px; padding-left: 4px; display: flex; flex-direction: column; justify-content: space-between; }
  .header-box { display: flex; align-items: flex-start; justify-content: space-between; border-bottom: 2px solid #000; padding-bottom: 4px; margin-bottom: 6px; }
  .station-title { font-size: 13px; font-weight: 900; color: #000; text-align: center; }
  .station-phone { font-size: 12px; font-weight: 800; color: #1d4ed8; font-family: 'Cairo', Tahoma, sans-serif; direction: ltr; margin: 2px 0; text-align: center; }
  .bank-acc { font-size: 10.5px; font-weight: 900; color: #000; text-align: center; }
  .cust-info { font-size: 10.5px; font-weight: 900; line-height: 1.5; margin-bottom: 4px; color: #000; }
  .red-title { text-align: center; font-weight: 900; color: #dc2626; font-size: 11px; margin: 5px 0; }
  .red-title-main { text-align: center; font-weight: 900; color: #dc2626; font-size: 12px; margin: 5px 0; }
  table.custom-table { width: 100%%; border-collapse: collapse; text-align: center; border: 2px solid #000; margin-bottom: 6px; }
  table.custom-table th, table.custom-table td { border: 1px solid #000; }
  table.custom-table th { font-size: 9.5px; font-weight: 900; background: #fff; padding: 3px 2px; }
  table.custom-table td { font-size: 10.5px; font-weight: 900; font-family: 'Cairo', Tahoma, sans-serif; padding: 4px 2px; color: #000; }
  .summary-coupon { border: 1px solid #000; background: #f8fafc; padding: 4px; margin-bottom: 6px; font-size: 9.5px; font-weight: 900; }
  .summary-coupon-row { display: flex; justify-content: space-between; padding: 2px 0; }
  .summary-card { border: 2px solid #000; background: #f8fafc; padding: 5px; margin-bottom: 6px; font-size: 10px; font-weight: 900; }
  .summary-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; text-align: center; }
  .policy-box { color: #dc2626; font-size: 9px; font-weight: 900; line-height: 1.35; margin: 5px 0; }
  .sig-row { display: flex; justify-content: space-between; font-size: 10.5px; font-weight: 900; padding: 0 12px; margin-top: 10px; }
  .date-footer { font-size: 10px; font-weight: 900; font-family: 'Cairo', Tahoma, sans-serif; text-align: left; border-top: 1px solid #000; padding-top: 4px; margin-top: 6px; color: #000; }
</style>
</head>
<body>
<div id="receipt-card" class="receipt-card">
  <div class="grid-container">
    
    <!-- Part 1 (RIGHT SIDE): Collector Coupon -->
    <div class="coupon-stub">
      <div>
        <div class="header-box">
          <div style="flex: 1; text-align: center;">
            <div class="station-title">%s</div>
            <div class="station-phone">%s</div>
          </div>
          <div style="padding-top: 2px;">
            %s
          </div>
        </div>

        <div class="cust-info">
          <div><span>اسم المشترك : </span><b>%s</b></div>
          <div><span>العنوان : </span><span>%s</span></div>
          <div><span>رقم المشترك : </span><span>%s</span></div>
          <div><span>رقم العداد : </span><span>%s</span></div>
        </div>

        <div class="red-title">%s</div>

        <table class="custom-table">
          <thead>
            <tr>
              <th colspan="2">قــــــراءة العداد</th>
              <th rowspan="2">الفارق</th>
              <th rowspan="2">متأخرات</th>
              <th rowspan="2">الاجمالي</th>
            </tr>
            <tr>
              <th>ق.السابقة</th>
              <th>ق.الحالية</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
            </tr>
          </tbody>
        </table>

        <div class="summary-coupon">
          <div class="summary-coupon-row">
            <span>المبلغ المسدد:</span>
            <span style="color: #065f46;">%s ر.ي</span>
          </div>
          <div class="summary-coupon-row" style="border-top: 1px solid rgba(0,0,0,0.3); padding-top: 2px;">
            <span>%s</span>
            <span style="color: %s;">%s</span>
          </div>
        </div>
      </div>

      <div class="sig-row">
        <div style="text-align: center;">
          <div>المحصل</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">....................</div>
        </div>
        <div style="text-align: center;">
          <div>الحسابات</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">....................</div>
        </div>
      </div>
    </div>

    <!-- Part 2 (LEFT SIDE): Main Receipt -->
    <div class="main-stub">
      <div>
        <div class="header-box">
          <div style="flex: 1; text-align: center;">
            <div class="station-title" style="font-size: 15px;">%s</div>
            <div class="station-phone" style="font-size: 13px;">%s</div>
            <div class="bank-acc">يمكنك الإيداع على الحساب %s</div>
          </div>
          <div style="padding-top: 2px;">
            %s
          </div>
        </div>

        <div class="cust-info">
          <div style="display: flex; justify-content: space-between;">
            <div><span>اسم المشترك : </span><b>%s</b></div>
            <div><span>رقم السند : </span><b>%s</b></div>
          </div>
          <div><span>العنوان : </span><span>%s</span></div>
          <div><span>رقم المشترك : </span><span>%s</span></div>
          <div style="display: flex; justify-content: space-between;">
            <div><span>رقم العداد : </span><span>%s</span></div>
            <div style="padding-left: 12px;"><span>رقم خط السير : </span><b>%s</b></div>
          </div>
        </div>

        <div class="red-title-main">%s</div>

        <table class="custom-table" style="font-size: 10px;">
          <thead>
            <tr>
              <th colspan="2">قــــــراءة العداد</th>
              <th rowspan="2">الفارق</th>
              <th rowspan="2">اشتراك</th>
              <th rowspan="2">القيمـة</th>
              <th rowspan="2">متأخرات</th>
              <th rowspan="2">الاجمالي</th>
            </tr>
            <tr>
              <th>ق. السابقة</th>
              <th>ق. الحالية</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
              <td>%s</td>
            </tr>
          </tbody>
        </table>

        <div class="summary-card">
          <div class="summary-grid">
            <div style="border-left: 1px solid #000; padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #475569;">إجمالي المستحق</span>
              <span style="font-size: 11px; font-weight: 900;">%s ر.ي</span>
            </div>
            <div style="border-left: 1px solid #000; padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #065f46;">المبلغ المسدد</span>
              <span style="font-size: 11px; font-weight: 900; color: #047857;">%s ر.ي</span>
            </div>
            <div style="padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #475569;">الرصيد المتبقي</span>
              <span style="font-size: 11px; font-weight: 900; color: %s;">%s</span>
            </div>
          </div>
        </div>

        <div class="policy-box">
          <div>o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.</div>
          <div>o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.</div>
          <div>o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان ألف ريال</div>
          <div>o يتحمل المشترك مديونية أي موقف إن لم يكن هناك سند رسمي مختوم بختم المحطة.</div>
          <div>o سعر الكيلوواط / ساعة %s ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.</div>
        </div>
      </div>

      <div class="sig-row">
        <div style="text-align: center;">
          <div>المحصل</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">..........................</div>
        </div>
        <div style="text-align: center;">
          <div>الحسابات</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">..........................</div>
        </div>
      </div>
    </div>

  </div>

  <div class="date-footer">
    التاريخ : %s
  </div>
</div>
</body>
</html>`,
		// Coupon Stub
		stationName, stationPhone, logoImgHTML,
		custName, address, subNo, meterNo,
		cycleTitle,
		prevStr, currStr, consStr, arrStr, dueStr,
		paidStr,
		couponRemLabel, remColor, couponRemVal,

		// Main Stub
		stationName, stationPhone, bankAccount, logoImgHTML,
		custName, receiptNo, address, subNo, meterNo, routeNo,
		cycleTitle,
		prevStr, currStr, consStr, feeStr, valStr, arrStr, dueStr,
		dueStr, paidStr, remColor, remainingText,
		formatMoney(kwhPrice),

		// Date
		dateStr,
	)
}