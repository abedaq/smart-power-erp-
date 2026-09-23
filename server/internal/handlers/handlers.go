package handlers

import (
	"context"
	"fmt"
	"net"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"smartpower/internal/database"
	"smartpower/internal/licensing"
	"smartpower/internal/models"
	"smartpower/internal/services"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"
)

type Handlers struct {
	authService     *services.AuthService
	customerService *services.CustomerService
	readingService  *services.ReadingService
	billingService  *services.BillingService
	paymentService  *services.PaymentService
	renderService   *services.InvoiceRenderService
	excelService    *services.ExcelService
	backupService   *services.BackupService
	whatsappService    *services.WhatsAppService
	updateService      *services.UpdateService
	diagnosticsService *services.DiagnosticsService
	streamingBackupService *services.StreamingBackupService
	remoteCommandWorker    *services.RemoteCommandWorker
	eventHub           *services.EventHub
	db                 *gorm.DB
}

func NewHandlers(
	authService *services.AuthService,
	customerService *services.CustomerService,
	readingService *services.ReadingService,
	billingService *services.BillingService,
	paymentService *services.PaymentService,
	renderService *services.InvoiceRenderService,
	excelService *services.ExcelService,
	backupService *services.BackupService,
	whatsappService *services.WhatsAppService,
	updateService *services.UpdateService,
	eventHub *services.EventHub,
) *Handlers {
	return &Handlers{
		authService:     authService,
		customerService: customerService,
		readingService:  readingService,
		billingService:  billingService,
		paymentService:  paymentService,
		renderService:   renderService,
		excelService:    excelService,
		backupService:   backupService,
		whatsappService: whatsappService,
		updateService:   updateService,
		eventHub:        eventHub,
		db:              database.DB,
	}
}

func (h *Handlers) SetDiagnosticsService(ds *services.DiagnosticsService) {
	h.diagnosticsService = ds
}

func (h *Handlers) SetStreamingBackupService(s *services.StreamingBackupService) {
	h.streamingBackupService = s
}

func (h *Handlers) SetRemoteCommandWorker(w *services.RemoteCommandWorker) {
	h.remoteCommandWorker = w
}

// ---------------- REALTIME EVENT STREAM HANDLER ----------------

func (h *Handlers) StreamEvents(c *fiber.Ctx) error {
	if h.eventHub != nil {
		return h.eventHub.HandleSSEStream(c)
	}
	return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{"error": "EventHub not initialized"})
}

// ---------------- AUTH HANDLERS ----------------

func (h *Handlers) Login(c *fiber.Ctx) error {
	var req struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request body"})
	}

	user, token, err := h.authService.Login(req.Username, req.Password)
	if err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"token":   token,
		"data":    user,
		"user":    user,
	})
}

func (h *Handlers) GetMe(c *fiber.Ctx) error {
	claims, ok := c.Locals("user").(*services.JWTClaims)
	if !ok || claims == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"success": false, "message": "Unauthorized"})
	}

	var user models.User
	if err := h.db.First(&user, claims.UserID).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "User not found"})
	}

	return c.JSON(fiber.Map{"success": true, "data": user, "user": user})
}

// ---------------- CUSTOMER HANDLERS ----------------

func (h *Handlers) GetAllCustomers(c *fiber.Ctx) error {
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "1000"))
	route := c.Query("route", "")
	search := c.Query("search", "")
	status := c.Query("status", "")

	filter := services.CustomerFilter{
		Search:      search,
		RouteNumber: route,
		Status:      status,
		Page:        page,
		Limit:       limit,
	}

	customers, total, err := h.customerService.ListCustomers(filter)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{
		"success":    true,
		"data":       customers,
		"customers":  customers,
		"total":      total,
		"page":       page,
		"limit":      limit,
		"totalPages": (total + int64(limit) - 1) / int64(limit),
	})
}

func (h *Handlers) GetCustomer(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}

	customer, err := h.customerService.GetCustomer(id)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Customer not found"})
	}

	return c.JSON(fiber.Map{"success": true, "data": customer, "customer": customer})
}

func (h *Handlers) CreateCustomer(c *fiber.Ctx) error {
	var customer models.Customer
	if err := c.BodyParser(&customer); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	auditCtx := h.getAuditContext(c)
	created, err := h.customerService.CreateCustomer(&customer, auditCtx)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{"success": true, "data": created, "customer": created})
}

func (h *Handlers) UpdateCustomer(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}

	var updates map[string]interface{}
	if err := c.BodyParser(&updates); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	auditCtx := h.getAuditContext(c)
	updated, err := h.customerService.UpdateCustomer(id, updates, auditCtx)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{"success": true, "data": updated, "customer": updated})
}

func (h *Handlers) DeleteCustomer(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}

	auditCtx := h.getAuditContext(c)
	if err := h.customerService.DeleteCustomer(id, auditCtx); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{"success": true, "message": "Customer deleted successfully"})
}

func (h *Handlers) GetRoutes(c *fiber.Ctx) error {
	routes, err := h.customerService.GetRoutes()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}
	return c.JSON(fiber.Map{"success": true, "data": routes, "routes": routes})
}

func (h *Handlers) GetNextSubscriberNumber(c *fiber.Ctx) error {
	nextNum := h.customerService.GetNextSubscriberNumber()
	return c.JSON(fiber.Map{
		"success":                true,
		"next_subscriber_number": nextNum,
		"data": fiber.Map{
			"next_subscriber_number": nextNum,
		},
	})
}

// ---------------- READING HANDLERS ----------------

func (h *Handlers) CreateReading(c *fiber.Ctx) error {
	var req services.CreateReadingRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	if claims, ok := c.Locals("user").(*services.JWTClaims); ok && claims != nil {
		if req.CollectorName == "" {
			req.CollectorName = claims.FullName
		}
		req.CollectorUserID = &claims.UserID
	}
	req.IPAddress = c.IP()

	result, err := h.readingService.CreateReading(req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("READINGS_CHANGED", map[string]interface{}{"reading_id": result.Reading.ID, "action": "CREATE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"success":    true,
		"data":       result,
		"reading":    result.Reading,
		"newReading": result.Reading,
		"invoice":    result.Invoice,
	})
}

func (h *Handlers) GetReadings(c *fiber.Ctx) error {
	custID, _ := strconv.ParseInt(c.Query("customer_id", "0"), 10, 64)
	cycle := c.Query("cycle", "")
	if cycle == "" {
		cycle = c.Query("period", "")
	}
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "100"))

	readings, total, err := h.readingService.ListReadings(custID, cycle, page, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{
		"success":  true,
		"data":     readings,
		"readings": readings,
		"total":    total,
	})
}

// ---------------- PAYMENT HANDLERS ----------------

func (h *Handlers) CreatePayment(c *fiber.Ctx) error {
	var req services.CreatePaymentRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	if claims, ok := c.Locals("user").(*services.JWTClaims); ok && claims != nil {
		if req.AccountantName == "" {
			req.AccountantName = claims.FullName
		}
		req.AccountantUserID = &claims.UserID
	}
	req.IPAddress = c.IP()

	result, err := h.paymentService.CreatePayment(req)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("PAYMENTS_CHANGED", map[string]interface{}{"payment_id": result.Payment.ID, "action": "CREATE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{
		"success":     true,
		"data":        result,
		"payment":     result.Payment,
		"allocations": result.Allocations,
		"credit":      result.Credit,
	})
}

func (h *Handlers) GetPayments(c *fiber.Ctx) error {
	custID, _ := strconv.ParseInt(c.Query("customer_id", "0"), 10, 64)
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "100"))

	payments, total, err := h.paymentService.ListPayments(custID, page, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{
		"success":  true,
		"data":     payments,
		"payments": payments,
		"total":    total,
	})
}

