import React, { useState, useEffect } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { LayoutDashboard, FileText, Settings, X, PanelRightClose, AlertTriangle } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';
import api from '../lib/api';

interface SidebarProps {
  isOpen?: boolean;
  onClose?: () => void;
  isCollapsed?: boolean;
  onToggleCollapse?: () => void;
}

const Sidebar: React.FC<SidebarProps> = ({ 
  isOpen = false, 
  onClose, 
  isCollapsed = false, 
  onToggleCollapse
}) => {
  const location = useLocation();
  const { user } = useAuth();
  const [mobileUrl, setMobileUrl] = useState<string>(() => {
    const host = window.location.hostname || '127.0.0.1';
    const port = window.location.port || '3000';
    return `http://${host}:${port}`;
  });

  useEffect(() => {
    let isMounted = true;
    api.get('/system/network-info').then((res) => {
      if (!isMounted) return;
      const data = res.data;
      if (data && data.success) {
        const port = data.port || '3000';
        const detectedAdapters = data.adapters || [];
        const hotspot = detectedAdapters.find((a: any) => a.ip === '192.168.137.1' || a.type === 'hotspot');
        const wifi = detectedAdapters.find((a: any) => a.type === 'wifi');
        let chosenIP = data.local_ip || window.location.hostname || '127.0.0.1';
        if (hotspot) {
          chosenIP = hotspot.ip;
        } else if (wifi) {
          chosenIP = wifi.ip;
        } else if (detectedAdapters.length > 0) {
          chosenIP = detectedAdapters[0].ip;
        }
        setMobileUrl(`http://${chosenIP}:${port}`);
      }
    }).catch(() => {});
    return () => { isMounted = false; };
  }, []);

  interface NavLinkItem {
    to: string;
    label: string;
    icon: any;
    badge?: number;
  }

  const role = user?.role || 'COLLECTOR';

  let links: NavLinkItem[] = [];
  if (role === 'ADMIN') {
    links = [
      { to: '/', label: 'الرئيسية والمتابعة', icon: LayoutDashboard },
      { to: '/invoices', label: 'الفواتير والتحصيل الميداني', icon: FileText },
      { to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle },
      { to: '/settings', label: 'الإعدادات والتهيئة', icon: Settings },
    ];
  } else if (role === 'ACCOUNTANT' || role === 'CASHIER') {
    links = [
      { to: '/invoices', label: 'الفواتير وسندات القبض', icon: FileText },
      { to: '/arrears', label: 'المديونيات والمتأخرات', icon: AlertTriangle },
    ];
  } else {
    // COLLECTOR
    links = [
      { to: '/invoices', label: 'الفواتير والتحصيل الميداني', icon: FileText },
    ];
  }

  return (
    <>
      {/* Mobile Backdrop Overlay */}
      {isOpen && (
        <div 
          onClick={onClose}
          className="md:hidden fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-40 transition-opacity"
        />
      )}

      {/* Sidebar Container */}
      <div 
        className={`fixed md:static inset-y-0 right-0 z-50 bg-white border-l border-slate-200 flex flex-col transition-all duration-300 ease-in-out shadow-sm ${
          isOpen
            ? 'translate-x-0 w-72 opacity-100'
            : 'max-md:translate-x-full max-md:w-0 max-md:opacity-0 max-md:overflow-hidden'
        } ${
          isCollapsed
            ? 'md:w-0 md:opacity-0 md:overflow-hidden md:border-0 md:translate-x-full'
            : 'md:w-72 md:opacity-100 md:translate-x-0'
        }`}
      >
        {/* Sidebar Header */}
        <div className="h-16 flex items-center justify-between px-4 border-b border-slate-200 bg-slate-50/80 shrink-0">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-blue-600 flex items-center justify-center font-bold text-white shadow-md shadow-blue-500/20">
              ⚡
            </div>
            <div>
              <h1 className="text-base font-bold text-slate-900">Smart Power ERP</h1>
              <p className="text-[10px] text-slate-500">نظام إدارة الكهرباء والتحصيل</p>
            </div>
          </div>

          <div className="flex items-center gap-1">
            {/* Collapse button on Desktop */}
            <button
              onClick={onToggleCollapse}
              className="hidden md:flex p-2 text-slate-500 hover:text-slate-900 rounded-xl hover:bg-slate-200 transition-colors"
              title="طي القائمة الجانبية وتوسيع الشاشة"
            >
              <PanelRightClose size={18} />
            </button>

            {/* Mobile close button */}
            {onClose && (
              <button 
                onClick={onClose}
                className="md:hidden p-2 text-slate-400 hover:text-slate-900 rounded-xl hover:bg-slate-100 transition-colors"
              >
                <X size={20} />
              </button>
            )}
          </div>
        </div>

        {/* Navigation Links */}
        <nav className="flex-1 p-4 space-y-2 overflow-y-auto">
          {links.map((link) => {
            const Icon = link.icon;
            const isActive = location.pathname === link.to;
            return (
              <Link
                key={link.to}
                to={link.to}
                onClick={onClose}
                className={`flex items-center justify-between px-4 py-3.5 rounded-xl transition-all ${
                  isActive 
                    ? 'bg-blue-600 text-white font-black shadow-md shadow-blue-500/25 border-2 border-blue-600' 
                    : 'text-slate-800 hover:bg-slate-100 hover:text-slate-950 font-bold border-2 border-transparent'
                }`}
              >
                <div className="flex items-center gap-3">
                  <Icon size={22} className={isActive ? 'text-white' : 'text-slate-600'} />
                  <span className="text-sm font-black whitespace-nowrap">{link.label}</span>
                </div>
                {link.badge !== undefined && link.badge > 0 && (
                  <span className={`px-2.5 py-0.5 text-xs font-mono font-black rounded-lg border ${
                    isActive ? 'bg-white/25 text-white border-white/40' : 'bg-amber-100 text-amber-900 border-amber-300'
                  }`}>
                    {link.badge}
                  </span>
                )}
              </Link>
            );
          })}
        </nav>

        {/* Direct Embedded Mobile QR Code */}
        <div className="p-3 border-t border-slate-200 bg-slate-50/80 flex flex-col items-center justify-center shrink-0">
          <div className="p-2 bg-white rounded-2xl shadow-sm border border-slate-200/80">
            <QRCodeSVG 
              value={mobileUrl} 
              size={135} 
              level="M" 
              includeMargin={false}
            />
          </div>
          <span className="text-[10px] text-slate-500 font-mono mt-1.5 font-bold tracking-tight" dir="ltr">
            {mobileUrl.replace('http://', '')}
          </span>
        </div>
      </div>
    </>
  );
};

export default Sidebar;
