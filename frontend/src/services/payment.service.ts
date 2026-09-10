import api from '../lib/api';

export const getPayments = async () => {
  try {
    const res = await api.get('/payments');
    if (res.data?.success && Array.isArray(res.data.data)) {
      return res.data.data;
    }
  } catch (err: any) {
    console.warn('Failed to load payments from API:', err?.message);
  }
  return [];
};

export const sendReceiptWhatsAppApi = (paymentId: number) =>
  api.post(`/payments/${paymentId}/send-whatsapp`).then((res) => res.data);
