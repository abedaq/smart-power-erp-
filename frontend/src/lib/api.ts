import axios from 'axios';

export const getSavedApiUrl = (): string => {
  if (typeof window !== 'undefined') {
    let saved = localStorage.getItem('custom_api_url');
    if (saved && (saved.includes('10.0.108.253') || saved.includes('10.146.146.187') || saved.includes('127.0.0.1') || saved.includes('192.168.137.1') || saved.includes('undefined'))) {
      localStorage.removeItem('custom_api_url');
      saved = null;
    }
    if (saved?.trim()) {
      return saved.trim();
    }
    const hostname = window.location.hostname;
    // If inside Capacitor Native App on Android/iOS (hostname is localhost)
    const isCapacitorNative = (window as any).Capacitor?.isNativePlatform?.() ||
      (typeof navigator !== 'undefined' && /android|iphone|ipad/i.test(navigator.userAgent) && (!hostname || hostname === 'localhost'));

    if (isCapacitorNative) {
      return 'http://192.168.137.194:3000/api';
    }

    const host = hostname || 'localhost';
    const protocol = window.location.protocol?.startsWith('https') ? 'https:' : 'http:';
    return `${protocol}//${host}:3000/api`;
  }
  return 'http://localhost:3000/api';
};

const api = axios.create({
  baseURL: getSavedApiUrl(),
  timeout: 20000 // 20s generous timeout
});

export const setSavedApiUrl = (newUrl: string) => {
  let formatted = newUrl.trim();
  if (!formatted.startsWith('http://') && !formatted.startsWith('https://')) {
    formatted = `http://${formatted}`;
  }
  if (!formatted.endsWith('/api')) {
    formatted = `${formatted.replace(/\/$/, '')}/api`;
  }
  localStorage.setItem('custom_api_url', formatted);
  api.defaults.baseURL = formatted;
  return formatted;
};

