import api from '../lib/api';

export interface CheckUpdateResponse {
  has_update: boolean;
  current_version: string;
  latest_version: string;
  download_url: string;
  sha256?: string;
  changelog: string;
  mandatory: boolean;
  error?: string;
}

export interface UpdateProgress {
  status: 'idle' | 'checking' | 'downloading' | 'ready' | 'applying' | 'error';
  progress: number;
  bytes_received: number;
  total_bytes: number;
  downloaded_path?: string;
  last_error?: string;
  latest_version?: string;
}

export const checkUpdatesApi = async (): Promise<CheckUpdateResponse> => {
  const res = await api.get<CheckUpdateResponse>('/system/check-updates');
  return res.data;
};

export const getUpdateStatusApi = async (): Promise<UpdateProgress> => {
  const res = await api.get<UpdateProgress>('/system/update-status');
  return res.data;
};

export const downloadUpdateApi = async (data?: { download_url?: string; sha256?: string }): Promise<{ success: boolean; message: string }> => {
  const res = await api.post('/system/download-update', data || {});
  return res.data;
};

export const applyUpdateApi = async (data?: { file_path?: string }): Promise<{ success: boolean; message: string }> => {
  const res = await api.post('/system/apply-update', data || {});
  return res.data;
};
