import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import type { CheckUpdateResponse } from '../services/update.service';
import { checkUpdatesApi } from '../services/update.service';
import UpdateNotificationModal from '../components/UpdateNotificationModal';
import toast from 'react-hot-toast';

interface UpdateContextType {
  updateInfo: CheckUpdateResponse | null;
  hasUpdate: boolean;
  isChecking: boolean;
  isModalOpen: boolean;
  openModal: () => void;
  closeModal: () => void;
  checkForUpdates: (manual?: boolean) => Promise<CheckUpdateResponse | null>;
}

const UpdateContext = createContext<UpdateContextType | undefined>(undefined);

export const UpdateProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [updateInfo, setUpdateInfo] = useState<CheckUpdateResponse | null>(null);
  const [isChecking, setIsChecking] = useState<boolean>(false);
  const [isModalOpen, setIsModalOpen] = useState<boolean>(false);

  const checkForUpdates = useCallback(async (manual = false): Promise<CheckUpdateResponse | null> => {
    setIsChecking(true);
    try {
      const data = await checkUpdatesApi();
      setUpdateInfo(data);
      if (data && data.has_update) {
        setIsModalOpen(true);
      } else if (manual) {
        toast.success(`أنت تستخدم أحدث إصدار من البرنامج (v${data?.current_version || '1.0.0'})`);
      }
      return data;
    } catch (err: any) {
      if (manual) {
        toast.error('تعذر التحقق من التحديثات. يرجى التأكد من الاتصال بالإنترنت.');
      }
      return null;
    } finally {
      setIsChecking(false);
    }
  }, []);

  // Run non-intrusive background check on startup after 2.5s
  useEffect(() => {
    const timer = setTimeout(() => {
      checkForUpdates(false);
    }, 2500);
    return () => clearTimeout(timer);
  }, [checkForUpdates]);

  const openModal = () => setIsModalOpen(true);
  const closeModal = () => setIsModalOpen(false);

  return (
    <UpdateContext.Provider
      value={{
        updateInfo,
        hasUpdate: !!updateInfo?.has_update,
        isChecking,
        isModalOpen,
        openModal,
        closeModal,
        checkForUpdates,
      }}
    >
      {children}
      <UpdateNotificationModal
        isOpen={isModalOpen}
        onClose={closeModal}
        updateInfo={updateInfo}
        onCheckAgain={() => checkForUpdates(true)}
      />
    </UpdateContext.Provider>
  );
};

export const useUpdate = () => {
  const context = useContext(UpdateContext);
  if (!context) {
    throw new Error('useUpdate must be used within an UpdateProvider');
  }
  return context;
};
