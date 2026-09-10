package services

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strings"
	"sync"
	"time"

	"smartpower/internal/config"
	"smartpower/internal/models"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/skip2/go-qrcode"
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
	"gorm.io/gorm"
)

type WhatsAppService struct {
	db            *gorm.DB
	cfg           *config.Config
	client        *whatsmeow.Client
	container     *sqlstore.Container
	deviceStore   *store.Device
	renderService *InvoiceRenderService
	eventHub      *EventHub
	wakeChan      chan struct{}
	mu            sync.RWMutex
	reconnectMu   sync.Mutex
	currentQR     string
	status        string // "CONNECTED", "CONNECTING", "RECONNECTING", "SCAN_QR_CODE", "DISCONNECTED"
	ctx           context.Context
	cancel        context.CancelFunc
}

func NewWhatsAppService(db *gorm.DB, cfg *config.Config, renderService *InvoiceRenderService) (*WhatsAppService, error) {
	ctx, cancel := context.WithCancel(context.Background())

	sqlDB, err := db.DB()
	if err != nil {
		cancel()
		return nil, fmt.Errorf("failed to retrieve underlying sql.DB: %w", err)
	}

	waLogger := waLog.Stdout("WhatsApp", "INFO", true)
	container := sqlstore.NewWithDB(sqlDB, "postgres", waLogger)

	err = container.Upgrade(ctx)
	if err != nil {
		log.Printf("Warning during whatsmeow container schema upgrade: %v", err)
	}

	deviceStore, err := container.GetFirstDevice(ctx)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("failed to get whatsmeow first device: %w", err)
	}

	client := whatsmeow.NewClient(deviceStore, waLogger)

	svc := &WhatsAppService{
		db:            db,
		cfg:           cfg,
		client:        client,
		container:     container,
		deviceStore:   deviceStore,
		renderService: renderService,
		wakeChan:      make(chan struct{}, 10),
		status:        "CONNECTING",
		ctx:           ctx,
		cancel:        cancel,
	}

	client.AddEventHandler(svc.handleEvent)

	return svc, nil
}

func (s *WhatsAppService) SetEventHub(eh *EventHub) {
	s.mu.Lock()
	s.eventHub = eh
	s.mu.Unlock()
}

func (s *WhatsAppService) TriggerWakeWorker() {
	select {
	case s.wakeChan <- struct{}{}:
	default:
	}
}

func (s *WhatsAppService) EnqueueMessage(qMsg *models.WhatsAppQueueMessage) error {
	now := time.Now().UTC()
	if qMsg.CreatedAt == nil {
		qMsg.CreatedAt = &now
	}
	if qMsg.UpdatedAt == nil {
		qMsg.UpdatedAt = &now
	}
	if qMsg.Status == "" {
		qMsg.Status = "PENDING"
	}
	if qMsg.ScheduledAt == nil {
		qMsg.ScheduledAt = &now
	}

	if err := s.db.Create(qMsg).Error; err != nil {
		return err
	}

	s.TriggerWakeWorker()

	s.mu.RLock()
	hub := s.eventHub
	s.mu.RUnlock()
	if hub != nil {
		hub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{
			"id":     qMsg.ID,
			"status": qMsg.Status,
		})
	}

	return nil
}

func (s *WhatsAppService) Start() {
	if s.client == nil {
		return
	}

	if s.client.Store.ID == nil {
		s.mu.Lock()
		s.status = "SCAN_QR_CODE"
		s.currentQR = ""
		s.mu.Unlock()
		s.persistSessionStatus("SCAN_QR_CODE", "")

		qrChan, err := s.client.GetQRChannel(s.ctx)
		if err != nil {
			log.Printf("Failed to get WhatsApp QR channel: %v", err)
		} else {
			go s.listenQRChannel(qrChan)
		}
	} else {
		s.mu.Lock()
		s.status = "CONNECTING"
		s.currentQR = ""
		s.mu.Unlock()
		s.persistSessionStatus("CONNECTING", "")
	}

	err := s.client.Connect()
	if err != nil {
		log.Printf("WhatsApp initial connection attempt: %v", err)
	}

	// 1. Start Keep-Alive & Heartbeat Watchdog (every 25 seconds)
	go s.startHeartbeatWatchdog()

	// 2. Start Unified Queue Worker
	go s.startQueueWorker()

	// 3. Cleanup any stuck PROCESSING messages from past crashes
	go s.cleanupStuckProcessingMessages()
}

func (s *WhatsAppService) IsReady() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.client != nil && s.client.IsConnected() && s.client.IsLoggedIn()
}