// ---------------- INVOICE HANDLERS ----------------

func (h *Handlers) GetInvoices(c *fiber.Ctx) error {
	custID, _ := strconv.ParseInt(c.Query("customer_id", "0"), 10, 64)
	cycle := c.Query("cycle", "")
	if cycle == "" {
		cycle = c.Query("period", "")
	}
	status := c.Query("status", "")
	route := c.Query("route", "")
	region := c.Query("region", "")
	search := c.Query("search", "")
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "1000"))

	filter := services.InvoiceFilter{
		CustomerID:   custID,
		BillingCycle: cycle,
		Status:       status,
		RouteNumber:  route,
		Region:       region,
		Search:       search,
		Page:         page,
		Limit:        limit,
	}

	invoices, total, err := h.billingService.ListInvoices(filter)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{
		"success":  true,
		"data":     invoices,
		"invoices": invoices,
		"total":    total,
	})
}

func (h *Handlers) GetInvoice(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}

	invoice, err := h.billingService.GetInvoice(id)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Invoice not found"})
	}

	return c.JSON(fiber.Map{"success": true, "data": invoice, "invoice": invoice})
}

func (h *Handlers) RenderInvoice(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}

	pngBytes, err := h.renderService.RenderInvoicePNG(id)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	c.Set("Content-Type", "image/png")
	return c.Send(pngBytes)
}

func (h *Handlers) GetBillingCycles(c *fiber.Ctx) error {
	cycles, err := h.billingService.GetBillingCycles()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}
	return c.JSON(fiber.Map{"success": true, "data": cycles, "cycles": cycles})
}

// ---------------- SETTINGS HANDLERS ----------------

func (h *Handlers) GetSettings(c *fiber.Ctx) error {
	var settings models.SystemSettings
	if err := h.db.First(&settings).Error; err != nil {
		settings = models.SystemSettings{
			StationName:      "محطة الضياء لتوليد الطاقة الكهربائية",
			StationPhone:     strPtr("783270260 _ 736955883"),
			BankAccounts:     strPtr("3052001225"),
			DefaultKwhPrice:  1400,
			DefaultFixedFee:  1000,
			MaxOverdueDays:   10,
			WhatsAppStatus:   "Disconnected",
			ReceiptFooter:    strPtr("شكراً لتعاملكم معنا، يرجى الاحتفاظ بالإيصال لغرض المراجعة"),
		}
		h.db.Create(&settings)
	}

	return c.JSON(fiber.Map{"success": true, "data": settings, "settings": settings})
}

func (h *Handlers) UpdateSettings(c *fiber.Ctx) error {
	var updates map[string]interface{}
	if err := c.BodyParser(&updates); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	var settings models.SystemSettings
	if err := h.db.First(&settings).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Settings not found"})
	}

	delete(updates, "id")
	if err := h.db.Model(&settings).Updates(updates).Error; err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	h.logAudit(c, "UPDATE_SETTINGS", "SETTINGS", nil, "تحديث إعدادات النظام والتعرفة المالية والبيانات العامة")

	return c.JSON(fiber.Map{"success": true, "data": settings, "settings": settings})
}

// ---------------- PLANS HANDLERS ----------------

func (h *Handlers) GetPlans(c *fiber.Ctx) error {
	var plans []models.SubscriptionPlan
	if err := h.db.Where("is_active = true").Find(&plans).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}
	return c.JSON(fiber.Map{"success": true, "data": plans, "plans": plans})
}

// ---------------- EXCEL IMPORT / EXPORT ----------------

func (h *Handlers) ImportExcel(c *fiber.Ctx) error {
	file, err := c.FormFile("file")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Excel file required"})
	}

	f, err := file.Open()
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Failed to open uploaded file"})
	}
	defer f.Close()

	cycle := c.FormValue("cycle", "")
	collector := c.FormValue("collector", "استيراد ملف")

	res, err := h.excelService.ImportReadingsExcel(f, cycle, collector)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{"success": true, "data": res})
}

func (h *Handlers) ExportCycleExcel(c *fiber.Ctx) error {
	cycle := c.Query("cycle", "")
	if cycle == "" {
		cycle = c.Params("id", "")
	}
	bytes, err := h.excelService.ExportCycleExcel(cycle)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	filename := "Cycle_All.xlsx"
	if cycle != "" && strings.ToUpper(cycle) != "ALL" {
		filename = fmt.Sprintf("Billing_Cycle_%s.xlsx", strings.ReplaceAll(cycle, "/", "_"))
	}

	c.Set("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	c.Set("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	return c.Send(bytes)
}

// ---------------- BACKUP HANDLER ----------------

func (h *Handlers) TriggerBackup(c *fiber.Ctx) error {
	path, err := h.backupService.RunDailyBackup()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}
	return c.JSON(fiber.Map{"success": true, "message": "Backup created successfully", "path": path})
}

func (h *Handlers) UploadCloudBackup(c *fiber.Ctx) error {
	if h.streamingBackupService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة النسخ السحابي غير مهيأة",
		})
	}

	var req struct {
		UserNote string `json:"user_note"`
	}
	_ = c.BodyParser(&req)

	metrics, err := h.streamingBackupService.ExecuteBackupAndUpload(c.Context(), req.UserNote)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": fmt.Sprintf("فشل رفع النسخة السحابية: %v", err),
		})
	}

	h.logAudit(c, "CLOUD_BACKUP_UPLOAD", "DATABASE", nil, fmt.Sprintf("تم رفع نسخة احتياطية سحابية كاملة بنجاح [%s]", metrics.ReferenceID))

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم رفع النسخة الاحتياطية السحابية بنجاح وتوثيقها في السحابة",
		"data":    metrics,
	})
}

func (h *Handlers) TriggerRemoteCommandCheck(c *fiber.Ctx) error {
	if h.remoteCommandWorker == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة الأوامر عن بعد غير متوفرة",
		})
	}

	h.remoteCommandWorker.Trigger()
	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم إرسال إشارة فحص الأوامر السحابية فوراً",
	})
}

// ---------------- CUSTOMER GRID CELL & REGIONS ----------------

func (h *Handlers) UpdateGridCell(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}

	var payload map[string]interface{}
	if err := c.BodyParser(&payload); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	auditCtx := h.getAuditContext(c)
	updated, err := h.customerService.UpdateGridCell(id, payload, auditCtx)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.JSON(fiber.Map{"success": true, "data": updated, "customer": updated})
}

func (h *Handlers) GetRegions(c *fiber.Ctx) error {
	regions, err := h.customerService.GetRegions()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}
	return c.JSON(fiber.Map{"success": true, "data": regions, "regions": regions})
}

// ---------------- READING APPROVALS ----------------

