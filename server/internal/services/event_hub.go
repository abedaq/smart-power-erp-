package services

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/valyala/fasthttp"
)

type SystemEvent struct {
	Type      string      `json:"type"`
	Payload   interface{} `json:"payload,omitempty"`
	Timestamp int64       `json:"timestamp"`
}

type EventHub struct {
	mu      sync.RWMutex
	clients map[chan SystemEvent]bool
}

func NewEventHub() *EventHub {
	return &EventHub{
		clients: make(map[chan SystemEvent]bool),
	}
}

func (h *EventHub) Subscribe() (chan SystemEvent, func()) {
	clientChan := make(chan SystemEvent, 100)

	h.mu.Lock()
	h.clients[clientChan] = true
	h.mu.Unlock()

	unsubscribe := func() {
		h.mu.Lock()
		if _, exists := h.clients[clientChan]; exists {
			delete(h.clients, clientChan)
			close(clientChan)
		}
		h.mu.Unlock()
	}

	return clientChan, unsubscribe
}

func (h *EventHub) Broadcast(eventType string, payload interface{}) {
	event := SystemEvent{
		Type:      eventType,
		Payload:   payload,
		Timestamp: time.Now().UTC().UnixMilli(),
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	for clientChan := range h.clients {
		select {
		case clientChan <- event:
		default:
			// Client channel full or slow consumer, drop to prevent blocking
		}
	}
}

func (h *EventHub) HandleSSEStream(c *fiber.Ctx) error {
	c.Set("Content-Type", "text/event-stream")
	c.Set("Cache-Control", "no-cache")
	c.Set("Connection", "keep-alive")
	c.Set("Transfer-Encoding", "chunked")
	c.Set("Access-Control-Allow-Origin", "*")

	clientChan, unsubscribe := h.Subscribe()

	c.Context().SetBodyStreamWriter(fasthttp.StreamWriter(func(w *bufio.Writer) {
		defer unsubscribe()

		// Send initial connected handshake event
		initialEvent, _ := json.Marshal(SystemEvent{
			Type:      "CONNECTED",
			Timestamp: time.Now().UTC().UnixMilli(),
		})
		_, _ = fmt.Fprintf(w, "event: message\ndata: %s\n\n", initialEvent)
		_ = w.Flush()

		keepAliveTicker := time.NewTicker(15 * time.Second)
		defer keepAliveTicker.Stop()

		for {
			select {
			case <-keepAliveTicker.C:
				// Send lightweight comment keepalive ping
				_, err := fmt.Fprintf(w, ": keepalive\n\n")
				if err != nil {
					return
				}
				if err := w.Flush(); err != nil {
					return
				}

			case event, ok := <-clientChan:
				if !ok {
					return
				}
				dataBytes, err := json.Marshal(event)
				if err != nil {
					log.Printf("⚠️ [EventHub] Failed to marshal SSE event: %v", err)
					continue
				}

				_, err = fmt.Fprintf(w, "event: message\ndata: %s\n\n", dataBytes)
				if err != nil {
					return
				}
				if err := w.Flush(); err != nil {
					return
				}
			}
		}
	}))

	return nil
}
