import api from '../lib/api';

export interface LicenseStatus {
  is_licensed: boolean;
  client_name: string;
  license_key: string;
  machine_hwid: string;
  expires_at: string;
  days_remaining: number;
  is_expired: boolean;
  is_offline: boolean;
  offline_days_left: number;
  is_time_tampered: boolean;
  error_message?: string;
  last_sync_time?: string;
}

export interface LicenseResponse {
  success: boolean;
  message?: string;
  data: LicenseStatus;
}

export const getLicenseStatus = async (): Promise<LicenseStatus> => {
  const res = await api.get<LicenseResponse>('/license/status');
  return res.data.data;
};

export const getMachineHWID = async (): Promise<string> => {
  const res = await api.get<{ success: boolean; hwid: string }>('/license/hwid');
  return res.data.hwid;
};

export const activateLicense = async (licenseKey: string): Promise<LicenseStatus> => {
  const res = await api.post<LicenseResponse>('/license/activate', { license_key: licenseKey });
  return res.data.data;
};

export const activateEmergencyCode = async (emergencyCode: string): Promise<LicenseStatus> => {
  const res = await api.post<LicenseResponse>('/license/emergency-code', { emergency_code: emergencyCode });
  return res.data.data;
};
