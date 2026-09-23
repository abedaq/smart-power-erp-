import { QueryClient } from '@tanstack/react-query';

/**
 * Unified Query Keys Factory for React Query
 * Prevents key drift and ensures coherent multi-entity cache invalidation.
 */
export const QUERY_KEYS = {
  // Customers & Subscribers
  customers: {
    all: ['customers'] as const,
    list: (filters?: any) => ['customers', 'list', filters] as const,
    detail: (id?: number | string) => ['customer-details', id] as const,
  },

  // Invoices & Billing
  invoices: {
    all: ['invoices'] as const,
    byFilter: (filters?: any) => ['invoices', filters] as const,
    unpaidArrears: ['invoices-all-unpaid'] as const,
  },

  // Payments & Receipts
  payments: {
    all: ['payments'] as const,
    byFilter: (filters?: any) => ['payments', filters] as const,
    recent: ['recent-transactions'] as const,
  },

  // Meter Readings & Cycles
  readings: {
    all: ['readings'] as const,
    routesProgress: ['routes-progress'] as const,
  },

  // Analytics & Dashboard
  dashboard: {
    monthlyPerformance: ['monthly-performance'] as const,
    summary: ['monthly-performance'] as const, // Aliased to prevent phantom keys
  },

  // System Settings & Master Data
  settings: ['settings'] as const,
  routes: ['routes'] as const,
  users: ['users'] as const,
  auditLogs: ['audit-logs'] as const,

  // WhatsApp Gateway
  whatsapp: {
    all: ['whatsapp'] as const,
    status: ['whatsapp-status'] as const,
    queue: ['whatsapp-queue'] as const,
    sent: ['whatsapp-sent'] as const,
  },
} as const;

/**
 * Invalidate entire financial tree atomically:
 * Invoices, Payments, Customers, Unpaid Arrears, Dashboard Performance, and Recent Transactions.
 */
export function invalidateFinancialTree(queryClient: QueryClient) {
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.invoices.all });
  queryClient.invalidateQueries({ queryKey: ['arrears-invoices'] });
  queryClient.invalidateQueries({ queryKey: ['invoices-all-cycles-for-tabs'] });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.invoices.unpaidArrears });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.payments.all });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.payments.recent });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.customers.all });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.dashboard.monthlyPerformance });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.readings.routesProgress });
}

/**
 * Invalidate readings and associated progress counters
 */
export function invalidateReadingsTree(queryClient: QueryClient, customerId?: number | string) {
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.readings.all });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.readings.routesProgress });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.invoices.all });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.invoices.unpaidArrears });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.customers.all });
  queryClient.invalidateQueries({ queryKey: QUERY_KEYS.dashboard.monthlyPerformance });
  if (customerId) {
    queryClient.invalidateQueries({ queryKey: QUERY_KEYS.customers.detail(customerId) });
  }
}
