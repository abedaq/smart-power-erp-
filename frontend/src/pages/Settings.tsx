import React from 'react';
import { useSearchParams } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Navigate } from 'react-router-dom';
import { Settings as SettingsIcon, Smartphone, UserCheck, ShieldAlert, Sparkles, LifeBuoy } from 'lucide-react';
import { useUpdate } from '../context/UpdateContext';
import WhatsApp from './WhatsApp';
import UsersManagement from './UsersManagement';
import AuditLogs from './AuditLogs';
import SystemUpdates from './SystemUpdates';
import SupportDiagnostics from './SupportDiagnostics';

const Settings: React.FC = () => {
  const { user } = useAuth();
  const { hasUpdate } = useUpdate();
  const [searchParams, setSearchParams] = useSearchParams();
  const activeTab = searchParams.get('tab') || 'users';

  // Strict role guard: only ADMIN can access settings
  if (user && user.role !== 'ADMIN') {
    return <Navigate to={user.role === 'ACCOUNTANT' ? '/invoices' : '/customers'} replace />;
  }

  const setTab = (tab: string) => {
    setSearchParams({ tab });
  };

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header */}
      <div className="flex justify-between items-center border-b border-slate-200 pb-4">
        <div>
          <h1 className="text-xl sm:text-2xl font-bold flex items-center gap-2 text-slate-900">
            <SettingsIcon className="text-blue-600" />
            مركز الإعدادات والتهيئة
          </h1>
          <p className="text-slate-500 text-xs sm:text-sm mt-0.5 font-medium">
            إدارة المستخدمين والصلاحيات، سجل الرقابة والتدقيق، تحديثات النظام، وبوابة الواتساب.
          </p>
        </div>
      </div>

      {/* Sub-Tabs Bar */}
      <div className="flex flex-wrap bg-slate-100/90 p-1.5 rounded-2xl border-2 border-slate-200 gap-2 shadow-sm">
        <button
          onClick={() => setTab('users')}
          className={`flex items-center gap-2.5 px-6 py-3 font-black text-sm rounded-xl transition-all ${
            activeTab === 'users'
              ? 'bg-white text-purple-800 shadow-md border border-purple-200 ring-2 ring-purple-500/20'
              : 'text-slate-700 hover:text-slate-900 hover:bg-white/60'
          }`}
        >
          <UserCheck size={20} className={activeTab === 'users' ? 'text-purple-600' : 'text-slate-500'} />
          <span>إدارة المستخدمين والصلاحيات</span>
        </button>

        <button
          onClick={() => setTab('whatsapp')}
          className={`flex items-center gap-2.5 px-6 py-3 font-black text-sm rounded-xl transition-all ${
            activeTab === 'whatsapp'
              ? 'bg-white text-blue-800 shadow-md border border-blue-200 ring-2 ring-blue-500/20'
              : 'text-slate-700 hover:text-slate-900 hover:bg-white/60'
          }`}
        >
          <Smartphone size={20} className={activeTab === 'whatsapp' ? 'text-blue-600' : 'text-slate-500'} />
          <span>إدارة وبوابة الواتساب</span>
        </button>

        <button
          onClick={() => setTab('audit-logs')}
          className={`flex items-center gap-2.5 px-6 py-3 font-black text-sm rounded-xl transition-all ${
            activeTab === 'audit-logs'
              ? 'bg-white text-amber-900 shadow-md border border-amber-200 ring-2 ring-amber-500/20'
              : 'text-slate-700 hover:text-slate-900 hover:bg-white/60'
          }`}
        >
          <ShieldAlert size={20} className={activeTab === 'audit-logs' ? 'text-amber-600' : 'text-slate-500'} />
          <span>سجل الرقابة والتدقيق الشامل</span>
        </button>

        <button
          onClick={() => setTab('updates')}
          className={`flex items-center gap-2.5 px-6 py-3 font-black text-sm rounded-xl transition-all relative ${
            activeTab === 'updates'
              ? 'bg-white text-cyan-900 shadow-md border border-cyan-200 ring-2 ring-cyan-500/20'
              : 'text-slate-700 hover:text-slate-900 hover:bg-white/60'
          }`}
        >
          <Sparkles size={20} className={activeTab === 'updates' ? 'text-cyan-600' : 'text-slate-500'} />
          <span>تحديثات النظام</span>
          {hasUpdate && (
            <span className="w-2.5 h-2.5 bg-rose-500 rounded-full animate-ping absolute top-2.5 left-2.5" />
          )}
        </button>

        <button
          onClick={() => setTab('diagnostics')}
          className={`flex items-center gap-2.5 px-6 py-3 font-black text-sm rounded-xl transition-all ${
            activeTab === 'diagnostics'
              ? 'bg-white text-sky-900 shadow-md border border-sky-200 ring-2 ring-sky-500/20'
              : 'text-slate-700 hover:text-slate-900 hover:bg-white/60'
          }`}
        >
          <LifeBuoy size={20} className={activeTab === 'diagnostics' ? 'text-sky-600' : 'text-slate-500'} />
          <span>الدعم الفني وتشخيص السجلات</span>
        </button>
      </div>

      {/* Tab Content */}
      {activeTab === 'users' && (
        <div>
          <UsersManagement />
        </div>
      )}

      {activeTab === 'whatsapp' && (
        <div>
          <WhatsApp />
        </div>
      )}

      {activeTab === 'audit-logs' && (
        <div>
          <AuditLogs />
        </div>
      )}

      {activeTab === 'updates' && (
        <div>
          <SystemUpdates />
        </div>
      )}

      {activeTab === 'diagnostics' && (
        <div>
          <SupportDiagnostics />
        </div>
      )}
    </div>
  );
};

export default Settings;