func (h *Handlers) ApproveReading(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	auditCtx := h.getAuditContext(c)
	if err := h.readingService.ApproveReading(id, auditCtx); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("READINGS_CHANGED", map[string]interface{}{"id": id, "action": "APPROVE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	return c.JSON(fiber.Map{"success": true, "message": "Reading approved"})
}

func (h *Handlers) RejectReading(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	var req struct {
		Reason string `json:"reason"`
	}
	_ = c.BodyParser(&req)
	auditCtx := h.getAuditContext(c)
	if err := h.readingService.RejectReading(id, req.Reason, auditCtx); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("READINGS_CHANGED", map[string]interface{}{"id": id, "action": "REJECT"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	return c.JSON(fiber.Map{"success": true, "message": "Reading rejected"})
}

func (h *Handlers) ApproveAllReadings(c *fiber.Ctx) error {
	auditCtx := h.getAuditContext(c)
	if err := h.readingService.ApproveAllPending(auditCtx); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("READINGS_CHANGED", map[string]interface{}{"action": "APPROVE_ALL"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	return c.JSON(fiber.Map{"success": true, "message": "All readings approved"})
}

func (h *Handlers) ApproveReadingAndWhatsApp(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	auditCtx := h.getAuditContext(c)
	if err := h.readingService.ApproveReading(id, auditCtx); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("READINGS_CHANGED", map[string]interface{}{"id": id, "action": "APPROVE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	var inv models.Invoice
	if err := h.db.Preload("Customer").Where("reading_id = ?", id).First(&inv).Error; err == nil {
		if inv.Customer != nil && inv.Customer.PhoneNumber != "" {
			phone := services.NormalizeWhatsAppPhone(inv.Customer.PhoneNumber)
			now := time.Now().UTC()
			sourceEntity := "INVOICE"
			msgType := "IMAGE"
			qMsg := models.WhatsAppQueueMessage{
				PhoneNumber:  phone,
				Type:         msgType,
				Message:      nil,
				Status:       "PENDING",
				SourceEntity: &sourceEntity,
				SourceID:     &inv.ID,
				ScheduledAt:  &now,
				CreatedAt:    &now,
				UpdatedAt:    &now,
			}
			if h.whatsappService != nil {
				_ = h.whatsappService.EnqueueMessage(&qMsg)
			}
		}
	}

	return c.JSON(fiber.Map{"success": true, "message": "تم اعتماد القراءة وإدراج الفاتورة في طابور الواتساب للإرسال الآمن بنجاح"})
}

func (h *Handlers) UpdateReading(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	var req struct {
		ReadingValue float64 `json:"reading_value"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	auditCtx := h.getAuditContext(c)
	updated, err := h.readingService.UpdateReading(id, map[string]interface{}{
		"reading_value": req.ReadingValue,
	}, auditCtx)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("READINGS_CHANGED", map[string]interface{}{"id": id, "action": "UPDATE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
		h.eventHub.Broadcast("CUSTOMERS_CHANGED", nil)
	}

	return c.JSON(fiber.Map{"success": true, "data": updated, "reading": updated, "message": "Reading updated successfully"})
}

// ---------------- PAYMENT APPROVALS ----------------

func (h *Handlers) ApprovePayment(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	auditCtx := h.getAuditContext(c)
	if err := h.paymentService.ApprovePayment(id, auditCtx); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("PAYMENTS_CHANGED", map[string]interface{}{"id": id, "action": "APPROVE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
	}

	return c.JSON(fiber.Map{"success": true, "message": "Payment approved"})
}

func (h *Handlers) ReversePayment(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "معرف السند غير صالح"})
	}

	var req struct {
		Reason string `json:"reason"`
	}
	_ = c.BodyParser(&req)

	auditCtx := h.getAuditContext(c)
	if err := h.paymentService.ReversePayment(id, req.Reason, auditCtx); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if h.eventHub != nil {
		h.eventHub.Broadcast("PAYMENTS_CHANGED", map[string]interface{}{"id": id, "action": "REVERSE"})
		h.eventHub.Broadcast("INVOICES_CHANGED", nil)
		h.eventHub.Broadcast("CUSTOMERS_CHANGED", nil)
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم إلغاء وعكس سند القبض وإعادة ضبط الحسابات بنجاح",
	})
}

func (h *Handlers) SendPaymentWhatsApp(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid payment ID"})
	}

	var payment models.Payment
	if err := h.db.Preload("Customer").Preload("Invoice").First(&payment, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Payment not found"})
	}

	if payment.Customer == nil || payment.Customer.PhoneNumber == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Customer has no phone number"})
	}

	receiptNo := fmt.Sprintf("REC-%06d", payment.ID)
	if payment.ReceiptNumber != nil && *payment.ReceiptNumber != "" {
		receiptNo = *payment.ReceiptNumber
	}

	phone := services.NormalizeWhatsAppPhone(payment.Customer.PhoneNumber)
	now := time.Now().UTC()
	sourceEntity := "PAYMENT"
	msgType := "IMAGE"
	qMsg := models.WhatsAppQueueMessage{
		PhoneNumber:  phone,
		Type:         msgType,
		Message:      nil,
		Status:       "PENDING",
		SourceEntity: &sourceEntity,
		SourceID:     &payment.ID,
		ScheduledAt:  &now,
		CreatedAt:    &now,
		UpdatedAt:    &now,
	}

	if h.whatsappService != nil {
		_ = h.whatsappService.EnqueueMessage(&qMsg)
	}

	h.logAudit(c, "WHATSAPP_SEND_PAYMENT", "PAYMENT", strPtr(fmt.Sprintf("%d", payment.ID)), fmt.Sprintf("إدراج سند قبض رقم [%s] للمشترك [%s] في طابور الواتساب للإرسال", receiptNo, payment.Customer.FullName))

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم إدراج سند القبض في طابور الواتساب للإرسال الآمن فوراً بنجاح",
	})
}

// ---------------- WHATSAPP HANDLERS ----------------

func (h *Handlers) GetWhatsAppStatus(c *fiber.Ctx) error {
	status, qr := h.whatsappService.GetStatus()
	return c.JSON(fiber.Map{
		"success": true,
		"status":  status,
		"qr":      qr,
		"data": fiber.Map{
			"status": status,
			"qr":     qr,
		},
	})
}

func (h *Handlers) SendTestWhatsApp(c *fiber.Ctx) error {
	var req struct {
		To      string `json:"to"`
		Message string `json:"message"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}
	phone := services.NormalizeWhatsAppPhone(req.To)
	now := time.Now().UTC()
	msg := models.WhatsAppQueueMessage{
		PhoneNumber: phone,
		Type:        "TEXT",
		Message:     &req.Message,
		Status:      "PENDING",
		ScheduledAt: &now,
		CreatedAt:   &now,
		UpdatedAt:   &now,
	}
	h.db.Create(&msg)

	services.SafeGo("SendWhatsAppTestMessage", func() {
		_ = h.whatsappService.SendTextMessage(context.Background(), phone, req.Message)
	})

	return c.JSON(fiber.Map{"success": true, "message": "Test message queued"})
}

func (h *Handlers) RestartWhatsApp(c *fiber.Ctx) error {
	_ = h.whatsappService.RestartSession(c.Context())
	time.Sleep(300 * time.Millisecond)
	status, qr := h.whatsappService.GetStatus()

	return c.JSON(fiber.Map{
		"success": true,
		"message": "WhatsApp pairing channel refreshed",
		"status":  status,
		"qr":      qr,
		"data": fiber.Map{
			"status": status,
			"qr":     qr,
		},
	})
}

func (h *Handlers) LogoutWhatsApp(c *fiber.Ctx) error {
	_ = h.whatsappService.Logout(c.Context())
	time.Sleep(300 * time.Millisecond)
	status, qr := h.whatsappService.GetStatus()

	return c.JSON(fiber.Map{
		"success": true,
		"message": "WhatsApp logged out and fresh pairing channel started",
		"status":  status,
		"qr":      qr,
		"data": fiber.Map{
			"status": status,
			"qr":     qr,
		},
	})
}

func (h *Handlers) ConnectWhatsApp(c *fiber.Ctx) error {
	status, qr := h.whatsappService.GetStatus()
	return c.JSON(fiber.Map{
		"success": true,
		"message": "WhatsApp status retrieved",
		"status":  status,
		"qr":      qr,
		"data": fiber.Map{
			"status": status,
			"qr":     qr,
		},
	})
}

func (h *Handlers) SendInvoiceWhatsApp(c *fiber.Ctx) error {
	var req struct {
		InvoiceID int64 `json:"invoice_id"`
		ID        int64 `json:"id"`
	}
	_ = c.BodyParser(&req)

	invoiceID := req.InvoiceID
	if invoiceID == 0 {
		invoiceID = req.ID
	}
	if invoiceID == 0 {
		if idParam, err := strconv.ParseInt(c.Params("id"), 10, 64); err == nil {
			invoiceID = idParam
		}
	}

	if invoiceID == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invoice ID required"})
	}

	var inv models.Invoice
	if err := h.db.Preload("Customer").Preload("MeterReading").First(&inv, invoiceID).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Invoice not found"})
	}

	if inv.Customer == nil || inv.Customer.PhoneNumber == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Customer has no phone number"})
	}

	invNo := fmt.Sprintf("INV-%06d", inv.ID)
	if inv.InvoiceNumber != nil && *inv.InvoiceNumber != "" {
		invNo = *inv.InvoiceNumber
	}

	phone := services.NormalizeWhatsAppPhone(inv.Customer.PhoneNumber)
	now := time.Now().UTC()
	sourceEntity := "INVOICE"
	msgType := "IMAGE"
	qMsg := models.WhatsAppQueueMessage{
		PhoneNumber:  phone,
		Type:         msgType,
		Message:      nil,
		Status:       "PENDING",
		SourceEntity: &sourceEntity,
		SourceID:     &inv.ID,
		ScheduledAt:  &now,
		CreatedAt:    &now,
		UpdatedAt:    &now,
	}

	if h.whatsappService != nil {
		_ = h.whatsappService.EnqueueMessage(&qMsg)
	}

	h.logAudit(c, "WHATSAPP_SEND_INVOICE", "INVOICE", strPtr(fmt.Sprintf("%d", inv.ID)), fmt.Sprintf("إدراج فاتورة رقم [%s] للمشترك [%s] في طابور الواتساب للإرسال", invNo, inv.Customer.FullName))

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم إدراج الفاتورة في طابور الواتساب للإرسال الآمن فوراً بنجاح",
	})
}

func (h *Handlers) SendWarningWhatsApp(c *fiber.Ctx) error {
	var req struct {
		CustomerID int64   `json:"customer_id"`
		Amount     float64 `json:"amount"`
	}
	if err := c.BodyParser(&req); err != nil || req.CustomerID == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	var customer models.Customer
	if err := h.db.First(&customer, req.CustomerID).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Customer not found"})
	}

	if customer.PhoneNumber == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Customer has no phone number"})
	}

	var settings models.SystemSettings
	if err := h.db.First(&settings).Error; err != nil {
		settings = models.SystemSettings{
			StationName:  "محطة الضياء لتوليد الطاقة الكهربائية",
			StationPhone: strPtr("783270260 _ 736955883"),
		}
	}

	stationPhone := ""
	if settings.StationPhone != nil {
		stationPhone = *settings.StationPhone
	}

	amountDue := req.Amount
	if amountDue <= 0 {
		amountDue = customer.TotalDue
		if amountDue <= 0 {
			var latestInv models.Invoice
			if err := h.db.Where("customer_id = ? AND approval_status != 'REJECTED'", customer.ID).
				Order("id DESC").First(&latestInv).Error; err == nil && latestInv.RemainingAmount > 0 {
				amountDue = latestInv.RemainingAmount
			}
		}
	}

	msgText := fmt.Sprintf(
		"⚠️ *%s* ⚠️\n"+
			"🚨 *إشعار إنذار رسمي بفصل الخدمة*\n"+
			"────────────────────\n"+
			"👤 *المشترك:* %s\n"+
			"🔢 *رقم المشترك:* %s\n"+
			"💵 *إجمالي المديونية المتأخرة:* %.2f ر.ي\n"+
			"────────────────────\n"+
			"نرجو منكم المبادرة بسداد المبلغ المتبقي خلال 24 ساعة لتجنب فصل التيار الكهربائي تلقائياً وتجنب رسوم إعادة الخدمة.\n"+
			"📞 للاستفسار أو السداد: %s",
		settings.StationName,
		customer.FullName,
		customer.SubscriberNumber,
		amountDue,
		stationPhone,
	)

	phone := services.NormalizeWhatsAppPhone(customer.PhoneNumber)
	now := time.Now().UTC()
	sourceEntity := "WARNING"
	qMsg := models.WhatsAppQueueMessage{
		PhoneNumber:  phone,
		Type:         "TEXT",
		Message:      &msgText,
		Status:       "PENDING",
		SourceEntity: &sourceEntity,
		SourceID:     &customer.ID,
		ScheduledAt:  &now,
		CreatedAt:    &now,
		UpdatedAt:    &now,
	}

	if h.whatsappService != nil {
		_ = h.whatsappService.EnqueueMessage(&qMsg)
	}

	h.logAudit(c, "WHATSAPP_SEND_WARNING", "CUSTOMER", strPtr(fmt.Sprintf("%d", customer.ID)), fmt.Sprintf("إدراج إنذار فصل للمشترك [%s] بمبلغ [%.2f] في طابور الواتساب", customer.FullName, amountDue))

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم إدراج إنذار الفصل في طابور الواتساب للإرسال الآمن بنجاح",
	})
}

