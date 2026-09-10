import api from '../lib/api';

export const getPlans = async () => {
  try {
    const res = await api.get('/plans');
    if (res.data?.success && Array.isArray(res.data.data) && res.data.data.length > 0) {
      return res.data.data;
    }
  } catch (err: any) {
    console.warn('Failed to load plans from API:', err?.message);
  }

  return [
    { id: 2, plan_name: 'باقة سكنية', kwh_price: 1400, fixed_fee: 1000, grace_period_days: 5 },
    { id: 1, plan_name: 'باقة تجارية', kwh_price: 2800, fixed_fee: 1000, grace_period_days: 5 },
  ];
};

export const createPlanApi = (data: any) =>
  api.post('/plans', data).then((res) => res.data?.data || res.data);

export const updatePlanApi = (id: number, data: any) =>
  api.put(`/plans/${id}`, data).then((res) => res.data?.data || res.data);

export const deletePlanApi = (id: number) =>
  api.delete(`/plans/${id}`).then((res) => res.data?.data || res.data);
