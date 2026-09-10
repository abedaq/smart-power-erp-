import React, { createContext, useContext, useState, useEffect } from 'react';
import type { LicenseStatus } from '../services/license.service';
import { getLicenseStatus, activateLicense, activateEmergencyCode, getMachineHWID } from '../services/license.service';

interface LicenseContextType {
  license: LicenseStatus | null;
  isLoading: boolean;
  hwid: string;
  error: string | null;
  activate: (key: string) => Promise<void>;
  activateEmergency: (code: string) => Promise<void>;
  refresh: () => Promise<void>;
}

const LicenseContext = createContext<LicenseContextType | undefined>(undefined);

export const LicenseProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [license, setLicense] = useState<LicenseStatus | null>(null);
  const [hwid, setHwid] = useState<string>('');
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const fetchStatus = async () => {
    try {
      setIsLoading(true);
      setError(null);
      const data = await getLicenseStatus();
      setLicense(data);
      if (data.machine_hwid) {
        setHwid(data.machine_hwid);
      } else {
        const id = await getMachineHWID();
        setHwid(id);
      }
    } catch (err: any) {
      console.error('Failed to fetch license status:', err);
      setError(err?.response?.data?.message || 'تعذر الاتصال بخدمة التحقق من التراخيص المحلية');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchStatus();
  }, []);

  const handleActivate = async (key: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const updated = await activateLicense(key);
      setLicense(updated);
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || 'فشل التفعيل';
      setError(msg);
      throw new Error(msg);
    } finally {
      setIsLoading(false);
    }
  };

  const handleActivateEmergency = async (code: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const updated = await activateEmergencyCode(code);
      setLicense(updated);
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || 'فشل تفعيل كود الطوارئ';
      setError(msg);
      throw new Error(msg);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <LicenseContext.Provider
      value={{
        license,
        isLoading,
        hwid,
        error,
        activate: handleActivate,
        activateEmergency: handleActivateEmergency,
        refresh: fetchStatus,
      }}
    >
      {children}
    </LicenseContext.Provider>
  );
};

export const useLicense = () => {
  const context = useContext(LicenseContext);
  if (!context) {
    throw new Error('useLicense must be used within a LicenseProvider');
  }
  return context;
};