func (h *Handlers) SendBulkWarningsWhatsApp(c *fiber.Ctx) error {
	var req struct {
		Items []struct {
			CustomerID int64   `json:"customer_id"`
			Amount     float64 `json:"amount"`
		} `json:"items"`
	}
	if err := c.BodyParser(&req); err != nil || len(req.Items) == 0 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "No items provided"})
	}

	var settings models.SystemSettings
	if err := h.db.First(&settings).Error; err != nil {
		settings = models.SystemSettings{
			StationName:  "محطة الضياء لتوليد الطاقة الكهربائية",
			StationPhone: strPtr("783270260 _ 736955883"),
		}
	}

	stationPhone := ""
	if settings.StationPhone != nil {
		stationPhone = *settings.StationPhone
	}

	queuedCount := 0
	now := time.Now().UTC()

	for _, item := range req.Items {
		var customer models.Customer
		if err := h.db.First(&customer, item.CustomerID).Error; err != nil || customer.PhoneNumber == "" {
			continue
		}

		amountDue := item.Amount
		if amountDue <= 0 {
			amountDue = customer.TotalDue
			if amountDue <= 0 {
				var latestInv models.Invoice
				if err := h.db.Where("customer_id = ? AND approval_status != 'REJECTED'", customer.ID).
					Order("id DESC").First(&latestInv).Error; err == nil && latestInv.RemainingAmount > 0 {
					amountDue = latestInv.RemainingAmount
				}
			}
		}

		msgText := fmt.Sprintf(
			"⚠️ *%s* ⚠️\n"+
				"🚨 *إشعار إنذار رسمي بفصل الخدمة*\n"+
				"────────────────────\n"+
				"👤 *المشترك:* %s\n"+
				"🔢 *رقم المشترك:* %s\n"+
				"💵 *إجمالي المديونية المتأخرة:* %.2f ر.ي\n"+
				"────────────────────\n"+
				"نرجو منكم المبادرة بسداد المبلغ المتبقي خلال 24 ساعة لتجنب فصل التيار الكهربائي تلقائياً وتجنب رسوم إعادة الخدمة.\n"+
				"📞 للاستفسار أو السداد: %s",
			settings.StationName,
			customer.FullName,
			customer.SubscriberNumber,
			amountDue,
			stationPhone,
		)

		phone := services.NormalizeWhatsAppPhone(customer.PhoneNumber)
		sourceEntity := "WARNING"
		qMsg := models.WhatsAppQueueMessage{
			PhoneNumber:  phone,
			Type:         "TEXT",
			Message:      &msgText,
			Status:       "PENDING",
			SourceEntity: &sourceEntity,
			SourceID:     &customer.ID,
			ScheduledAt:  &now,
			CreatedAt:    &now,
			UpdatedAt:    &now,
		}
		if err := h.db.Create(&qMsg).Error; err == nil {
			queuedCount++
		}
	}

	if h.whatsappService != nil {
		h.whatsappService.TriggerWakeWorker()
	}
	if h.eventHub != nil {
		h.eventHub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{"action": "BULK_QUEUED", "count": queuedCount})
	}

	h.logAudit(c, "WHATSAPP_SEND_BULK_WARNINGS", "WHATSAPP", nil, fmt.Sprintf("تم إدراج %d إشعار إنذار فصل في طابور الواتساب الآمن", queuedCount))

	return c.JSON(fiber.Map{
		"success": true,
		"message": fmt.Sprintf("تم إدراج %d إشعار إنذار في طابور الإرسال بنجاح", queuedCount),
		"count":   queuedCount,
	})
}

