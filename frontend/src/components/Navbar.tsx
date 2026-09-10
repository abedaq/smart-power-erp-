import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { useQuery } from '@tanstack/react-query';
import { useDebouncedRealtime } from '../utils/debouncedRealtime';
import { getRecentTransactions } from '../services/analytics.service';
import { useUpdate } from '../context/UpdateContext';
import { Bell, Menu, LogOut, PanelRightOpen, Sparkles } from 'lucide-react';


interface NavbarProps {
  onToggleSidebar?: () => void;
  isSidebarCollapsed?: boolean;
}

const Navbar: React.FC<NavbarProps> = ({ onToggleSidebar, isSidebarCollapsed }) => {
  const { user, logout } = useAuth();
  const { hasUpdate, updateInfo, openModal } = useUpdate();
  const [showNotifications, setShowNotifications] = useState(false);

  useDebouncedRealtime([
    {
      channelName: 'navbar:transactions',
      table: 'all',
      queryKeysToInvalidate: [['recent-transactions']],
      debounceMs: 500,
    },
  ]);

  const { data: recentTransactions = [] } = useQuery({
    queryKey: ['recent-transactions'],
    queryFn: getRecentTransactions,
    staleTime: 60000,
  });

  const rawLiveFeed = recentTransactions;
  const pendingCount = rawLiveFeed.filter((item: any) => item.approval_status === 'PENDING').length;


  const getRoleBadge = (role?: string) => {
    switch (role) {
      case 'ADMIN':
        return <span className="bg-purple-100 text-purple-950 border-2 border-purple-300 text-xs px-2.5 py-1 rounded-xl font-black shadow-sm">مدير النظام</span>;
      case 'CASHIER':
        return <span className="bg-blue-100 text-blue-950 border-2 border-blue-300 text-xs px-2.5 py-1 rounded-xl font-black shadow-sm">محاسب المحطة</span>;
      case 'COLLECTOR':
        return <span className="bg-emerald-100 text-emerald-950 border-2 border-emerald-300 text-xs px-2.5 py-1 rounded-xl font-black shadow-sm">محصل ميداني</span>;
      default:
        return null;
    }
  };

  return (
    <header className="h-16 bg-white border-b-2 border-slate-200 flex items-center justify-between px-4 sm:px-6 shadow-sm relative z-30" dir="rtl">
      <div className="flex items-center gap-3.5">
        <button
          onClick={onToggleSidebar}
          className={`p-2.5 rounded-xl border-2 transition-all flex items-center gap-2 text-xs font-black ${isSidebarCollapsed
            ? 'bg-blue-50 text-blue-800 border-blue-300 shadow-sm'
            : 'text-slate-700 hover:text-slate-950 bg-slate-100 border-slate-200 hover:bg-slate-200'
            }`}
          title={isSidebarCollapsed ? "إظهار القائمة الجانبية" : "إخفاء القائمة الجانبية لتوسيع الشاشة"}
        >
          {isSidebarCollapsed ? <PanelRightOpen size={20} className="text-blue-600 animate-pulse" /> : <Menu size={20} />}
          {isSidebarCollapsed && <span className="hidden sm:inline">إظهار القائمة</span>}
        </button>

        <div className="flex items-center gap-2.5">
          <span className="text-xs font-bold text-slate-500">مرحباً بك،</span>
          <h2 className="text-base font-black text-slate-900">{user?.full_name || 'المستخدم'}</h2>
          {getRoleBadge(user?.role)}
          <div className="hidden md:flex items-center gap-1.5 bg-gradient-to-r from-indigo-600 to-purple-600 text-white px-2.5 py-1 rounded-xl text-xs font-black shadow-sm">
            <span>🚀 إصدار السحاب v1.0.3 - النواة المحصنة بالكامل</span>
          </div>
        </div>
      </div>

      <div className="flex items-center space-x-3 space-x-reverse">
        {/* Update Available Badge / Button */}
        {hasUpdate && (
          <button
            onClick={openModal}
            className="flex items-center gap-2 px-3 py-1.5 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 text-white rounded-xl text-xs font-black shadow-md shadow-blue-500/20 animate-pulse transition-all cursor-pointer"
            title="تحديث جديد متوفر للبرنامج"
          >
            <Sparkles size={14} className="text-yellow-300" />
            <span className="hidden md:inline">تحديث متوفر (v{updateInfo?.latest_version})</span>
            <span className="md:hidden">تحديث</span>
          </button>
        )}

        {/* Notification Bell */}
        <div className="relative">
          <button
            onClick={() => setShowNotifications(!showNotifications)}
            className="p-2 text-slate-600 hover:text-slate-900 transition-colors relative bg-slate-100 rounded-xl border border-slate-200 hover:bg-slate-200"
            title="الإشعارات"
          >
            <Bell size={18} />
            {pendingCount > 0 && (
              <span className="absolute -top-1 -right-1 w-4 h-4 bg-rose-500 text-white text-[10px] font-bold rounded-full flex items-center justify-center animate-pulse">
                {pendingCount}
              </span>
            )}
          </button>

          {/* Notifications Dropdown */}
          {showNotifications && (
            <div className="absolute left-0 mt-2 w-72 bg-white rounded-2xl border border-slate-200 shadow-xl p-4 space-y-3 z-50 animate-in fade-in zoom-in-95">
              <div className="flex items-center justify-between border-b border-slate-100 pb-2">
                <h3 className="text-xs font-bold text-slate-900">مركز الإشعارات والتنبيهات</h3>
                <span className="text-[10px] bg-blue-100 text-blue-700 px-2 py-0.5 rounded-full font-bold">
                  {pendingCount} معلق
                </span>
              </div>

              {pendingCount === 0 ? (
                <p className="text-center text-xs text-slate-400 py-3">لا توجد إشعارات جديدة</p>
              ) : (
                <div className="space-y-2 max-h-60 overflow-y-auto">
                  <div className="bg-amber-50 border border-amber-200 p-2.5 rounded-xl text-xs space-y-1">
                    <p className="font-bold text-amber-800">قراءات ومدفوعات معلقة</p>
                    <p className="text-amber-700 text-[11px]">يوجد {pendingCount} قراءة أو سداد بانتظار اعتماد المحاسب في لوحة التحكم.</p>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        {/* User Info Avatar & Logout Button */}
        <div className="flex items-center gap-2 border-r border-slate-200 pr-3">
          <div className="w-8 h-8 bg-blue-600 border border-blue-500 rounded-xl flex items-center justify-center text-xs font-bold text-white shadow-sm">
            {user?.full_name ? user.full_name.charAt(0) : 'U'}
          </div>

          <button
            onClick={logout}
            className="p-2 text-rose-600 hover:bg-rose-50 border border-transparent hover:border-rose-200 rounded-xl transition-all flex items-center gap-1 text-xs font-bold"
            title="تسجيل الخروج"
          >
            <LogOut size={16} />
            <span className="hidden sm:inline">خروج</span>
          </button>
        </div>
      </div>
    </header>
  );
};

export default Navbar;
