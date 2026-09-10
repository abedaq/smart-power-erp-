import api from '../lib/api';

export const getInvoices = async (page = 1, limit = 1000, route = 'all', region = 'all', cycle = 'all') => {
  try {
    const res = await api.get('/invoices', {
      params: {
        page,
        limit,
        route: route !== 'all' ? route : undefined,
        region: region !== 'all' ? region : undefined,
        cycle: cycle !== 'all' ? cycle : undefined,
      }
    });
    if (res.data?.success && Array.isArray(res.data.data)) {
      return res.data;
    }
  } catch (err: any) {
    console.warn('Failed to load invoices from API:', err?.message);
  }

  return {
    success: true,
    data: [],
    meta: {
      total: 0,
      page,
      limit,
      totalPages: 1
    }
  };
};

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

export const sendInvoiceWhatsApp = (invoiceId: number) =>
  api.post('/whatsapp/send-invoice', { invoice_id: invoiceId }).then(res => res.data);

export const sendDisconnectionWarning = (customerId: number, amount: number) =>
  api.post('/whatsapp/send-warning', { customer_id: customerId, amount }).then(res => res.data);

export const sendBulkDisconnectionWarnings = (items: Array<{ customer_id: number; amount: number }>) =>
  api.post('/whatsapp/send-bulk-warnings', { items }).then(res => res.data);