// ---------------- ANALYTICS HANDLERS ----------------

func (h *Handlers) GetMonthlyPerformance(c *fiber.Ctx) error {
	type MonthlyPerf struct {
		Month               string  `json:"month"`
		BillingCycle        string  `json:"billing_cycle"`
		TotalBilled         float64 `json:"total_billed"`
		TotalCollected      float64 `json:"total_collected"`
		TotalRemaining      float64 `json:"total_remaining"`
		CollectionRate      float64 `json:"collection_rate"`
		TotalBilledCamel    float64 `json:"totalBilled"`
		TotalCollectedCamel float64 `json:"totalCollected"`
		TotalRemainingCamel float64 `json:"totalRemaining"`
		CollectionRateCamel float64 `json:"collectionRate"`
		InvoiceCount        int64   `json:"invoice_count"`
		SortIndex           int     `json:"sort_index"`
	}

	var rows []struct {
		Cycle          string  `gorm:"column:cycle"`
		TotalBilled    float64 `gorm:"column:total_billed"`
		TotalCollected float64 `gorm:"column:total_collected"`
		TotalRemaining float64 `gorm:"column:total_remaining"`
		InvoiceCount   int64   `gorm:"column:invoice_count"`
	}

	h.db.Raw(`
		SELECT
			COALESCE(billing_cycle, 'Unknown') as cycle,
			COALESCE(SUM(total_due), 0) as total_billed,
			COALESCE(SUM(paid_amount), 0) as total_collected,
			COALESCE(SUM(remaining_amount), 0) as total_remaining,
			COUNT(id) as invoice_count
		FROM invoices
		GROUP BY billing_cycle
	`).Scan(&rows)

	// Strictly deduplicate and merge by SortIndex
	mergedMap := make(map[int]*MonthlyPerf)
	for _, r := range rows {
		sortIdx := services.GetCycleSortIndex(r.Cycle)
		if existing, exists := mergedMap[sortIdx]; exists {
			existing.TotalBilled += r.TotalBilled
			existing.TotalCollected += r.TotalCollected
			existing.TotalRemaining += r.TotalRemaining
			existing.InvoiceCount += r.InvoiceCount
		} else {
			canonicalName := services.FormatCanonicalCycle(r.Cycle)
			mergedMap[sortIdx] = &MonthlyPerf{
				Month:          canonicalName,
				BillingCycle:   canonicalName,
				TotalBilled:    r.TotalBilled,
				TotalCollected: r.TotalCollected,
				TotalRemaining: r.TotalRemaining,
				InvoiceCount:   r.InvoiceCount,
				SortIndex:      sortIdx,
			}
		}
	}

	results := []MonthlyPerf{}
	for _, item := range mergedMap {
		var rate float64
		if item.TotalBilled > 0 {
			rate = (item.TotalCollected / item.TotalBilled) * 100
			if rate > 100 {
				rate = 100
			}
		}
		item.CollectionRate = float64(int(rate*100)) / 100.0
		item.TotalBilledCamel = item.TotalBilled
		item.TotalCollectedCamel = item.TotalCollected
		item.TotalRemainingCamel = item.TotalRemaining
		item.CollectionRateCamel = item.CollectionRate
		results = append(results, *item)
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].SortIndex < results[j].SortIndex
	})

	return c.JSON(fiber.Map{"success": true, "data": results})
}

func (h *Handlers) GetDashboardSummary(c *fiber.Ctx) error {
	var totalCustomers int64
	var totalInvoices int64
	var totalBilled float64
	var totalCollected float64
	var totalArrears float64

	h.db.Model(&models.Customer{}).Where("is_deleted = false").Count(&totalCustomers)
	h.db.Model(&models.Invoice{}).Count(&totalInvoices)
	h.db.Model(&models.Invoice{}).Where("approval_status != 'REJECTED'").Select("COALESCE(SUM(total_amount), 0)").Scan(&totalBilled)
	h.db.Model(&models.Invoice{}).Where("approval_status != 'REJECTED'").Select("COALESCE(SUM(paid_amount), 0)").Scan(&totalCollected)
	h.db.Model(&models.Customer{}).Where("is_deleted = false AND total_due > 0").Select("COALESCE(SUM(total_due), 0)").Scan(&totalArrears)
	if totalArrears == 0 {
		h.db.Raw(`
			SELECT COALESCE(SUM(latest_due), 0) FROM (
				SELECT DISTINCT ON (customer_id) remaining_amount as latest_due
				FROM invoices
				WHERE approval_status != 'REJECTED' AND remaining_amount > 0
				ORDER BY customer_id, id DESC
			) sub
		`).Scan(&totalArrears)
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data": fiber.Map{
			"total_customers": totalCustomers,
			"total_invoices":  totalInvoices,
			"total_billed":    totalBilled,
			"total_collected": totalCollected,
			"total_arrears":   totalArrears,
		},
	})
}

func (h *Handlers) GetRoutesProgress(c *fiber.Ctx) error {
	type RouteProgress struct {
		Route       string  `json:"route"`
		TotalCount  int64   `json:"total_count"`
		ReadCount   int64   `json:"read_count"`
		ProgressPct float64 `json:"progress_pct"`
	}
	var results []RouteProgress
	h.db.Raw(`
		SELECT
			COALESCE(c.route_number, 'Unknown') as route,
			COUNT(c.id) as total_count,
			COUNT(mr.id) as read_count,
			CASE WHEN COUNT(c.id) > 0 THEN ROUND((COUNT(mr.id)::float / COUNT(c.id)::float * 100)::numeric, 1) ELSE 0 END as progress_pct
		FROM customers c
		LEFT JOIN meter_readings mr ON mr.customer_id = c.id
		WHERE c.is_deleted = false
		GROUP BY c.route_number
		ORDER BY c.route_number ASC
	`).Scan(&results)

	return c.JSON(fiber.Map{"success": true, "data": results})
}

func (h *Handlers) GetOverdueReport(c *fiber.Ctx) error {
	cycle := c.Query("cycle", "")
	status := c.Query("status", "")
	route := c.Query("route", "")
	region := c.Query("region", "")
	search := c.Query("search", "")
	category := c.Query("category", "")

	filter := services.InvoiceFilter{
		BillingCycle: cycle,
		Status:       status,
		RouteNumber:  route,
		Region:       region,
		Search:       search,
		Limit:        1000,
	}

	invoices, _, err := h.billingService.ListInvoices(filter)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	var overdue []models.Invoice
	for _, inv := range invoices {
		if category == "debtors_only" && inv.RemainingAmount <= 0 {
			continue
		}
		overdue = append(overdue, inv)
	}

	return c.JSON(fiber.Map{"success": true, "data": overdue, "total": len(overdue)})
}

// ---------------- USER & AUDIT HANDLERS ----------------

func (h *Handlers) GetUsers(c *fiber.Ctx) error {
	var users []models.User
	h.db.Find(&users)
	return c.JSON(fiber.Map{"success": true, "data": users})
}