func (s *WhatsAppService) listenQRChannel(qrChan <-chan whatsmeow.QRChannelItem) {
	for {
		select {
		case <-s.ctx.Done():
			return
		case item, ok := <-qrChan:
			if !ok {
				return
			}
			if item.Event == "code" {
				log.Printf("📲 [WhatsApp] Received pairing QR code from WhatsApp gateway")
				pngBytes, err := qrcode.Encode(item.Code, qrcode.Medium, 256)
				if err == nil {
					dataURL := "data:image/png;base64," + base64.StdEncoding.EncodeToString(pngBytes)
					s.mu.Lock()
					s.currentQR = dataURL
					s.status = "SCAN_QR_CODE"
					s.mu.Unlock()
					s.persistSessionStatus("SCAN_QR_CODE", dataURL)
				}
			} else if item.Event == "success" {
				log.Println("✅ [WhatsApp] Pairing handshake SUCCESSFUL!")
				s.mu.Lock()
				s.status = "CONNECTED"
				s.currentQR = ""
				s.mu.Unlock()
				s.persistSessionStatus("CONNECTED", "")
			} else if item.Event == "timeout" {
				log.Println("⏳ [WhatsApp] QR pairing timeout. Refreshing channel...")
			}
		}
	}
}

func (s *WhatsAppService) handleEvent(rawEvt interface{}) {
	now := time.Now().UTC()
	switch evt := rawEvt.(type) {
	case *events.Connected:
		log.Println("⚡ [WhatsApp] Connected to WhatsApp Web Gateway!")
		s.mu.Lock()
		s.status = "CONNECTED"
		s.currentQR = ""
		s.mu.Unlock()

		pushName := ""
		jidStr := ""
		if s.client != nil && s.client.Store != nil {
			pushName = s.client.Store.PushName
			if s.client.Store.ID != nil {
				jidStr = s.client.Store.ID.String()
			}
		}

		s.db.Exec(`
			INSERT INTO whatsapp_sessions (session_id, jid, status, qr_code, push_name, is_active, last_connected_at, last_heartbeat_at, created_at, updated_at)
			VALUES ('default', ?, 'CONNECTED', NULL, ?, true, ?, ?, ?, ?)
			ON CONFLICT (session_id) DO UPDATE
			SET status = 'CONNECTED', qr_code = NULL, jid = EXCLUDED.jid, push_name = EXCLUDED.push_name, is_active = true, last_connected_at = EXCLUDED.last_connected_at, last_heartbeat_at = EXCLUDED.last_heartbeat_at, updated_at = EXCLUDED.updated_at
		`, jidStr, pushName, now, now, now, now)

	case *events.LoggedOut:
		log.Printf("🚪 [WhatsApp] Logged out from WhatsApp on phone (Reason: %v). Clearing session...", evt.Reason)
		s.mu.Lock()
		s.status = "SCAN_QR_CODE"
		s.currentQR = ""
		s.mu.Unlock()
		s.persistSessionStatus("SCAN_QR_CODE", "")
		go func() {
			_ = s.RestartSession(context.Background())
		}()

	case *events.Disconnected:
		log.Println("⚠️ [WhatsApp] Disconnected from WhatsApp servers. Initiating auto-reconnect...")
		s.mu.Lock()
		if s.client != nil && s.client.Store.ID != nil {
			s.status = "RECONNECTING"
		} else {
			s.status = "SCAN_QR_CODE"
		}
		s.mu.Unlock()
		go s.triggerAutoReconnect()

	case *events.PairSuccess:
		log.Printf("✅ [WhatsApp] Pairing successful! (ID: %s, Business: %s)", evt.ID.String(), evt.BusinessName)
		s.mu.Lock()
		s.status = "CONNECTED"
		s.currentQR = ""
		s.mu.Unlock()
		s.persistSessionStatus("CONNECTED", "")

	case *events.StreamReplaced:
		log.Println("⚠️ [WhatsApp] Stream replaced by another active session. Reconnecting...")
		s.mu.Lock()
		s.status = "RECONNECTING"
		s.mu.Unlock()
		go s.triggerAutoReconnect()

	case *events.ConnectFailure:
		log.Printf("⚠️ [WhatsApp] Connection failure: %v", evt.Reason)
		s.mu.Lock()
		if s.client != nil && s.client.Store.ID != nil {
			s.status = "RECONNECTING"
		}
		s.mu.Unlock()

	case *events.TemporaryBan:
		log.Printf("🚨 [WhatsApp Warning] Temporary ban detected: %v (Expire: %v)", evt.Code, evt.Expire)
	}
}