api.interceptors.request.use(async (config) => {
  config.baseURL = getSavedApiUrl();
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => {
    return response;
  },
  async (error) => {
    if (error.response?.status === 401) {
      if (!error.config.url?.includes('/auth/login')) {
        localStorage.removeItem('token');
        localStorage.removeItem('user');
        if (typeof window !== 'undefined' && !window.location.pathname.includes('/login')) {
          window.location.href = '/login';
        }
      }
    }
    throw error;
  }
);

// Auth API
export const loginApi = (credentials: { username: string; password: string }) =>
  api.post('/auth/login', credentials).then(res => res.data);
export const getMeApi = () => api.get('/auth/me').then(res => res.data.data);

// Users API
export const getUsersApi = () => api.get('/users').then(res => res.data.data);
export const createUserApi = (data: any) => api.post('/users', data).then(res => res.data);
export const updateUserApi = (id: number, data: any) => api.put(`/users/${id}`, data).then(res => res.data);
export const resetUserPasswordApi = (id: number, new_password: string) => api.post(`/users/${id}/reset-password`, { new_password }).then(res => res.data);

// Audit Logs API
export const getAuditLogsApi = (page = 1, limit = 50, user_id = 'all', action = 'all', search = '') =>
  api.get(`/audit-logs?page=${page}&limit=${limit}&user_id=${user_id}&action=${action}&search=${encodeURIComponent(search)}`).then(res => res.data);

export const getCustomers = async (page = 1, limit = 500, route = 'all', region = 'all') => {
  const res = await api.get(`/customers?page=${page}&limit=${limit}&route=${route}&region=${region}`);
  return res.data;
};

export const createCustomer = (data: any) => api.post('/customers', data).then(res => res.data.data);

export const getCustomerById = async (id: number) => {
  const res = await api.get(`/customers/${id}`);
  return res.data.data;
};

export const updateCustomer = (id: number, data: any) => api.put(`/customers/${id}`, data).then(res => res.data.data);
export const deleteCustomer = (id: number) => api.delete(`/customers/${id}`).then(res => res.data.data);

export const getUniqueRoutes = async () => {
  const cacheKey = 'smartpower_cached_routes';
  try {
    const res = await api.get('/customers/routes');
    if (res.data && res.data.data) {
      localStorage.setItem(cacheKey, JSON.stringify(res.data.data));
    }
    return res.data.data;
  } catch (err) {
    const cached = localStorage.getItem(cacheKey);
    if (cached) {
      try {
        return JSON.parse(cached);
      } catch (e) {
        console.error('Failed to parse cached routes', e);
      }
    }
    return [];
  }
};

export const getUniqueRegions = () => api.get('/customers/regions').then(res => res.data.data);

// Plans API (with offline Dexie caching)
export const getPlans = async () => {
  try {
    const res = await api.get('/plans');
    if (res.data && res.data.data) {
      return res.data.data;
    }
    return [];
  } catch (err) {
    return [
      { id: 1, plan_name: 'باقة تجارية', kwh_price: 1400, fixed_fee: 1000, grace_period_days: 7 },
      { id: 2, plan_name: 'باقة سكنية', kwh_price: 1200, fixed_fee: 500, grace_period_days: 10 }
    ];
  }
};
export const createPlanApi = (data: { plan_name: string; kwh_price: number; fixed_fee?: number; grace_period_days?: number }) =>
  api.post('/plans', data).then(res => res.data.data);
export const updatePlanApi = (id: number, data: { plan_name: string; kwh_price: number; fixed_fee?: number; grace_period_days?: number }) =>
  api.put(`/plans/${id}`, data).then(res => res.data.data);
export const deletePlanApi = (id: number) =>
  api.delete(`/plans/${id}`).then(res => res.data);

// Meter Readings API
export const createReading = async (data: { customer_id: number; reading_value: number; collector_name: string; client_mutation_id?: string }) => {
  try {
    const res = await api.post('/readings', data);
    return res.data?.data || res.data;
  } catch (err: any) {
    // If local backend returns error, throw user friendly message
    throw new Error(err.response?.data?.message || err.message || 'فشل تسجيل القراءة');
  }
};

// Invoices & Payments API
export const getInvoices = (page = 1, limit = 50, route = 'all', region = 'all') => api.get(`/invoices?page=${page}&limit=${limit}&route=${route}&region=${region}`).then(res => res.data);
export const payInvoice = async (id: number, amount_paid: number, accountant_name: string, client_mutation_id?: string, invoice_id?: number) => {
  try {
    const res = await api.post('/payments', {
      customer_id: id,
      invoice_id: invoice_id,
      amount_paid,
      accountant_name,
      client_mutation_id,
    });
    return res.data?.data || res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل تسجيل السداد');
  }
};
export const getPayments = () => api.get('/payments').then(res => res.data.data);
export const sendReceiptWhatsAppApi = (paymentId: number) => api.post(`/payments/${paymentId}/send-whatsapp`).then(res => res.data);

// WhatsApp API
export const getWhatsAppStatus = () => api.get('/whatsapp/status').then(res => res.data?.data || res.data);
export const getWhatsAppMessages = (page = 1, limit = 50, type = 'all', status = 'all', search = '') =>
  api.get(`/whatsapp/messages?page=${page}&limit=${limit}&type=${type}&status=${status}&search=${encodeURIComponent(search)}`).then(res => res.data);
export const sendTestWhatsAppMessage = (to: string, message: string) => api.post('/whatsapp/send-test', { to, message }).then(res => res.data);
export const restartWhatsApp = () => api.post('/whatsapp/restart').then(res => res.data?.data || res.data);
export const logoutWhatsApp = () => api.post('/whatsapp/logout').then(res => res.data?.data || res.data);
export const connectWhatsApp = () => api.post('/whatsapp/connect').then(res => res.data?.data || res.data);
export const clearPendingWhatsAppQueue = () => api.delete('/whatsapp/queue/pending').then(res => res.data);
export const deleteWhatsAppMessageApi = (id: number) => api.delete(`/whatsapp/messages/${id}`).then(res => res.data);
export const retryWhatsAppMessageApi = (id: number) => api.post(`/whatsapp/messages/${id}/retry`).then(res => res.data);
export const retryAllWhatsAppQueueApi = () => api.post('/whatsapp/queue/retry-all').then(res => res.data);
export const clearAllWhatsAppMessagesApi = () => api.delete('/whatsapp/messages').then(res => res.data);

// Settings API
export const getSettings = () => api.get('/settings').then(res => res.data.data);
export const updateSettings = (data: any) => api.put('/settings', data).then(res => res.data.data);
export const uploadStationLogoApi = (file: File) => {
  const formData = new FormData();
  formData.append('logo', file);
  return api.post('/settings/logo', formData).then(res => res.data.data);
};

// Export API
export const exportGeneralRoster = async () => {
  try {
    const response = await api.get('/export/general-roster', { responseType: 'blob' });
    const url = window.URL.createObjectURL(new Blob([response.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `General_Roster_${new Date().toISOString().slice(0, 10)}.xlsx`);
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
  } catch (error: any) {
    console.error('Export error:', error);
    throw error;
  }
};

export const exportBillingCycle = async (cycleId: string = 'all') => {
  try {
    const response = await api.get('/export/cycle', {
      params: { cycle: cycleId },
      responseType: 'blob',
    });
    const blob = new Blob([response.data], {
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    const cleanCycle = cycleId.replace(/[\s\/\\]/g, '_');
    link.setAttribute('download', `كشف_فواتير_${cleanCycle}_${new Date().toISOString().slice(0, 10)}.xlsx`);
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
  } catch (error: any) {
    console.error('Export error:', error);
    throw error;
  }
};

export const sendInvoiceWhatsApp = (invoiceId: number) => api.post('/whatsapp/send-invoice', { invoice_id: invoiceId }).then(res => res.data);
export const sendDisconnectionWarning = (customerId: number, amount: number) => api.post('/whatsapp/send-warning', { customer_id: customerId, amount }).then(res => res.data);
export const sendBulkDisconnectionWarnings = (items: Array<{ customer_id: number; amount: number }>) => api.post('/whatsapp/send-bulk-warnings', { items }).then(res => res.data);

export const getMonthlyPerformance = () => api.get('/analytics/monthly-performance').then(res => res.data?.data || []);
export const getOverdueReport = (category: string = 'all', route: string = 'all', region: string = 'all') => api.get(`/analytics/overdue-report?category=${category}&route=${route}&region=${region}`).then(res => res.data.data);
export const getDashboardSummary = () => api.get('/analytics/dashboard-summary').then(res => res.data.data);
export const getRoutesProgress = () => api.get('/analytics/routes-progress').then(res => res.data.data);

export const startAsyncImportApi = (formData: FormData) =>
  api.post('/import/async', formData, { headers: { 'Content-Type': 'multipart/form-data' } }).then(res => res.data);
export const getImportJobStatusApi = (jobId: string) =>
  api.get(`/import/status/${jobId}`).then(res => res.data);
export const cancelImportJobApi = (jobId: string) =>
  api.post(`/import/cancel/${jobId}`).then(res => res.data);
export const cleanupTestDataApi = (tag: string = 'LOADTEST') =>
  api.post('/import/cleanup-test', { tag }).then(res => res.data);

export const approveReadingApi = async (id: number) => {
  try {
    const res = await api.post(`/readings/approve/${id}`);
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل اعتماد القراءة');
  }
};

export const rejectReadingApi = async (id: number, reason: string) => {
  try {
    const res = await api.post(`/readings/reject/${id}`, { reason });
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل رفض القراءة');
  }
};

export const updateReadingApi = async (id: number, reading_value: number) => {
  try {
    const res = await api.put(`/readings/${id}`, { reading_value });
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل تعديل القراءة');
  }
};

export const approvePaymentApi = async (id: number) => {
  try {
    const res = await api.post(`/payments/approve/${id}`);
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل اعتماد السداد');
  }
};

export const rejectPaymentApi = async (id: number, reason: string) => {
  try {
    const res = await api.post(`/payments/reject/${id}`, { reason });
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل رفض السداد');
  }
};

export const updatePaymentAmountApi = async (id: number, amount_paid: number) => {
  try {
    const res = await api.put(`/payments/${id}`, { amount_paid });
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل تعديل مبلغ السداد');
  }
};

export const approveAllPendingApi = async () => {
  try {
    const res = await api.post('/readings/approve-all');
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل الاعتماد الجماعي');
  }
};

export default api;