func (h *Handlers) CreateUser(c *fiber.Ctx) error {
	var req struct {
		Username    string  `json:"username"`
		Password    string  `json:"password"`
		FullName    string  `json:"full_name"`
		Role        string  `json:"role"`
		PhoneNumber *string `json:"phone_number"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}
	hashedPwd, _ := h.authService.HashPassword(req.Password)
	user := models.User{
		Username:     req.Username,
		PasswordHash: hashedPwd,
		FullName:     req.FullName,
		Role:         req.Role,
		PhoneNumber:  req.PhoneNumber,
		IsActive:     true,
	}
	if err := h.db.Create(&user).Error; err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	h.logAudit(c, "CREATE_USER", "USER", strPtr(fmt.Sprintf("%d", user.ID)), fmt.Sprintf("إضافة مستخدم نظام جديد [%s] برتبة [%s]", user.FullName, user.Role))

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{"success": true, "data": user})
}

func (h *Handlers) UpdateUser(c *fiber.Ctx) error {
	id, _ := strconv.ParseInt(c.Params("id"), 10, 64)
	var updates map[string]interface{}
	if err := c.BodyParser(&updates); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}
	delete(updates, "id")
	delete(updates, "password_hash")
	h.db.Model(&models.User{}).Where("id = ?", id).Updates(updates)
	var user models.User
	h.db.First(&user, id)

	h.logAudit(c, "UPDATE_USER", "USER", strPtr(fmt.Sprintf("%d", id)), fmt.Sprintf("تعديل بيانات وصلاحيات المستخدم [%s]", user.FullName))

	return c.JSON(fiber.Map{"success": true, "data": user})
}

func (h *Handlers) ResetUserPassword(c *fiber.Ctx) error {
	id, _ := strconv.ParseInt(c.Params("id"), 10, 64)
	var req struct {
		NewPassword string `json:"new_password"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}
	hashedPwd, _ := h.authService.HashPassword(req.NewPassword)
	h.db.Model(&models.User{}).Where("id = ?", id).Update("password_hash", hashedPwd)

	h.logAudit(c, "RESET_PASSWORD", "USER", strPtr(fmt.Sprintf("%d", id)), fmt.Sprintf("إعادة تعيين كلمة المرور للمستخدم رقم [%d]", id))

	return c.JSON(fiber.Map{"success": true, "message": "Password reset successfully"})
}

// ---------------- ENHANCED AUDIT & ACTIVITY LOGS ----------------

func (h *Handlers) GetAuditLogs(c *fiber.Ctx) error {
	var logs []models.AuditLog
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "50"))
	action := c.Query("action", "all")
	search := c.Query("search", "")
	userID := c.Query("user_id", "all")

	query := h.db.Model(&models.AuditLog{})

	if action != "all" && action != "" {
		query = query.Where("action = ?", action)
	}

	if userID != "all" && userID != "" {
		uid, err := strconv.ParseInt(userID, 10, 64)
		if err == nil && uid > 0 {
			query = query.Where("user_id = ?", uid)
		}
	}

	if search != "" {
		searchTerm := "%" + search + "%"
		query = query.Where("entity ILIKE ? OR details ILIKE ? OR action ILIKE ? OR entity_id ILIKE ?",
			searchTerm, searchTerm, searchTerm, searchTerm)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if limit <= 0 {
		limit = 50
	}
	offset := (page - 1) * limit
	if offset < 0 {
		offset = 0
	}

	err := query.Preload("User").
		Order("created_at DESC, id DESC").
		Limit(limit).
		Offset(offset).
		Find(&logs).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	totalPages := int((total + int64(limit) - 1) / int64(limit))
	if totalPages < 1 {
		totalPages = 1
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data":    logs,
		"total":   total,
		"meta": fiber.Map{
			"total":      total,
			"page":       page,
			"limit":      limit,
			"totalPages": totalPages,
		},
	})
}

func (h *Handlers) LogActivity(c *fiber.Ctx) error {
	var req struct {
		Action   string  `json:"action"`
		Entity   string  `json:"entity"`
		EntityID *string `json:"entity_id"`
		Details  *string `json:"details"`
	}
	if err := c.BodyParser(&req); err != nil || req.Action == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid request"})
	}

	var userID *int64
	if claims, ok := c.Locals("user").(*services.JWTClaims); ok && claims != nil {
		userID = &claims.UserID
	}

	now := time.Now().UTC()
	logEntry := models.AuditLog{
		UserID:    userID,
		Action:    req.Action,
		Entity:    req.Entity,
		EntityID:  req.EntityID,
		Details:   req.Details,
		CreatedAt: &now,
	}

	if err := h.db.Create(&logEntry).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	return c.Status(fiber.StatusCreated).JSON(fiber.Map{"success": true, "data": logEntry})
}

// ---------------- WHATSAPP MESSAGE STREAM ----------------

func (h *Handlers) GetWhatsAppMessages(c *fiber.Ctx) error {
	var messages []models.WhatsAppQueueMessage
	page, _ := strconv.Atoi(c.Query("page", "1"))
	limit, _ := strconv.Atoi(c.Query("limit", "50"))
	msgType := c.Query("type", "all")
	status := c.Query("status", "all")
	search := c.Query("search", "")

	query := h.db.Model(&models.WhatsAppQueueMessage{})

	if msgType == "RECEIPT" || msgType == "PAYMENT" {
		query = query.Where("type IN ('RECEIPT', 'PAYMENT')")
	} else if msgType == "WARNING" || msgType == "DISCONNECTION" {
		query = query.Where("type IN ('WARNING', 'DISCONNECTION')")
	} else if msgType == "CUSTOM" || msgType == "TEXT" {
		query = query.Where("type IN ('CUSTOM', 'TEXT', 'NOTIFICATION')")
	} else if msgType != "all" && msgType != "" {
		query = query.Where("type = ?", msgType)
	}

	if status == "queue" {
		query = query.Where("status IN ('PENDING', 'QUEUED', 'FAILED')")
	} else if status == "sent" {
		query = query.Where("status IN ('SENT', 'DELIVERED')")
	} else if status != "all" && status != "" {
		query = query.Where("status = ?", status)
	}

	if search != "" {
		searchTerm := "%" + search + "%"
		query = query.Where("phone_number ILIKE ? OR message ILIKE ? OR source_entity ILIKE ?",
			searchTerm, searchTerm, searchTerm)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	if limit <= 0 {
		limit = 50
	}
	offset := (page - 1) * limit
	if offset < 0 {
		offset = 0
	}

	err := query.Order("created_at DESC, id DESC").
		Limit(limit).
		Offset(offset).
		Find(&messages).Error

	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}

	totalPages := int((total + int64(limit) - 1) / int64(limit))
	if totalPages < 1 {
		totalPages = 1
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data":    messages,
		"total":   total,
		"meta": fiber.Map{
			"total":      total,
			"page":       page,
			"limit":      limit,
			"totalPages": totalPages,
		},
	})
}

func (h *Handlers) ClearPendingWhatsAppQueue(c *fiber.Ctx) error {
	result := h.db.Exec("DELETE FROM whatsapp_queue_messages WHERE status IN ('PENDING', 'QUEUED', 'FAILED')")
	if result.Error != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": result.Error.Error(),
		})
	}
	deletedCount := result.RowsAffected
	h.logAudit(c, "WHATSAPP_CANCEL_QUEUE", "WHATSAPP", nil, fmt.Sprintf("تم إلغاء وتفريغ %d رسالة معلقة من طابور الواتساب بنجاح", deletedCount))
	return c.JSON(fiber.Map{
		"success": true,
		"message": fmt.Sprintf("تم إلغاء %d رسالة من الطابور بنجاح", deletedCount),
		"deleted": deletedCount,
	})
}