func (s *WhatsAppService) startHeartbeatWatchdog() {
	ticker := time.NewTicker(25 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			if s.client == nil || s.client.Store.ID == nil {
				continue
			}

			if s.client.IsConnected() && s.client.IsLoggedIn() {
				// 1. Send lightweight presence keepalive to maintain TCP state & prevent NAT drops
				_ = s.client.SendPresence(s.ctx, types.PresenceAvailable)
				now := time.Now().UTC()
				s.mu.Lock()
				s.status = "CONNECTED"
				s.mu.Unlock()
				s.db.Model(&models.WhatsAppSession{}).Where("session_id = ?", "default").Updates(map[string]interface{}{
					"status":            "CONNECTED",
					"is_active":         true,
					"last_heartbeat_at": now,
					"updated_at":        now,
				})
			} else {
				// 2. Connection dropped or idle: trigger auto-reconnection
				log.Println("⚠️ [WhatsApp Watchdog] WebSocket not active or dropped. Triggering automatic reconnection...")
				s.mu.Lock()
				if s.client.Store.ID != nil {
					s.status = "RECONNECTING"
				} else {
					s.status = "SCAN_QR_CODE"
				}
				s.mu.Unlock()

				go s.triggerAutoReconnect()
			}
		}
	}
}

func (s *WhatsAppService) triggerAutoReconnect() {
	if !s.reconnectMu.TryLock() {
		return
	}
	defer s.reconnectMu.Unlock()

	if s.client == nil || s.client.Store.ID == nil {
		return
	}

	if s.client.IsConnected() && s.client.IsLoggedIn() {
		return
	}

	log.Println("🔄 [WhatsApp Reconnect] Safe reconnect attempt to WhatsApp Web gateway...")
	if s.client.IsConnected() {
		s.client.Disconnect()
		time.Sleep(300 * time.Millisecond)
	}

	err := s.client.Connect()
	if err != nil {
		log.Printf("⚠️ [WhatsApp Reconnect] Reconnect attempt failed: %v", err)
	} else {
		log.Println("⚡ [WhatsApp Reconnect] Reconnect request dispatched.")
	}
}

func (s *WhatsAppService) cleanupStuckProcessingMessages() {
	twoMinutesAgo := time.Now().UTC().Add(-2 * time.Minute)
	res := s.db.Model(&models.WhatsAppQueueMessage{}).
		Where("status = 'PROCESSING' AND (processing_started_at < ? OR processing_started_at IS NULL)", twoMinutesAgo).
		Updates(map[string]interface{}{
			"status":     "PENDING",
			"updated_at": time.Now().UTC(),
		})
	if res.RowsAffected > 0 {
		log.Printf("🔄 [WhatsApp Queue Worker] Recovered %d stuck PROCESSING messages back to PENDING.", res.RowsAffected)
	}
}

func (s *WhatsAppService) persistSessionStatus(status, qr string) {
	now := time.Now().UTC()
	var qrPtr *string
	if qr != "" {
		qrPtr = &qr
	}
	s.db.Exec(`
		INSERT INTO whatsapp_sessions (session_id, status, qr_code, is_active, created_at, updated_at)
		VALUES ('default', ?, ?, ?, ?, ?)
		ON CONFLICT (session_id) DO UPDATE
		SET status = EXCLUDED.status, qr_code = EXCLUDED.qr_code, is_active = EXCLUDED.is_active, updated_at = EXCLUDED.updated_at
	`, status, qrPtr, status == "CONNECTED", now, now)

	s.mu.RLock()
	hub := s.eventHub
	s.mu.RUnlock()
	if hub != nil {
		hub.Broadcast("WHATSAPP_STATUS_CHANGED", map[string]interface{}{
			"status": status,
			"qr":     qr,
		})
	}
}

func (s *WhatsAppService) GetStatus() (string, string) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.client != nil && s.client.IsConnected() && s.client.IsLoggedIn() {
		return "CONNECTED", ""
	}

	if s.currentQR != "" {
		return "SCAN_QR_CODE", s.currentQR
	}

	if s.status == "RECONNECTING" || s.status == "CONNECTING" {
		return s.status, ""
	}

	var session models.WhatsAppSession
	if err := s.db.Where("session_id = ?", "default").First(&session).Error; err == nil {
		var qr string
		if session.QRCode != nil {
			qr = *session.QRCode
		}
		return session.Status, qr
	}

	return s.status, s.currentQR
}

