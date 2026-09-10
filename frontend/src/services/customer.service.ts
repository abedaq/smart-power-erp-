import api from '../lib/api';

export const getCustomers = async (page = 1, limit = 5000, route = 'all', region = 'all') => {
  try {
    const res = await api.get('/customers', {
      params: {
        page,
        limit,
        route: route !== 'all' ? route : undefined,
        region: region !== 'all' ? region : undefined,
      },
    });
    if (res.data?.success && Array.isArray(res.data.data)) {
      return res.data;
    }
  } catch (err: any) {
    console.warn('Failed to load customers from API:', err?.message);
  }

  return {
    success: true,
    data: [],
    meta: {
      total: 0,
      page,
      limit,
      totalPages: 1,
    },
  };
};

export const getCustomerById = async (id: number) => {
  try {
    const res = await api.get(`/customers/${id}`);
    return res.data?.data || res.data;
  } catch (err: any) {
    console.warn('Failed to load customer by ID:', err?.message);
    return null;
  }
};

export const createCustomer = (data: any) =>
  api.post('/customers', data).then((res) => res.data?.data || res.data);

export const updateCustomer = (id: number, data: any) =>
  api.put(`/customers/${id}`, data).then((res) => res.data?.data || res.data);

export const deleteCustomer = (id: number) =>
  api.delete(`/customers/${id}`).then((res) => res.data?.data || res.data);

export const getUniqueRoutes = async () => {
  const cacheKey = 'smartpower_cached_routes';
  try {
    const res = await api.get('/customers/routes');
    if (res.data?.success && Array.isArray(res.data.data)) {
      localStorage.setItem(cacheKey, JSON.stringify(res.data.data));
      return res.data.data;
    }
  } catch (err) {}

  const cached = localStorage.getItem(cacheKey);
  return cached ? JSON.parse(cached) : [];
};

export const getUniqueRegions = async () => {
  try {
    const res = await api.get('/customers/regions');
    if (res.data?.success && Array.isArray(res.data.data)) {
      return res.data.data;
    }
  } catch (err) {}
  return [];
};

export const getNextSubscriberNumber = async (): Promise<string> => {
  try {
    const res = await api.get('/customers/next-subscriber-number');
    return String(res.data?.next_subscriber_number || res.data?.data?.next_subscriber_number || '10016');
  } catch (err) {
    console.warn('Failed to fetch next subscriber number:', err);
    return '10016';
  }
};