func (h *Handlers) DeleteWhatsAppMessage(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	if err := h.db.Delete(&models.WhatsAppQueueMessage{}, id).Error; err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": err.Error()})
	}
	h.logAudit(c, "WHATSAPP_DELETE_MESSAGE", "WHATSAPP", strPtr(fmt.Sprintf("%d", id)), fmt.Sprintf("تم حذف رسالة الواتساب رقم [%d]", id))
	return c.JSON(fiber.Map{"success": true, "message": "تم حذف الرسالة بنجاح"})
}

func (h *Handlers) RetryWhatsAppMessage(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{"success": false, "message": "Invalid ID"})
	}
	var msg models.WhatsAppQueueMessage
	if err := h.db.First(&msg, id).Error; err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{"success": false, "message": "Message not found"})
	}
	now := time.Now().UTC()
	h.db.Model(&msg).Updates(map[string]interface{}{
		"status":       "PENDING",
		"retries":      0,
		"scheduled_at": now,
		"updated_at":   now,
	})

	if h.whatsappService != nil {
		h.whatsappService.TriggerWakeWorker()
	}
	if h.eventHub != nil {
		h.eventHub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{
			"id":     id,
			"status": "PENDING",
		})
	}

	h.logAudit(c, "WHATSAPP_RETRY_MESSAGE", "WHATSAPP", strPtr(fmt.Sprintf("%d", id)), fmt.Sprintf("إعادة محاولة إرسال رسالة الواتساب رقم [%d]", id))
	return c.JSON(fiber.Map{"success": true, "message": "تمت إعادة إدراج الرسالة في طابور الإرسال الفوري"})
}

func (h *Handlers) RetryAllWhatsAppQueue(c *fiber.Ctx) error {
	now := time.Now().UTC()
	result := h.db.Model(&models.WhatsAppQueueMessage{}).
		Where("status IN ('FAILED', 'PENDING', 'QUEUED')").
		Updates(map[string]interface{}{
			"status":       "PENDING",
			"retries":      0,
			"scheduled_at": now,
			"updated_at":   now,
		})

	count := result.RowsAffected
	if count == 0 {
		return c.JSON(fiber.Map{
			"success": true,
			"message": "لا توجد رسائل معلقة أو فاشلة في الطابور",
			"count":   0,
		})
	}

	if h.whatsappService != nil {
		h.whatsappService.TriggerWakeWorker()
	}
	if h.eventHub != nil {
		h.eventHub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{
			"action": "RETRY_ALL",
			"count":  count,
		})
	}

	h.logAudit(c, "WHATSAPP_RETRY_ALL", "WHATSAPP", nil, fmt.Sprintf("إعادة محاولة إرسال شاملة لـ %d رسالة معلقة في طابور الواتساب", count))
	return c.JSON(fiber.Map{
		"success": true,
		"message": fmt.Sprintf("تمت إعادة محاولة إرسال %d رسالة بنجاح عبر طابور الإرسال الآمن", count),
		"count":   count,
	})
}

func (h *Handlers) ClearAllWhatsAppMessages(c *fiber.Ctx) error {
	result := h.db.Exec("DELETE FROM whatsapp_queue_messages")
	if result.Error != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"success": false, "message": result.Error.Error()})
	}
	deletedCount := result.RowsAffected
	h.logAudit(c, "WHATSAPP_CLEAR_ALL", "WHATSAPP", nil, fmt.Sprintf("تم تفريغ وتصفير سجل رسائل الواتساب بالكامل (%d رسالة)", deletedCount))
	return c.JSON(fiber.Map{
		"success": true,
		"message": fmt.Sprintf("تم تصفير وحذف %d رسالة بنجاح", deletedCount),
		"deleted": deletedCount,
	})
}

func (h *Handlers) getAuditContext(c *fiber.Ctx) models.AuditContext {
	var ctx models.AuditContext
	ctx.IPAddress = c.IP()
	if claims, ok := c.Locals("user").(*services.JWTClaims); ok && claims != nil {
		ctx.UserID = &claims.UserID
		ctx.Username = claims.Username
		ctx.FullName = claims.FullName
		ctx.Role = claims.Role
	}
	return ctx
}

func (h *Handlers) logAudit(c *fiber.Ctx, action, entity string, entityID *string, details string) {
	var userID *int64
	if claims, ok := c.Locals("user").(*services.JWTClaims); ok && claims != nil {
		userID = &claims.UserID
	}
	ip := c.IP()
	now := time.Now().UTC()
	_ = h.db.Create(&models.AuditLog{
		UserID:    userID,
		Action:    action,
		Entity:    entity,
		EntityID:  entityID,
		Details:   &details,
		IPAddress: &ip,
		CreatedAt: &now,
	}).Error
}

func strPtr(s string) *string {
	return &s
}

// ---------------- LICENSING HANDLERS ----------------

func (h *Handlers) GetLicenseStatus(c *fiber.Ctx) error {
	mgr := licensing.GetLicenseManager()
	status := mgr.TriggerSync()
	return c.JSON(fiber.Map{
		"success": true,
		"data":    status,
	})
}

func (h *Handlers) GetMachineHWID(c *fiber.Ctx) error {
	hwid := licensing.GetMachineHWID()
	return c.JSON(fiber.Map{
		"success": true,
		"hwid":    hwid,
	})
}

func (h *Handlers) ActivateLicense(c *fiber.Ctx) error {
	var req struct {
		LicenseKey string `json:"license_key"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "بيانات غير صالحة",
		})
	}

	mgr := licensing.GetLicenseManager()
	status, err := mgr.Activate(req.LicenseKey)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": err.Error(),
			"data":    status,
		})
	}

	h.logAudit(c, "LICENSE_ACTIVATE", "LICENSE", nil, fmt.Sprintf("تفعيل ترخيص جديد بنجاح: %s للعميل: %s", status.LicenseKey, status.ClientName))

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم تفعيل الترخيص بنجاح",
		"data":    status,
	})
}

func (h *Handlers) ActivateEmergencyCode(c *fiber.Ctx) error {
	var req struct {
		EmergencyCode string `json:"emergency_code"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "بيانات غير صالحة",
		})
	}

	mgr := licensing.GetLicenseManager()
	status, err := mgr.ActivateOfflineCode(req.EmergencyCode)
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": err.Error(),
			"data":    status,
		})
	}

	h.logAudit(c, "LICENSE_EMERGENCY_UNLOCK", "LICENSE", nil, fmt.Sprintf("تفعيل كود طوارئ أوفلاين: %s", req.EmergencyCode))

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم تفعيل كود الطوارئ وتمديد الاشتراك بنجاح",
		"data":    status,
	})
}

// GetNetworkInfo returns the local machine's LAN IP address, adapters, and URL for mobile QR connect
func (h *Handlers) GetNetworkInfo(c *fiber.Ctx) error {
	adapters, primaryIP := getAvailableNetworkAdapters()
	port := "3000"
	mobileURL := fmt.Sprintf("http://%s:%s", primaryIP, port)

	return c.JSON(fiber.Map{
		"success":    true,
		"local_ip":   primaryIP,
		"port":       port,
		"mobile_url": mobileURL,
		"adapters":   adapters,
	})
}

