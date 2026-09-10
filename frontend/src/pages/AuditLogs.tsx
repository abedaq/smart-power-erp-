import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAuditLogsApi, type AuditLogItem } from '../services/audit.service';
import { 
  ShieldAlert, 
  RefreshCw, 
  Search, 
  X, 
  User, 
  Clock, 
  Layers, 
  LayoutGrid, 
  List, 
  Filter,
  LogIn,
  LogOut,
  Receipt,
  CheckCheck,
  Zap,
  FileText,
  AlertTriangle,
  UserPlus,
  UserCheck,
  Trash2,
  Edit3,
  Sliders,
  MessageSquare,
  KeyRound,
  Ban,
  PhoneCall,
  Download,
  UploadCloud
} from 'lucide-react';
import { toEnglishDigits } from '../utils/formatters';

export const AuditLogs: React.FC = () => {
  const [page, setPage] = useState(1);
  const [searchTerm, setSearchTerm] = useState('');
  const [actionFilter, setActionFilter] = useState('all');
  const [viewMode, setViewMode] = useState<'cards' | 'table'>('cards');

  const { data, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['audit-logs', page, actionFilter, searchTerm],
    queryFn: () => getAuditLogsApi(page, 40, 'all', actionFilter, searchTerm),
    staleTime: 5000
  });

  const logs: AuditLogItem[] = data?.data || [];
  const meta = data?.meta || { totalPages: 1, total: 0 };

  // Arabic Action Badge Mapper
  const getActionBadge = (action: string) => {
    switch (action) {
      case 'LOGIN':
        return (
          <span className="inline-flex items-center gap-1.5 bg-sky-100 text-sky-950 border-2 border-sky-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <LogIn size={13} className="text-sky-700" />
            تسجيل دخول
          </span>
        );
      case 'LOGOUT':
        return (
          <span className="inline-flex items-center gap-1.5 bg-slate-100 text-slate-800 border-2 border-slate-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <LogOut size={13} className="text-slate-600" />
            تسجيل خروج
          </span>
        );
      case 'CREATE_PAYMENT':
      case 'PAYMENT_CREATE':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-100 text-emerald-950 border-2 border-emerald-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Receipt size={13} className="text-emerald-700" />
            تحصيل سند قبض
          </span>
        );
      case 'PAYMENT_APPROVE':
      case 'APPROVE_PAYMENT':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-700 text-white text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <CheckCheck size={13} />
            اعتماد سند قبض
          </span>
        );
      case 'PAYMENT_REJECT':
      case 'REJECT_PAYMENT':
        return (
          <span className="inline-flex items-center gap-1.5 bg-rose-100 text-rose-950 border-2 border-rose-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Ban size={13} className="text-rose-700" />
            رفض سند قبض
          </span>
        );
      case 'READING_CREATE':
      case 'CREATE_READING':
        return (
          <span className="inline-flex items-center gap-1.5 bg-blue-100 text-blue-950 border-2 border-blue-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Zap size={13} className="text-blue-700" />
            تسجيل قراءة عداد
          </span>
        );
      case 'READING_APPROVE':
      case 'APPROVE_READING':
        return (
          <span className="inline-flex items-center gap-1.5 bg-blue-700 text-white text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <FileText size={13} />
            اعتماد قراءة وفاتورة
          </span>
        );
      case 'READING_REJECT':
      case 'REJECT_READING':
        return (
          <span className="inline-flex items-center gap-1.5 bg-rose-100 text-rose-950 border-2 border-rose-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <AlertTriangle size={13} className="text-rose-700" />
            رفض قراءة عداد
          </span>
        );
      case 'READING_APPROVE_ALL':
      case 'APPROVE_ALL_READINGS':
        return (
          <span className="inline-flex items-center gap-1.5 bg-teal-100 text-teal-950 border-2 border-teal-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <CheckCheck size={13} className="text-teal-700" />
            اعتماد شامل للقراءات
          </span>
        );
      case 'CUSTOMER_CREATE':
      case 'CREATE_CUSTOMER':
        return (
          <span className="inline-flex items-center gap-1.5 bg-purple-100 text-purple-950 border-2 border-purple-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <UserPlus size={13} className="text-purple-700" />
            إضافة مشترك جديد
          </span>
        );
      case 'CUSTOMER_UPDATE':
      case 'UPDATE_CUSTOMER':
        return (
          <span className="inline-flex items-center gap-1.5 bg-amber-100 text-amber-950 border-2 border-amber-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Edit3 size={13} className="text-amber-700" />
            تعديل بيانات مشترك
          </span>
        );
      case 'CUSTOMER_DELETE':
      case 'DELETE_CUSTOMER':
        return (
          <span className="inline-flex items-center gap-1.5 bg-red-100 text-red-950 border-2 border-red-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Trash2 size={13} className="text-red-700" />
            حذف مشترك
          </span>
        );
      case 'GRID_CELL_UPDATE':
      case 'CUSTOMER_GRID_CELL_UPDATE':
        return (
          <span className="inline-flex items-center gap-1.5 bg-indigo-100 text-indigo-950 border-2 border-indigo-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <LayoutGrid size={13} className="text-indigo-700" />
            تعديل فوري بالجدول
          </span>
        );
      case 'CREATE_USER':
        return (
          <span className="inline-flex items-center gap-1.5 bg-purple-100 text-purple-950 border-2 border-purple-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <UserCheck size={13} className="text-purple-700" />
            إضافة مستخدم نظام
          </span>
        );
      case 'UPDATE_USER':
        return (
          <span className="inline-flex items-center gap-1.5 bg-amber-100 text-amber-950 border-2 border-amber-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Edit3 size={13} className="text-amber-700" />
            تعديل صلاحيات مستخدم
          </span>
        );
      case 'RESET_PASSWORD':
        return (
          <span className="inline-flex items-center gap-1.5 bg-rose-100 text-rose-950 border-2 border-rose-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <KeyRound size={13} className="text-rose-700" />
            تغيير كلمة المرور
          </span>
        );
      case 'UPDATE_SETTINGS':
        return (
          <span className="inline-flex items-center gap-1.5 bg-slate-800 text-white text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Sliders size={13} />
            تحديث التعرفة والإعدادات
          </span>
        );
      case 'WHATSAPP_CANCEL_QUEUE':
        return (
          <span className="inline-flex items-center gap-1.5 bg-rose-700 text-white text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Trash2 size={13} />
            إلغاء وتفريغ طابور الواتساب
          </span>
        );
      case 'WHATSAPP_SEND_TEST':
      case 'SEND_TEST_WHATSAPP':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-100 text-emerald-950 border-2 border-emerald-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <MessageSquare size={13} className="text-emerald-700" />
            رسالة واتساب تجريبية
          </span>
        );
      case 'WHATSAPP_RESTART':
      case 'WHATSAPP_LOGOUT':
      case 'WHATSAPP_CONNECT':
        return (
          <span className="inline-flex items-center gap-1.5 bg-indigo-100 text-indigo-950 border-2 border-indigo-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <PhoneCall size={13} className="text-indigo-700" />
            إدارة جلسة الواتساب
          </span>
        );
      case 'IMPORT_READINGS':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-100 text-emerald-950 border-2 border-emerald-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <UploadCloud size={13} className="text-emerald-700" />
            استيراد قراءات Excel
          </span>
        );
      case 'EXPORT_EXCEL':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-100 text-emerald-950 border-2 border-emerald-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Download size={13} className="text-emerald-700" />
            تصدير كشف Excel
          </span>
        );
      case 'NAVIGATE':
      case 'TAB_SWITCH':
        return (
          <span className="inline-flex items-center gap-1.5 bg-slate-100 text-slate-800 border-2 border-slate-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            تنقل في النظام
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1 bg-slate-100 text-slate-800 border-2 border-slate-300 text-xs px-3 py-1 rounded-xl font-black">
            {action}
          </span>
        );
    }
  };

  // Arabic Entity Badge Mapper
  const getEntityBadge = (entity?: string | null, entityId?: string | null) => {
    if (!entity) return null;
    const cleanEntity = entity.toUpperCase().trim();
    let arabicName = cleanEntity;
    let colorClass = 'bg-slate-100 text-slate-800 border-slate-300';

    switch (cleanEntity) {
      case 'CUSTOMER':
        arabicName = 'مشترك';
        colorClass = 'bg-purple-50 text-purple-900 border-purple-200';
        break;
      case 'READING':
        arabicName = 'قراءة عداد';
        colorClass = 'bg-blue-50 text-blue-900 border-blue-200';
        break;
      case 'PAYMENT':
        arabicName = 'سند قبض / سداد';
        colorClass = 'bg-emerald-50 text-emerald-900 border-emerald-200';
        break;
      case 'INVOICE':
        arabicName = 'فاتورة';
        colorClass = 'bg-sky-50 text-sky-900 border-sky-200';
        break;
      case 'USER':
        arabicName = 'مستخدم';
        colorClass = 'bg-indigo-50 text-indigo-900 border-indigo-200';
        break;
      case 'SETTINGS':
        arabicName = 'إعدادات النظام';
        colorClass = 'bg-slate-100 text-slate-900 border-slate-300';
        break;
      case 'WHATSAPP':
        arabicName = 'بوابة الواتساب';
        colorClass = 'bg-emerald-50 text-emerald-900 border-emerald-300';
        break;
      case 'EXCEL':
        arabicName = 'ملف إكسل';
        colorClass = 'bg-emerald-50 text-emerald-900 border-emerald-200';
        break;
    }

    return (
      <span className={`inline-flex items-center gap-1.5 border-2 text-xs px-2.5 py-1 rounded-xl font-mono font-black ${colorClass}`}>
        <Layers size={13} className="text-slate-500" />
        <span>{arabicName}</span>
        {entityId ? ` #${toEnglishDigits(entityId)}` : ''}
      </span>
    );
  };

  const getActionBorderColor = (action: string) => {
    switch (action) {
      case 'PAYMENT_CREATE':
      case 'CREATE_PAYMENT':
      case 'PAYMENT_APPROVE':
      case 'APPROVE_PAYMENT':
        return 'border-r-emerald-600 hover:border-emerald-700';
      case 'READING_CREATE':
      case 'CREATE_READING':
      case 'READING_APPROVE':
      case 'APPROVE_READING':
      case 'READING_APPROVE_ALL':
        return 'border-r-blue-600 hover:border-blue-700';
      case 'CUSTOMER_CREATE':
      case 'CREATE_CUSTOMER':
      case 'CREATE_USER':
        return 'border-r-purple-600 hover:border-purple-700';
      case 'CUSTOMER_UPDATE':
      case 'UPDATE_CUSTOMER':
      case 'UPDATE_USER':
      case 'GRID_CELL_UPDATE':
        return 'border-r-amber-600 hover:border-amber-700';
      case 'CUSTOMER_DELETE':
      case 'DELETE_CUSTOMER':
      case 'RESET_PASSWORD':
      case 'WHATSAPP_CANCEL_QUEUE':
      case 'PAYMENT_REJECT':
      case 'READING_REJECT':
        return 'border-r-rose-600 hover:border-rose-700';
      default:
        return 'border-r-slate-500 hover:border-slate-600';
    }
  };

  // Smart Arabic Details Formatter
  const formatArabicDetails = (details?: string | null) => {
    if (!details) return 'لا توجد تفاصيل إضافية للعملية.';
    let text = details;

    // Handle legacy English patterns
    if (text.includes('User logged in successfully') || text.includes('logged in')) {
      return 'تسجيل دخول ناجح لمستخدم النظام';
    }
    if (text.startsWith('Payment of') && text.includes('allocations')) {
      const match = text.match(/Payment of ([0-9.]+) processed with ([0-9]+) allocations/i);
      if (match) {
        return `تم تحصيل سند قبض وسداد بمبلغ ${toEnglishDigits(match[1])} ريال وتوزيعه آلياً على ${toEnglishDigits(match[2])} فاتورة مستحقة`;
      }
    }

    return toEnglishDigits(text);
  };

  const formatDateTime = (dateStr: string) => {
    try {
      const d = new Date(dateStr);
      if (isNaN(d.getTime())) return dateStr;
      const year = d.getFullYear();
      const month = String(d.getMonth() + 1).padStart(2, '0');
      const day = String(d.getDate()).padStart(2, '0');
      const hours = String(d.getHours()).padStart(2, '0');
      const minutes = String(d.getMinutes()).padStart(2, '0');
      const seconds = String(d.getSeconds()).padStart(2, '0');
      return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    } catch {
      return dateStr;
    }
  };

  const actionFilterOptions = [
    { value: 'all', label: 'كافة الإجراءات' },
    { value: 'CREATE_PAYMENT', label: 'سدادات وتحصيلات' },
    { value: 'READING_CREATE', label: 'قراءات العدادات' },
    { value: 'READING_APPROVE', label: 'اعتماد الفواتير' },
    { value: 'CUSTOMER_UPDATE', label: 'تعديلات المشتركين' },
    { value: 'CUSTOMER_CREATE', label: 'إضافة مشتركين' },
    { value: 'WHATSAPP_CANCEL_QUEUE', label: 'طابور الواتساب' },
    { value: 'LOGIN', label: 'تسجيلات الدخول' },
    { value: 'UPDATE_USER', label: 'إدارة المستخدمين' }
  ];

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header & Main Bar */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4 bg-white p-6 rounded-2xl border-2 border-slate-200/90 shadow-md">
        <div className="flex items-center gap-4">
          <div className="p-3.5 bg-amber-50 text-amber-700 rounded-2xl border-2 border-amber-200 shadow-sm">
            <ShieldAlert size={30} />
          </div>
          <div>
            <h1 className="text-2xl font-black text-slate-900 flex items-center gap-2.5">
              سجل حركة النظام والتدقيق الشامل (Audit Trail)
              <span className="text-xs bg-slate-100 text-slate-800 px-3 py-1 rounded-full border-2 border-slate-300 font-mono font-black shadow-sm">
                {toEnglishDigits(meta.total)} سجل
              </span>
            </h1>
            <p className="text-xs text-slate-600 font-bold mt-1">
              متابعة دقيقة وفورية لكافة تحركات المدير والمحصلين وتعديلات البيانات والعمليات المالية
            </p>
          </div>
        </div>

        {/* View Switch & Refresh */}
        <div className="flex items-center gap-2">
          <div className="bg-slate-100 p-1.5 rounded-2xl flex items-center gap-1.5 border-2 border-slate-200">
            <button
              onClick={() => setViewMode('cards')}
              className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-black transition-all ${
                viewMode === 'cards' 
                  ? 'bg-white text-slate-950 shadow-md border-2 border-slate-200' 
                  : 'text-slate-600 hover:text-slate-950'
              }`}
            >
              <LayoutGrid size={15} />
              <span>عرض البطاقات</span>
            </button>
            <button
              onClick={() => setViewMode('table')}
              className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-black transition-all ${
                viewMode === 'table' 
                  ? 'bg-white text-slate-950 shadow-md border-2 border-slate-200' 
                  : 'text-slate-600 hover:text-slate-950'
              }`}
            >
              <List size={15} />
              <span>جدول تفصيلي</span>
            </button>
          </div>

          <button
            onClick={() => refetch()}
            disabled={isFetching}
            className="flex items-center justify-center gap-2 bg-slate-100 hover:bg-slate-200 text-slate-800 px-5 py-2.5 rounded-xl text-xs font-black transition-all shrink-0 border-2 border-slate-200 shadow-sm"
          >
            <RefreshCw size={15} className={isFetching ? 'animate-spin' : ''} />
            <span>تحديث</span>
          </button>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="bg-white p-5 rounded-2xl border-2 border-slate-200/90 shadow-md flex flex-col md:flex-row items-center gap-3.5">
        {/* Search */}
        <div className="relative flex-1 w-full">
          <Search className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" size={18} />
          <input
            type="text"
            placeholder="ابحث برقم المشترك، اسم المنفذ، الكيان المستهدف، أو تفاصيل العملية..."
            value={searchTerm}
            onChange={e => {
              setSearchTerm(toEnglishDigits(e.target.value));
              setPage(1);
            }}
            className="w-full bg-slate-50 border-2 border-slate-200 rounded-xl pr-11 pl-10 py-3 text-sm font-bold text-slate-900 focus:outline-none focus:border-amber-600 transition-colors shadow-inner"
          />
          {searchTerm && (
            <button
              onClick={() => setSearchTerm('')}
              className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-700"
            >
              <X size={16} />
            </button>
          )}
        </div>

        {/* Action Type Filter */}
        <div className="flex items-center gap-2 w-full md:w-auto overflow-x-auto pb-1 md:pb-0">
          <Filter size={16} className="text-slate-500 shrink-0" />
          <div className="flex gap-2 flex-nowrap">
            {actionFilterOptions.map(opt => (
              <button
                key={opt.value}
                onClick={() => {
                  setActionFilter(opt.value);
                  setPage(1);
                }}
                className={`px-4 py-2.5 rounded-xl text-xs font-black whitespace-nowrap transition-all border-2 ${
                  actionFilter === opt.value
                    ? 'bg-amber-600 text-white border-amber-600 shadow-md'
                    : 'bg-slate-50 text-slate-700 border-slate-200 hover:bg-slate-100 hover:text-slate-950'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Main Content Area */}
      {isLoading ? (
        <div className="bg-white rounded-2xl border-2 border-slate-200 p-12 text-center shadow-md">
          <RefreshCw size={36} className="animate-spin text-amber-600 mx-auto mb-3" />
          <p className="text-base font-black text-slate-800">جاري تحميل سجلات التدقيق الشامل والرقابة...</p>
          <p className="text-xs font-bold text-slate-500 mt-1">يتم استرجاع الحركات من قاعدة البيانات الموحدة</p>
        </div>
      ) : logs.length === 0 ? (
        <div className="bg-white rounded-2xl border-2 border-slate-200 p-12 text-center shadow-md">
          <ShieldAlert size={44} className="text-slate-300 mx-auto mb-3" />
          <p className="text-lg font-black text-slate-900">لا توجد سجلات مطابقة للبحث أو الفلتر</p>
          <p className="text-xs font-bold text-slate-500 mt-1">
            {searchTerm || actionFilter !== 'all' ? 'جرّب إعادة تعيين معايير البحث أو الفلترة' : 'لم يتم تسجيل أي أحداث حتى الآن'}
          </p>
          {(searchTerm || actionFilter !== 'all') && (
            <button
              onClick={() => {
                setSearchTerm('');
                setActionFilter('all');
                setPage(1);
              }}
              className="mt-4 px-5 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-800 rounded-xl text-xs font-black transition-colors border-2 border-slate-200 shadow-sm"
            >
              إعادة ضبط الفلاتر
            </button>
          )}
        </div>
      ) : viewMode === 'cards' ? (
        /* Cards View */
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {logs.map((log) => (
            <div
              key={log.id}
              className={`bg-white rounded-2xl border-2 border-slate-200/90 p-5 shadow-md hover:shadow-lg transition-all border-r-8 ${getActionBorderColor(log.action)} flex flex-col justify-between`}
            >
              {/* Card Header: Action Badge & Time */}
              <div className="flex items-start justify-between gap-3 mb-3.5">
                <div className="flex items-center gap-2 flex-wrap">
                  {getActionBadge(log.action)}
                  {getEntityBadge(log.entity, log.entity_id)}
                </div>
                <span className="flex items-center gap-1.5 font-mono text-xs font-bold text-slate-500 whitespace-nowrap bg-slate-50 px-2.5 py-1 rounded-lg border border-slate-200">
                  <Clock size={13} />
                  {formatDateTime(log.created_at)}
                </span>
              </div>

              {/* Actor User Info */}
              <div className="flex items-center gap-3 mb-3.5 bg-slate-50 p-3 rounded-xl border-2 border-slate-200/80">
                <div className="w-9 h-9 rounded-xl bg-amber-100 text-amber-800 flex items-center justify-center font-bold text-sm shrink-0 shadow-sm">
                  <User size={18} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-xs font-black text-slate-900 truncate">
                      {log.user?.full_name || 'النظام التلقائي (System)'}
                    </p>
                    {log.user?.role && (
                      <span className="text-[11px] bg-slate-200/90 text-slate-800 px-2.5 py-0.5 rounded-lg font-black border border-slate-300">
                        {log.user.role === 'ADMIN' || log.user.role === 'admin' 
                          ? 'مدير النظام' 
                          : log.user.role === 'ACCOUNTANT' || log.user.role === 'accountant' 
                          ? 'محاسب' 
                          : log.user.role === 'COLLECTOR' || log.user.role === 'collector' 
                          ? 'محصل' 
                          : log.user.role}
                      </span>
                    )}
                  </div>
                  {log.user?.username && (
                    <p className="text-[11px] font-mono font-bold text-slate-500 truncate">@{log.user.username}</p>
                  )}
                </div>
              </div>

              {/* Action Details Box */}
              <div className="bg-slate-50 border-2 border-slate-200/80 rounded-xl p-3.5 text-xs font-bold text-slate-900 leading-relaxed min-h-[48px] shadow-inner">
                {formatArabicDetails(log.details)}
              </div>
            </div>
          ))}
        </div>
      ) : (
        /* Compact Table View */
        <div className="bg-white rounded-2xl border-2 border-slate-200/90 shadow-md overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-right border-collapse">
              <thead>
                <tr className="bg-slate-50 border-b-2 border-slate-200 text-slate-700 text-xs font-black">
                  <th className="p-4">الوقت والتاريخ</th>
                  <th className="p-4">المنفذ / المستخدم</th>
                  <th className="p-4">الإجراء</th>
                  <th className="p-4">الكيان المرتبط</th>
                  <th className="p-4">تفاصيل العملية</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 text-sm">
                {logs.map((log) => (
                  <tr key={log.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="p-4 font-mono text-xs font-bold text-slate-600 whitespace-nowrap">
                      {formatDateTime(log.created_at)}
                    </td>
                    <td className="p-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <div className="w-7 h-7 rounded-lg bg-slate-100 text-slate-700 flex items-center justify-center text-xs font-bold border border-slate-200">
                          <User size={14} />
                        </div>
                        <div>
                          <span className="font-black text-slate-900 text-xs block">{log.user ? log.user.full_name : 'النظام'}</span>
                          {log.user?.role && (
                            <span className="text-[10px] text-slate-500 font-bold">
                              {log.user.role === 'ADMIN' || log.user.role === 'admin' ? 'مدير النظام' : log.user.role}
                            </span>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="p-4 whitespace-nowrap">{getActionBadge(log.action)}</td>
                    <td className="p-4 whitespace-nowrap">
                      {getEntityBadge(log.entity, log.entity_id) || '-'}
                    </td>
                    <td className="p-4 text-xs font-bold text-slate-900 leading-relaxed max-w-md">
                      {formatArabicDetails(log.details)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Pagination Controls */}
      {meta.totalPages > 1 && (
        <div className="bg-white p-4 rounded-2xl border-2 border-slate-200/90 shadow-md flex flex-col sm:flex-row items-center justify-between gap-3">
          <span className="text-xs text-slate-600 font-bold">
            صفحة <span className="font-black text-slate-900 font-mono text-sm">{toEnglishDigits(page)}</span> من <span className="font-black text-slate-900 font-mono text-sm">{toEnglishDigits(meta.totalPages)}</span> (إجمالي <span className="font-black text-slate-900 font-mono text-sm">{toEnglishDigits(meta.total)}</span> سجلاً)
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setPage(p => Math.max(1, p - 1))}
              disabled={page === 1}
              className="px-5 py-2.5 bg-slate-100 hover:bg-slate-200 disabled:opacity-40 text-xs font-black text-slate-800 rounded-xl transition-all border-2 border-slate-200 shadow-sm"
            >
              السابق
            </button>
            <div className="flex items-center gap-1 font-mono text-xs">
              {[...Array(Math.min(5, meta.totalPages))].map((_, i) => {
                const pNum = i + 1;
                return (
                  <button
                    key={pNum}
                    onClick={() => setPage(pNum)}
                    className={`w-9 h-9 rounded-xl font-black transition-all border-2 ${
                      page === pNum 
                        ? 'bg-amber-600 text-white border-amber-600 shadow-md' 
                        : 'bg-slate-50 hover:bg-slate-100 text-slate-700 border-slate-200'
                    }`}
                  >
                    {toEnglishDigits(pNum)}
                  </button>
                );
              })}
              {meta.totalPages > 5 && <span className="text-slate-400 px-1 font-black">...</span>}
            </div>
            <button
              onClick={() => setPage(p => Math.min(meta.totalPages, p + 1))}
              disabled={page === meta.totalPages}
              className="px-5 py-2.5 bg-slate-100 hover:bg-slate-200 disabled:opacity-40 text-xs font-black text-slate-800 rounded-xl transition-all border-2 border-slate-200 shadow-sm"
            >
              التالي
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default AuditLogs;

