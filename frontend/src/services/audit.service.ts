import api from '../lib/api';

export interface AuditLogItem {
  id: number;
  user_id?: number | null;
  action: string;
  entity?: string | null;
  entity_id?: string | null;
  details?: string | null;
  created_at: string;
  user?: {
    id?: number;
    full_name: string;
    username: string;
    role: string;
  } | null;
}

export const getAuditLogsApi = async (page = 1, limit = 50, user_id = 'all', action = 'all', search = '') => {
  try {
    const res = await api.get('/audit-logs', {
      params: { page, limit, user_id, action, search }
    });
    if (res.data && res.data.success) {
      return {
        success: true,
        data: res.data.data || [],
        meta: res.data.meta || {
          total: res.data.total || 0,
          page,
          limit,
          totalPages: res.data.meta?.totalPages || 1
        }
      };
    }
  } catch (err: any) {
    console.warn('Backend /audit-logs endpoint failed:', err?.message);
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

export const logActivityApi = async (data: {
  action: string;
  entity?: string;
  entity_id?: string;
  details?: string;
}) => {
  try {
    const res = await api.post('/audit/activity', data);
    return res.data;
  } catch (err: any) {
    console.warn('Failed to log activity audit:', err?.message);
  }
};