func (s *WhatsAppService) RestartSession(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client != nil {
		if s.client.IsConnected() {
			s.client.Disconnect()
		}
	}

	s.status = "SCAN_QR_CODE"
	s.currentQR = ""

	qrChan, err := s.client.GetQRChannel(s.ctx)
	if err != nil {
		return fmt.Errorf("failed to get QR channel: %w", err)
	}

	go s.listenQRChannel(qrChan)
	go func() {
		_ = s.client.Connect()
	}()

	return nil
}

func (s *WhatsAppService) Logout(ctx context.Context) error {
	if s.client != nil && s.client.IsLoggedIn() {
		_ = s.client.Logout(ctx)
	}
	return s.RestartSession(ctx)
}

func (s *WhatsAppService) SendTextMessage(ctx context.Context, phone, message string) error {
	if s.client == nil || !s.client.IsConnected() || !s.client.IsLoggedIn() {
		return fmt.Errorf("whatsapp is not connected")
	}

	normalized, err := ValidateWhatsAppPhone(phone)
	if err != nil {
		return err
	}

	if !strings.HasSuffix(normalized, "@s.whatsapp.net") {
		normalized = normalized + "@s.whatsapp.net"
	}

	jid, err := types.ParseJID(normalized)
	if err != nil {
		return fmt.Errorf("invalid JID: %w", err)
	}

	msg := &waE2E.Message{
		Conversation: proto.String(message),
	}

	_, err = s.client.SendMessage(ctx, jid, msg)
	return err
}

func (s *WhatsAppService) SendImageMessage(ctx context.Context, phone string, imageBytes []byte, caption string) error {
	if s.client == nil || !s.client.IsConnected() || !s.client.IsLoggedIn() {
		return fmt.Errorf("whatsapp is not connected")
	}

	if len(imageBytes) == 0 {
		return fmt.Errorf("empty image data")
	}

	normalized, err := ValidateWhatsAppPhone(phone)
	if err != nil {
		return err
	}

	if !strings.HasSuffix(normalized, "@s.whatsapp.net") {
		normalized = normalized + "@s.whatsapp.net"
	}

	jid, err := types.ParseJID(normalized)
	if err != nil {
		return fmt.Errorf("invalid JID: %w", err)
	}

	resp, err := s.client.Upload(ctx, imageBytes, whatsmeow.MediaImage)
	if err != nil {
		log.Printf("⚠️ Failed to upload image to WhatsApp server: %v", err)
		return fmt.Errorf("image upload failed: %w", err)
	}

	imageMsg := &waE2E.ImageMessage{
		Mimetype:      proto.String("image/png"),
		URL:           &resp.URL,
		DirectPath:    &resp.DirectPath,
		MediaKey:      resp.MediaKey,
		FileEncSHA256: resp.FileEncSHA256,
		FileSHA256:    resp.FileSHA256,
		FileLength:    proto.Uint64(uint64(len(imageBytes))),
	}
	if caption != "" {
		imageMsg.Caption = proto.String(caption)
	}

	msg := &waE2E.Message{
		ImageMessage: imageMsg,
	}

	_, err = s.client.SendMessage(ctx, jid, msg)
	return err
}

