import React, { useEffect } from 'react';
import { HashRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider, useAuth } from './context/AuthContext';
import { LicenseProvider, useLicense } from './context/LicenseContext';
import { UpdateProvider } from './context/UpdateContext';
import { LicenseActivationModal } from './components/LicenseActivationModal';
import Layout from './components/Layout';

import Dashboard from './pages/Dashboard';
import Invoices from './pages/Invoices';
import Settings from './pages/Settings';
import ArrearsReport from './pages/ArrearsReport';
import Login from './pages/Login';

const ProtectedRoute: React.FC<{ children: React.ReactNode; allowedRoles?: string[] }> = ({ children, allowedRoles }) => {
  const { user, token, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center font-bold text-slate-500" dir="rtl">
        جاري التحقق من الجلسة...
      </div>
    );
  }

  // Allow access if token exists
  if (!token) {
    return <Navigate to="/login" replace />;
  }

  // Check role authorization if specified
  if (allowedRoles && user && !allowedRoles.includes(user.role)) {
    if (user.role === 'COLLECTOR' || user.role === 'ACCOUNTANT' || user.role === 'CASHIER') {
      return <Navigate to="/invoices" replace />;
    }
    return <Navigate to="/" replace />;
  }

  return <>{children}</>;
};

const AppContent: React.FC = () => {
  const { license, isLoading: isLicenseLoading } = useLicense();

  return (
    <>
      <LicenseActivationModal isOpen={!isLicenseLoading && (!license || !license.is_licensed)} />
      <HashRouter>
        <Routes>
          <Route path="/login" element={<Login />} />

          <Route
            path="/"
            element={
              <ProtectedRoute>
                <Layout />
              </ProtectedRoute>
            }
          >
            <Route index element={<Dashboard />} />
            <Route path="customers" element={<Navigate to="/invoices" replace />} />
            <Route 
              path="invoices" 
              element={
                <ProtectedRoute allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER', 'COLLECTOR']}>
                  <Invoices />
                </ProtectedRoute>
              } 
            />
            <Route path="reports" element={<Navigate to="/invoices" replace />} />
            <Route 
              path="arrears" 
              element={
                <ProtectedRoute allowedRoles={['ADMIN', 'ACCOUNTANT', 'CASHIER']}>
                  <ArrearsReport />
                </ProtectedRoute>
              } 
            />
            <Route path="unread-meters" element={<Navigate to="/invoices" replace />} />
            <Route 
              path="settings" 
              element={
                <ProtectedRoute allowedRoles={['ADMIN']}>
                  <Settings />
                </ProtectedRoute>
              } 
            />
            <Route path="approved-edits" element={<Navigate to="/invoices" replace />} />
            <Route path="users" element={<Navigate to="/settings?tab=users" replace />} />
            <Route path="audit-logs" element={<Navigate to="/settings?tab=audit-logs" replace />} />
            <Route path="whatsapp" element={<Navigate to="/settings?tab=whatsapp" replace />} />
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </HashRouter>
    </>
  );
};

const App: React.FC = () => {
  useEffect(() => {
    // Engine initialization
  }, []);

  return (
    <LicenseProvider>
      <AuthProvider>
        <UpdateProvider>
          <AppContent />
        </UpdateProvider>
      </AuthProvider>
    </LicenseProvider>
  );
};

export default App;