func getAvailableNetworkAdapters() ([]map[string]string, string) {
	var adapters []map[string]string
	seenIPs := make(map[string]bool)

	// 1. Detect primary outbound IP using UDP route
	primaryOutboundIP := ""
	if conn, err := net.DialTimeout("udp", "8.8.8.8:80", 200*time.Millisecond); err == nil {
		if udpAddr, ok := conn.LocalAddr().(*net.UDPAddr); ok && udpAddr.IP != nil {
			primaryOutboundIP = udpAddr.IP.String()
		}
		_ = conn.Close()
	}

	// 2. Iterate network interfaces
	ifaces, err := net.Interfaces()
	if err == nil {
		for _, iface := range ifaces {
			// Skip down or loopback interfaces
			if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
				continue
			}

			nameLower := strings.ToLower(iface.Name)
			// Skip virtual/hypervisor/VPN adapters
			if strings.Contains(nameLower, "vmware") ||
				strings.Contains(nameLower, "vethernet") ||
				strings.Contains(nameLower, "virtual") ||
				strings.Contains(nameLower, "hyper-v") ||
				strings.Contains(nameLower, "docker") ||
				strings.Contains(nameLower, "wsl") ||
				strings.Contains(nameLower, "bluetooth") ||
				strings.Contains(nameLower, "pseudo") ||
				strings.Contains(nameLower, "npcap") ||
				strings.Contains(nameLower, "tap") ||
				strings.Contains(nameLower, "tun") ||
				strings.Contains(nameLower, "tailscale") ||
				strings.Contains(nameLower, "zerotier") {
				continue
			}

			addrs, err := iface.Addrs()
			if err != nil {
				continue
			}

			for _, addr := range addrs {
				ipnet, ok := addr.(*net.IPNet)
				if !ok || ipnet.IP.IsLoopback() {
					continue
				}
				ip4 := ipnet.IP.To4()
				if ip4 == nil {
					continue
				}
				ipStr := ip4.String()
				// Skip APIPA (169.254.x.x)
				if strings.HasPrefix(ipStr, "169.254.") {
					continue
				}

				if seenIPs[ipStr] {
					continue
				}
				seenIPs[ipStr] = true

				friendlyName := iface.Name
				adapterType := "other"

				if ipStr == "192.168.137.1" || strings.Contains(nameLower, "hotspot") || strings.Contains(nameLower, "local* 2") || strings.Contains(nameLower, "اتصال محلي* 2") {
					friendlyName = "نقطة اتصال اللابتوب (Mobile Hotspot)"
					adapterType = "hotspot"
				} else if strings.Contains(nameLower, "wi-fi") || strings.Contains(nameLower, "wifi") || strings.Contains(nameLower, "wlan") || strings.Contains(nameLower, "واي") {
					friendlyName = "شبكة الواي فاي (Wi-Fi LAN)"
					adapterType = "wifi"
				} else if strings.Contains(nameLower, "ethernet") || strings.Contains(nameLower, "إيثرنت") || strings.Contains(nameLower, "ايثرنت") {
					friendlyName = "كابل الشبكة (Ethernet LAN)"
					adapterType = "ethernet"
				} else {
					friendlyName = fmt.Sprintf("شبكة محلية (%s)", iface.Name)
				}

				adapters = append(adapters, map[string]string{
					"ip":   ipStr,
					"name": friendlyName,
					"type": adapterType,
				})
			}
		}
	}

	// Determine selected primary IP
	selectedIP := ""
	if primaryOutboundIP != "" && seenIPs[primaryOutboundIP] {
		selectedIP = primaryOutboundIP
	} else if len(adapters) > 0 {
		for _, a := range adapters {
			if a["type"] == "hotspot" || a["type"] == "wifi" {
				selectedIP = a["ip"]
				break
			}
		}
		if selectedIP == "" {
			selectedIP = adapters[0]["ip"]
		}
	} else {
		selectedIP = "127.0.0.1"
		adapters = append(adapters, map[string]string{
			"ip":   "127.0.0.1",
			"name": "محلي (Localhost)",
			"type": "local",
		})
	}

	return adapters, selectedIP
}

// ---------------- UPDATE SERVICE HANDLERS ----------------

// CheckUpdates checks remote manifest for newer version
func (h *Handlers) CheckUpdates(c *fiber.Ctx) error {
	if h.updateService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التحديث غير متوفرة",
		})
	}

	resp, err := h.updateService.CheckForUpdates()
	if err != nil {
		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"has_update":      false,
			"current_version": h.updateService.GetCurrentVersion(),
			"latest_version":  h.updateService.GetCurrentVersion(),
			"download_url":    "",
			"changelog":       "",
			"mandatory":       false,
			"error":           err.Error(),
		})
	}

	return c.JSON(resp)
}

// GetUpdateStatus returns the current download/installation state
func (h *Handlers) GetUpdateStatus(c *fiber.Ctx) error {
	if h.updateService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التحديث غير متوفرة",
		})
	}

	progress := h.updateService.GetProgress()
	return c.JSON(progress)
}

// DownloadUpdate initiates async download of update package with SHA256 integrity
func (h *Handlers) DownloadUpdate(c *fiber.Ctx) error {
	if h.updateService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التحديث غير متوفرة",
		})
	}

	var req struct {
		DownloadURL string `json:"download_url"`
		SHA256      string `json:"sha256"`
	}
	_ = c.BodyParser(&req)

	if req.DownloadURL != "" && !strings.HasPrefix(strings.ToLower(req.DownloadURL), "https://") {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "يجب أن يكون رابط التحديث عبر بروتوكول آمن مشفر (HTTPS)",
		})
	}

	h.updateService.StartAsyncDownload(req.DownloadURL, req.SHA256)

	return c.JSON(fiber.Map{
		"success": true,
		"message": "بدأ تحميل حزمة التحديث بأمان...",
	})
}

// ApplyUpdate initiates safe hot-swap replacement and app restart
func (h *Handlers) ApplyUpdate(c *fiber.Ctx) error {
	if h.updateService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التحديث غير متوفرة",
		})
	}

	var req struct {
		FilePath string `json:"file_path"`
	}
	_ = c.BodyParser(&req)

	if err := h.updateService.ApplyUpdate(req.FilePath); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": fmt.Sprintf("فشل تطبيق التحديث: %v", err),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "جاري استبدال البرنامج وإعادة التشغيل تلقائياً...",
	})
}

// UpdateUI downloads and atomically applies the custom UI bundle
func (h *Handlers) UpdateUI(c *fiber.Ctx) error {
	if h.updateService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التحديث غير متوفرة",
		})
	}

	var req struct {
		DownloadURL string `json:"download_url"`
		SHA256      string `json:"sha256"`
	}
	if err := c.BodyParser(&req); err != nil || req.DownloadURL == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"success": false,
			"message": "رابط تحميل حزمة الواجهة غير صالح",
		})
	}

	if err := h.updateService.DownloadAndApplyUIUpdate(c.Context(), req.DownloadURL, req.SHA256); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": fmt.Sprintf("فشل تحديث حزمة الواجهة: %v", err),
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "تم تحديث حزمة الواجهة وتطبيقها بنجاح",
	})
}

// ---------------- DIAGNOSTICS & SUPPORT HANDLERS ----------------

func (h *Handlers) UploadDiagnostics(c *fiber.Ctx) error {
	if h.diagnosticsService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التشخيص الفني غير مفعلة",
		})
	}

	var req struct {
		UserNote string `json:"user_note"`
	}
	_ = c.BodyParser(&req)

	res, err := h.diagnosticsService.UploadToCloud(req.UserNote)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": fmt.Sprintf("فشل رفع تقرير الدعم الفني: %v", err),
		})
	}

	return c.JSON(res)
}

func (h *Handlers) ExportDiagnostics(c *fiber.Ctx) error {
	if h.diagnosticsService == nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"success": false,
			"message": "خدمة التشخيص الفني غير مفعلة",
		})
	}

	var req struct {
		UserNote string `json:"user_note"`
	}
	_ = c.BodyParser(&req)

	path, zipData, err := h.diagnosticsService.ExportToDesktop(req.UserNote)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"success": false,
			"message": fmt.Sprintf("فشل تصدير السجلات لسطح المكتب: %v", err),
		})
	}

	// Set headers for direct browser download
	fileName := filepath.Base(path)
	c.Set("Content-Type", "application/zip")
	c.Set("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", fileName))
	c.Set("X-File-Path", path)
	c.Set("Access-Control-Expose-Headers", "X-File-Path, Content-Disposition")

	return c.Send(zipData)
}