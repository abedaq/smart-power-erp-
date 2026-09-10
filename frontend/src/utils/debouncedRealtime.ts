import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getSavedApiUrl } from '../lib/api';

export interface RealtimeSubscriptionConfig {
  channelName: string;
  table: string; // 'meter_readings' | 'payments' | 'invoices' | 'customers' | 'whatsapp' | 'whatsapp_queue_messages' | 'whatsapp_sessions' | 'all'
  schema?: string;
  queryKeysToInvalidate: (string | number)[][];
  debounceMs?: number;
}

interface SystemEvent {
  type: string;
  payload?: any;
  timestamp: number;
}

const TABLE_EVENT_MAP: Record<string, string[]> = {
  meter_readings: ['READINGS_CHANGED'],
  readings: ['READINGS_CHANGED'],
  payments: ['PAYMENTS_CHANGED'],
  invoices: ['INVOICES_CHANGED', 'PAYMENTS_CHANGED', 'READINGS_CHANGED'],
  customers: ['CUSTOMERS_CHANGED'],
  whatsapp: ['WHATSAPP_STATUS_CHANGED', 'WHATSAPP_QUEUE_UPDATED'],
  whatsapp_queue_messages: ['WHATSAPP_QUEUE_UPDATED'],
  whatsapp_sessions: ['WHATSAPP_STATUS_CHANGED'],
  all: ['READINGS_CHANGED', 'PAYMENTS_CHANGED', 'INVOICES_CHANGED', 'CUSTOMERS_CHANGED', 'WHATSAPP_STATUS_CHANGED', 'WHATSAPP_QUEUE_UPDATED'],
};

/**
 * Event-Driven Realtime Hook via Server-Sent Events (SSE)
 * Replaces polling with instant push notifications from the Go backend.
 */
export function useDebouncedRealtime(configs: RealtimeSubscriptionConfig[]) {
  const queryClient = useQueryClient();
  const debounceTimers = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  useEffect(() => {
    if (!configs || configs.length === 0) return;

    let eventSource: EventSource | null = null;
    let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
    let isMounted = true;

    const connectSSE = () => {
      if (!isMounted) return;
      try {
        const apiUrl = getSavedApiUrl();
        const streamUrl = `${apiUrl}/realtime/stream`;

        eventSource = new EventSource(streamUrl);

        eventSource.onmessage = (event) => {
          if (!event.data) return;
          try {
            const parsed: SystemEvent = JSON.parse(event.data);
            if (parsed.type === 'CONNECTED') return;

            // Check which configs match this event type
            configs.forEach((cfg) => {
              const matchedEvents = TABLE_EVENT_MAP[cfg.table] || [cfg.table.toUpperCase()];
              if (matchedEvents.includes(parsed.type) || cfg.table === 'all') {
                const debounceMs = cfg.debounceMs ?? 800;

                cfg.queryKeysToInvalidate.forEach((queryKey) => {
                  const keyStr = JSON.stringify(queryKey);
                  const existingTimer = debounceTimers.current.get(keyStr);
                  if (existingTimer) {
                    clearTimeout(existingTimer);
                  }

                  const newTimer = setTimeout(() => {
                    queryClient.invalidateQueries({ queryKey });
                    debounceTimers.current.delete(keyStr);
                  }, debounceMs);

                  debounceTimers.current.set(keyStr, newTimer);
                });
              }
            });
          } catch (e) {
            // Non-JSON or comment keepalive
          }
        };

        eventSource.onerror = () => {
          if (eventSource) {
            eventSource.close();
            eventSource = null;
          }
          if (isMounted) {
            reconnectTimeout = setTimeout(connectSSE, 3000);
          }
        };
      } catch (err) {
        if (isMounted) {
          reconnectTimeout = setTimeout(connectSSE, 5000);
        }
      }
    };

    connectSSE();

    return () => {
      isMounted = false;
      if (reconnectTimeout) clearTimeout(reconnectTimeout);
      if (eventSource) {
        eventSource.close();
        eventSource = null;
      }
      debounceTimers.current.forEach((t) => clearTimeout(t));
      debounceTimers.current.clear();
    };
  }, [configs, queryClient]);
}
