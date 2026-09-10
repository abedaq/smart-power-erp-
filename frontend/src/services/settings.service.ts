import api from '../lib/api';

export const getSettings = async () => {
  try {
    const res = await api.get('/settings');
    if (res.data?.data) {
      return res.data.data;
    }
  } catch (err: any) {
    console.warn('Failed to load settings from API:', err?.message);
  }

  return {
    arrears_threshold: 0,
    max_overdue_days: 7,
  };
};

export const updateSettings = (data: any) =>
  api.put('/settings', data).then((res) => res.data?.data || res.data);
