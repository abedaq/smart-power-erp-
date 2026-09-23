import { useRealtime } from '../context/RealtimeContext';

export interface RealtimeSubscriptionConfig {
  channelName: string;
  table: string;
  schema?: string;
  queryKeysToInvalidate: (string | number)[][];
  debounceMs?: number;
}

/**
 * Lightweight compatibility hook.
 * The central RealtimeProvider now manages the singleton SSE stream and automatic invalidations.
 */
export function useDebouncedRealtime(_configs?: RealtimeSubscriptionConfig[]) {
  // Consumes central singleton realtime provider status without opening duplicate sockets
  const { isConnected, lastEventTime } = useRealtime();
  return { isConnected, lastEventTime };
}
