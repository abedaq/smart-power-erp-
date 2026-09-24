import React, { createContext, useContext, useEffect, useState, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { getSavedApiUrl } from '../lib/api';
import {
  QUERY_KEYS,
  invalidateFinancialTree,
  invalidateReadingsTree,
} from '../constants/queryKeys';

import type { UpdateProgress } from '../services/update.service';

interface RealtimeContextType {
  isConnected: boolean;
  lastEventTime: Date | null;
  lastUpdateProgress: UpdateProgress | null;
}

const RealtimeContext = createContext<RealtimeContextType>({
  isConnected: false,
  lastEventTime: null,
  lastUpdateProgress: null,
});

interface SystemEvent {
  type: string;
  payload?: any;
  timestamp: number;
}

export const RealtimeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const queryClient = useQueryClient();
  const [isConnected, setIsConnected] = useState(false);
  const [lastEventTime, setLastEventTime] = useState<Date | null>(null);
  const [lastUpdateProgress, setLastUpdateProgress] = useState<UpdateProgress | null>(null);

  const debounceTimers = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());
  const eventSourceRef = useRef<EventSource | null>(null);

  const debouncedInvalidate = (category: string, action: () => void, delayMs = 300) => {
    const existing = debounceTimers.current.get(category);
    if (existing) {
      clearTimeout(existing);
    }
    const timer = setTimeout(() => {
      action();
      debounceTimers.current.delete(category);
    }, delayMs);
    debounceTimers.current.set(category, timer);
  };

  useEffect(() => {
    let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
    let isMounted = true;

    const connect = () => {
      if (!isMounted) return;

      if (eventSourceRef.current) {
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }

      try {
        const apiUrl = getSavedApiUrl();
        const streamUrl = `${apiUrl}/realtime/stream`;

        const es = new EventSource(streamUrl);
        eventSourceRef.current = es;

        es.onopen = () => {
          if (isMounted) {
            setIsConnected(true);
          }
        };

        es.onmessage = (event) => {
          if (!event.data) return;
          try {
            const parsed: SystemEvent = JSON.parse(event.data);
            if (isMounted) {
              setLastEventTime(new Date());
            }

            if (parsed.type === 'CONNECTED') return;

            switch (parsed.type) {
              case 'INVOICES_CHANGED':
              case 'PAYMENTS_CHANGED':
              case 'CUSTOMERS_CHANGED':
                debouncedInvalidate('financial', () => invalidateFinancialTree(queryClient), 300);
                break;

              case 'READINGS_CHANGED':
                debouncedInvalidate('readings', () => invalidateReadingsTree(queryClient), 300);
                break;

              case 'WHATSAPP_STATUS_CHANGED':
              case 'WHATSAPP_QUEUE_UPDATED':
                debouncedInvalidate('whatsapp', () => {
                  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.whatsapp.status });
                  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.whatsapp.queue });
                  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.whatsapp.sent });
                }, 300);
                break;

              case 'USERS_CHANGED':
                debouncedInvalidate('users', () => {
                  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.users });
                }, 300);
                break;

              case 'SETTINGS_CHANGED':
                debouncedInvalidate('settings', () => {
                  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.settings });
                }, 300);
                break;

              case 'system:update_progress':
                if (isMounted && parsed.payload) {
                  setLastUpdateProgress(parsed.payload);
                }
                break;

              default:
                // Global fallback for any broadcasted data alteration
                debouncedInvalidate('all', () => invalidateFinancialTree(queryClient), 400);
                break;
            }
          } catch {
            // Ignore non-JSON keepalive comments
          }
        };

        es.onerror = () => {
          if (isMounted) {
            setIsConnected(false);
          }
          if (eventSourceRef.current) {
            eventSourceRef.current.close();
            eventSourceRef.current = null;
          }
          if (isMounted && !reconnectTimeout) {
            reconnectTimeout = setTimeout(() => {
              reconnectTimeout = null;
              connect();
            }, 3000);
          }
        };
      } catch {
        if (isMounted && !reconnectTimeout) {
          reconnectTimeout = setTimeout(() => {
            reconnectTimeout = null;
            connect();
          }, 5000);
        }
      }
    };

    connect();

    return () => {
      isMounted = false;
      if (reconnectTimeout) clearTimeout(reconnectTimeout);
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }
      debounceTimers.current.forEach((t) => clearTimeout(t));
      debounceTimers.current.clear();
    };
  }, [queryClient]);

  return (
    <RealtimeContext.Provider value={{ isConnected, lastEventTime, lastUpdateProgress }}>
      {children}
    </RealtimeContext.Provider>
  );
};

export const useRealtime = () => useContext(RealtimeContext);