func (s *WhatsAppService) startQueueWorker() {
	ticker := time.NewTicker(1500 * time.Millisecond)
	defer ticker.Stop()

	stuckTicker := time.NewTicker(1 * time.Minute)
	defer stuckTicker.Stop()

	sentCount := 0

	processBatch := func() {
		if !s.IsReady() {
			return
		}

		var pendingMsgs []models.WhatsAppQueueMessage
		now := time.Now().UTC()
		err := s.db.Where("status = ? AND (scheduled_at <= ? OR scheduled_at IS NULL)", "PENDING", now).
			Order("scheduled_at ASC, created_at ASC").
			Limit(5).
			Find(&pendingMsgs).Error

		if err != nil || len(pendingMsgs) == 0 {
			return
		}

		for _, item := range pendingMsgs {
			if !s.IsReady() {
				break
			}

			procNow := time.Now().UTC()
			s.db.Model(&models.WhatsAppQueueMessage{}).Where("id = ? AND status = 'PENDING'", item.ID).Updates(map[string]interface{}{
				"status":                "PROCESSING",
				"processing_started_at": procNow,
				"updated_at":            procNow,
			})

			s.mu.RLock()
			hub := s.eventHub
			s.mu.RUnlock()
			if hub != nil {
				hub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{
					"id":     item.ID,
					"status": "PROCESSING",
				})
			}

			var sendErr error
			cleanPhone := NormalizeWhatsAppPhone(item.PhoneNumber)

			if cleanPhone == "" {
				sendErr = fmt.Errorf("invalid phone number: %s", item.PhoneNumber)
			} else if strings.ToUpper(item.Type) == "IMAGE" {
				var imgBytes []byte
				if item.SourceEntity != nil && *item.SourceEntity == "INVOICE" && item.SourceID != nil && s.renderService != nil {
					imgBytes, sendErr = s.renderService.RenderInvoicePNG(*item.SourceID)
				} else if item.SourceEntity != nil && *item.SourceEntity == "PAYMENT" && item.SourceID != nil && s.renderService != nil {
					imgBytes, sendErr = s.renderService.RenderPaymentReceiptPNG(*item.SourceID)
				} else if item.ImageBase64 != nil && *item.ImageBase64 != "" {
					b64Data := *item.ImageBase64
					if idx := strings.Index(b64Data, ","); idx != -1 {
						b64Data = b64Data[idx+1:]
					}
					imgBytes, sendErr = base64.StdEncoding.DecodeString(b64Data)
				} else if item.MediaPath != nil && *item.MediaPath != "" {
					imgBytes, sendErr = os.ReadFile(*item.MediaPath)
				} else {
					sendErr = fmt.Errorf("no image source found for queued message #%d", item.ID)
				}

				if sendErr == nil && len(imgBytes) > 0 {
					caption := ""
					if item.Caption != nil {
						caption = *item.Caption
					}
					sendErr = s.SendImageMessage(s.ctx, cleanPhone, imgBytes, caption)
				}
			} else {
				msgText := ""
				if item.Message != nil {
					msgText = *item.Message
				}
				sendErr = s.SendTextMessage(s.ctx, cleanPhone, msgText)
			}

			completedNow := time.Now().UTC()
			if sendErr == nil {
				sentCount++
				log.Printf("✅ [WhatsApp Queue Worker] Message #%d successfully sent to %s (Batch count: %d)", item.ID, cleanPhone, sentCount)
				s.db.Model(&models.WhatsAppQueueMessage{}).Where("id = ?", item.ID).Updates(map[string]interface{}{
					"status":     "SENT",
					"sent_at":    completedNow,
					"error_msg":  nil,
					"updated_at": completedNow,
				})

				if item.SourceEntity != nil && *item.SourceEntity == "INVOICE" && item.SourceID != nil {
					var inv models.Invoice
					if err := s.db.First(&inv, *item.SourceID).Error; err == nil && inv.ReadingID != nil {
						s.db.Model(&models.MeterReading{}).Where("id = ?", *inv.ReadingID).Update("whatsapp_sent", true)
					}
				} else if item.SourceEntity != nil && *item.SourceEntity == "PAYMENT" && item.SourceID != nil {
					s.db.Model(&models.Payment{}).Where("id = ?", *item.SourceID).Update("whatsapp_sent", true)
				}

				if hub != nil {
					hub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{
						"id":     item.ID,
						"status": "SENT",
					})
				}
			} else {
				log.Printf("❌ [WhatsApp Queue Worker] Failed sending message #%d to %s: %v", item.ID, cleanPhone, sendErr)
				retries := item.Retries + 1
				status := "PENDING"
				errMsg := sendErr.Error()

				isFatal := strings.Contains(errMsg, "invalid phone number") ||
					strings.Contains(errMsg, "invalid JID") ||
					strings.Contains(errMsg, "not registered") ||
					retries >= item.MaxRetries

				if isFatal {
					status = "FAILED"
				}

				nextSchedule := completedNow.Add(time.Duration(10*retries) * time.Second)
				s.db.Model(&models.WhatsAppQueueMessage{}).Where("id = ?", item.ID).Updates(map[string]interface{}{
					"status":       status,
					"retries":      retries,
					"error_msg":    errMsg,
					"scheduled_at": nextSchedule,
					"updated_at":   completedNow,
				})

				if hub != nil {
					hub.Broadcast("WHATSAPP_QUEUE_UPDATED", map[string]interface{}{
						"id":     item.ID,
						"status": status,
					})
				}
			}

			// Anti-Ban Jitter Delay
			jitterDelay := time.Duration(1500+rand.Intn(1500)) * time.Millisecond
			time.Sleep(jitterDelay)

			// Batch Cooldown
			if sentCount > 0 && sentCount%30 == 0 {
				log.Println("⏳ [WhatsApp Cooldown] Batch pause (10s) to protect account safety...")
				time.Sleep(10 * time.Second)
			}
		}
	}

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-stuckTicker.C:
			s.cleanupStuckProcessingMessages()
		case <-s.wakeChan:
			processBatch()
		case <-ticker.C:
			processBatch()
		}
	}
}

func (s *WhatsAppService) Close() {
	s.cancel()
	if s.client != nil {
		s.client.Disconnect()
	}
}
