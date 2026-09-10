import React, { useState } from 'react';
import { 
  QrCode, 
  RefreshCcw, 
  RefreshCw, 
  CheckCircle, 
  AlertCircle, 
  Smartphone, 
  Send, 
  Power, 
  LogOut,
  MessageSquare,
  Clock,
  Search,
  Filter,
  CheckCheck,
  AlertTriangle,
  Receipt,
  FileText,
  ShieldAlert,
  ChevronDown,
  ChevronUp,
  X,
  Radio,
  Trash2,
  RotateCcw,
  Copy,
  Check,
  Inbox,
  SendHorizontal
} from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useDebouncedRealtime } from '../utils/debouncedRealtime';
import { 
  getWhatsAppStatus, 
  getWhatsAppMessages, 
  sendTestWhatsAppMessage, 
  restartWhatsApp, 
  logoutWhatsApp,
  clearPendingWhatsAppQueue,
  deleteWhatsAppMessageApi,
  retryWhatsAppMessageApi,
  retryAllWhatsAppQueueApi,
  clearAllWhatsAppMessagesApi
} from '../lib/api';
import { toEnglishDigits } from '../utils/formatters';

interface WhatsAppMessage {
  id: number;
  phone_number: string;
  message: string;
  type?: string;
  status: 'PENDING' | 'QUEUED' | 'SENT' | 'FAILED' | 'DELIVERED';
  attempts?: number;
  source_entity?: string;
  created_at: string;
  sent_at?: string;
  error_message?: string;
}

export const WhatsApp: React.FC = () => {
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<'queue' | 'sent' | 'gateway'>('queue');
  
  // Feedback alert banner
  const [feedback, setFeedback] = useState<{ type: 'success' | 'error' | 'info'; text: string } | null>(null);
  const [copiedId, setCopiedId] = useState<number | null>(null);

  // Gateway Tab State
  const [testNumber, setTestNumber] = useState('');
  const [testMessage, setTestMessage] = useState('رسالة تجريبية من نظام Smart Power ERP');

  // Queue Tab State
  const [queuePage, setQueuePage] = useState(1);
  const [queueSearch, setQueueSearch] = useState('');
  const [queueTypeFilter, setQueueTypeFilter] = useState('all');
  const [queueStatusFilter, setQueueStatusFilter] = useState('all'); // all, PENDING, QUEUED, FAILED
  const [expandedQueueId, setExpandedQueueId] = useState<number | null>(null);

  // Sent Tab State
  const [sentPage, setSentPage] = useState(1);
  const [sentSearch, setSentSearch] = useState('');
  const [sentTypeFilter, setSentTypeFilter] = useState('all');
  const [expandedSentId, setExpandedSentId] = useState<number | null>(null);

  // Realtime Event-Driven Subscriptions (Replaces Polling)
  useDebouncedRealtime([
    {
      channelName: 'whatsapp_page:status',
      table: 'whatsapp_sessions',
      queryKeysToInvalidate: [['whatsapp-status']],
      debounceMs: 400,
    },
    {
      channelName: 'whatsapp_page:queue',
      table: 'whatsapp_queue_messages',
      queryKeysToInvalidate: [
        ['whatsapp-queue'],
        ['whatsapp-sent'],
        ['whatsapp-status']
      ],
      debounceMs: 500,
    },
  ]);

  // Queries
  const { data: statusData, refetch: refetchStatus, isFetching: isFetchingStatus } = useQuery({
    queryKey: ['whatsapp-status'],
    queryFn: getWhatsAppStatus,
    staleTime: 60000
  });

  // Query for Queue Messages (PENDING, QUEUED, FAILED)
  const effectiveQueueStatus = queueStatusFilter === 'all' ? 'queue' : queueStatusFilter;
  const { data: queueData, refetch: refetchQueue, isFetching: isFetchingQueue } = useQuery({
    queryKey: ['whatsapp-queue', queuePage, queueTypeFilter, effectiveQueueStatus, queueSearch],
    queryFn: () => getWhatsAppMessages(queuePage, 30, queueTypeFilter, effectiveQueueStatus, queueSearch),
    staleTime: 60000
  });

  // Query for Sent Messages (SENT, DELIVERED)
  const { data: sentData, refetch: refetchSent, isFetching: isFetchingSent } = useQuery({
    queryKey: ['whatsapp-sent', sentPage, sentTypeFilter, sentSearch],
    queryFn: () => getWhatsAppMessages(sentPage, 30, sentTypeFilter, 'sent', sentSearch),
    staleTime: 60000
  });

  const connectionStatus = statusData?.status || statusData?.data?.status || 'SCAN_QR_CODE';
  const qrImage = statusData?.qr || statusData?.data?.qr || null;

  const queueMessages: WhatsAppMessage[] = queueData?.data || [];
  const queueMeta = queueData?.meta || { totalPages: 1, total: 0 };

  const sentMessages: WhatsAppMessage[] = sentData?.data || [];
  const sentMeta = sentData?.meta || { totalPages: 1, total: 0 };

  // Mutations
  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ['whatsapp-queue'] });
    queryClient.invalidateQueries({ queryKey: ['whatsapp-sent'] });
    queryClient.invalidateQueries({ queryKey: ['whatsapp-status'] });
  };

  const testMutation = useMutation({
    mutationFn: ({ number, message }: { number: string; message: string }) =>
      sendTestWhatsAppMessage(number, message),
    onSuccess: () => {
      setFeedback({ type: 'success', text: 'تمت إضافة الرسالة بنجاح لطابور الإرسال!' });
      setTestNumber('');
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشل إرسال رسالة الاختبار' });
    }
  });

  const restartMutation = useMutation({
    mutationFn: restartWhatsApp,
    onSuccess: () => {
      setFeedback({ type: 'success', text: 'تمت إعادة تهيئة الخدمة وتوليد رمز QR جديد.' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشل إعادة التهيئة' });
    }
  });

  const logoutMutation = useMutation({
    mutationFn: logoutWhatsApp,
    onSuccess: () => {
      setFeedback({ type: 'success', text: 'تم تسجيل الخروج من الجلسة بنجاح.' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشل تسجيل الخروج' });
    }
  });

  const clearQueueMutation = useMutation({
    mutationFn: clearPendingWhatsAppQueue,
    onSuccess: (res: any) => {
      setFeedback({ type: 'success', text: res?.message || 'تم تفريغ وإلغاء طابور الإرسال بنجاح!' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشل تفريغ طابور الإرسال' });
    }
  });

  const retrySingleMutation = useMutation({
    mutationFn: (id: number) => retryWhatsAppMessageApi(id),
    onSuccess: (res: any) => {
      setFeedback({ type: 'success', text: res?.message || 'تمت إعادة محاولة إرسال الرسالة بنجاح' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشلت إعادة محاولة الإرسال' });
    }
  });

  const deleteSingleMutation = useMutation({
    mutationFn: (id: number) => deleteWhatsAppMessageApi(id),
    onSuccess: (res: any) => {
      setFeedback({ type: 'success', text: res?.message || 'تم حذف الرسالة بنجاح' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشل حذف الرسالة' });
    }
  });

  const retryAllMutation = useMutation({
    mutationFn: retryAllWhatsAppQueueApi,
    onSuccess: (res: any) => {
      setFeedback({ type: 'success', text: res?.message || 'تمت إعادة جدولة جميع الرسائل المعلقة والفاشلة بنجاح!' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشلت إعادة جدولة الطابور' });
    }
  });

  const clearAllMutation = useMutation({
    mutationFn: clearAllWhatsAppMessagesApi,
    onSuccess: (res: any) => {
      setFeedback({ type: 'success', text: res?.message || 'تم مسح كافة سجلات الرسائل بنجاح' });
      invalidateAll();
    },
    onError: (err: any) => {
      setFeedback({ type: 'error', text: err.response?.data?.message || 'فشل مسح السجلات' });
    }
  });

  const handleSendTest = (e: React.FormEvent) => {
    e.preventDefault();
    const normalizedNumber = testNumber.trim().replace(/\s+/g, '');

    if (!/^(?:7\d{8}|\+?\d{10,15})$/.test(normalizedNumber)) {
      setFeedback({ type: 'error', text: 'يرجى إدخال رقم هاتف يمني صالح (مثل 771234567) أو رقم دولي.' });
      return;
    }

    if (connectionStatus !== 'CONNECTED' && connectionStatus !== 'READY') {
      setFeedback({ type: 'error', text: 'تنبيه: لا يمكن الإرسال الفوري قبل ربط واتساب وتأكيد الاتصال، ولكن سيتم وضعها في الطابور.' });
    }

    testMutation.mutate({ number: normalizedNumber, message: testMessage });
  };

  const handleCopyText = (id: number, text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const formatDateTime = (dateStr?: string) => {
    if (!dateStr) return '-';
    try {
      const d = new Date(dateStr);
      if (isNaN(d.getTime())) return dateStr;
      const year = d.getFullYear();
      const month = String(d.getMonth() + 1).padStart(2, '0');
      const day = String(d.getDate()).padStart(2, '0');
      const hours = String(d.getHours()).padStart(2, '0');
      const minutes = String(d.getMinutes()).padStart(2, '0');
      const seconds = String(d.getSeconds()).padStart(2, '0');
      return toEnglishDigits(`${year}-${month}-${day} ${hours}:${minutes}:${seconds}`);
    } catch {
      return dateStr;
    }
  };

  const formatDisplayPhone = (rawPhone: string) => {
    if (!rawPhone) return '';
    let p = rawPhone.replace(/\D/g, '');
    if (p.startsWith('967') && p.length === 12) {
      return toEnglishDigits(p.substring(3));
    }
    return toEnglishDigits(p);
  };

  const getTypeBadge = (type?: string) => {
    switch (type) {
      case 'INVOICE':
        return (
          <span className="inline-flex items-center gap-1.5 bg-blue-100 text-blue-900 border-2 border-blue-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <FileText size={13} />
            فاتورة استهلاك
          </span>
        );
      case 'RECEIPT':
      case 'PAYMENT':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-100 text-emerald-900 border-2 border-emerald-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Receipt size={13} />
            سند سداد مالي
          </span>
        );
      case 'WARNING':
      case 'DISCONNECTION':
        return (
          <span className="inline-flex items-center gap-1.5 bg-rose-100 text-rose-900 border-2 border-rose-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <ShieldAlert size={13} />
            إنذار فصل
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1.5 bg-purple-100 text-purple-900 border-2 border-purple-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <MessageSquare size={13} />
            إشعار / تجريبي
          </span>
        );
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'SENT':
      case 'DELIVERED':
        return (
          <span className="inline-flex items-center gap-1.5 bg-emerald-50 text-emerald-900 border-2 border-emerald-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <CheckCheck size={14} className="text-emerald-700" />
            تم الإرسال بنجاح
          </span>
        );
      case 'QUEUED':
      case 'PENDING':
        return (
          <span className="inline-flex items-center gap-1.5 bg-amber-50 text-amber-900 border-2 border-amber-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <Clock size={14} className="text-amber-700 animate-pulse" />
            في طابور الإرسال
          </span>
        );
      case 'FAILED':
        return (
          <span className="inline-flex items-center gap-1.5 bg-red-50 text-red-900 border-2 border-red-300 text-xs px-3 py-1 rounded-xl font-black shadow-sm">
            <AlertTriangle size={14} className="text-red-700" />
            تعثر الإرسال
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1.5 bg-slate-100 text-slate-700 border-2 border-slate-300 text-xs px-3 py-1 rounded-xl font-bold">
            {status}
          </span>
        );
    }
  };

  return (
    <div className="space-y-6 max-w-7xl mx-auto p-4 sm:p-6" dir="rtl">
      {/* Header Banner */}
      <div className="bg-gradient-to-l from-slate-900 via-emerald-950 to-slate-900 text-white p-6 sm:p-8 rounded-3xl shadow-xl border border-emerald-500/20 relative overflow-hidden">
        <div className="absolute top-0 right-0 w-96 h-96 bg-emerald-500/10 rounded-full blur-3xl -mr-20 -mt-20 pointer-events-none" />
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 relative z-10">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-500/20 border border-emerald-400/30 text-emerald-300 text-xs font-black">
              <Radio size={14} className="animate-pulse" />
              بوابة وخادم إرسال رسائل الواتساب
            </div>
            <h1 className="text-2xl sm:text-3xl font-black tracking-tight text-white">
              إدارة الإرسال وطابور رسائل الواتساب
            </h1>
            <p className="text-slate-300 text-sm max-w-2xl font-medium leading-relaxed">
              تحكم كامل في طابور الإرسال التلقائي، إعادة المحاولة، مسح السجلات، واستعراض كافة الفواتير وسندات السداد والإنذارات المرسلة للمشتركين.
            </p>
          </div>

          {/* Connection Status Badge */}
          <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3 bg-white/10 backdrop-blur-md p-4 rounded-2xl border border-white/15">
            <div className="flex items-center gap-3">
              {connectionStatus === 'CONNECTED' || connectionStatus === 'READY' ? (
                <div className="w-10 h-10 rounded-xl bg-emerald-500/20 border border-emerald-400/40 flex items-center justify-center text-emerald-400">
                  <CheckCircle size={22} className="animate-pulse" />
                </div>
              ) : connectionStatus === 'RECONNECTING' || connectionStatus === 'CONNECTING' ? (
                <div className="w-10 h-10 rounded-xl bg-blue-500/20 border border-blue-400/40 flex items-center justify-center text-blue-400">
                  <RefreshCw size={22} className="animate-spin" />
                </div>
              ) : connectionStatus === 'SCAN_QR_CODE' ? (
                <div className="w-10 h-10 rounded-xl bg-amber-500/20 border border-amber-400/40 flex items-center justify-center text-amber-400">
                  <QrCode size={22} className="animate-bounce" />
                </div>
              ) : (
                <div className="w-10 h-10 rounded-xl bg-red-500/20 border border-red-400/40 flex items-center justify-center text-red-400">
                  <Power size={22} />
                </div>
              )}
              <div>
                <div className="text-xs text-slate-400 font-bold">حالة الجلسة الآن</div>
                <div className="font-black text-sm text-white">
                  {connectionStatus === 'CONNECTED' || connectionStatus === 'READY'
                    ? 'متصل وجاهز للإرسال'
                    : connectionStatus === 'RECONNECTING' || connectionStatus === 'CONNECTING'
                    ? 'جارٍ استعادة الاتصال...'
                    : connectionStatus === 'SCAN_QR_CODE'
                    ? 'بانتظار مسح الرمز QR'
                    : 'غير متصل'}
                </div>
              </div>
            </div>

            <button
              onClick={() => setActiveTab('gateway')}
              className="px-3.5 py-2 rounded-xl bg-white/20 hover:bg-white/30 text-white font-black text-xs transition flex items-center justify-center gap-1.5 border border-white/20 shadow-sm"
            >
              <Smartphone size={14} />
              إعدادات الربط
            </button>
          </div>
        </div>
      </div>

      {/* Global Feedback Toast */}
      {feedback && (
        <div
          className={`p-4 rounded-2xl border-2 flex items-center justify-between gap-3 shadow-md animate-fade-in ${
            feedback.type === 'success'
              ? 'bg-emerald-50 border-emerald-400 text-emerald-950 font-bold'
              : feedback.type === 'error'
              ? 'bg-rose-50 border-rose-400 text-rose-950 font-bold'
              : 'bg-blue-50 border-blue-400 text-blue-950 font-bold'
          }`}
        >
          <div className="flex items-center gap-3">
            {feedback.type === 'success' ? (
              <CheckCircle className="text-emerald-700 shrink-0" size={20} />
            ) : feedback.type === 'error' ? (
              <AlertCircle className="text-rose-700 shrink-0" size={20} />
            ) : (
              <Radio className="text-blue-700 shrink-0" size={20} />
            )}
            <span className="text-sm">{feedback.text}</span>
          </div>
          <button
            onClick={() => setFeedback(null)}
            className="p-1 hover:bg-black/5 rounded-lg text-slate-500 hover:text-slate-800"
          >
            <X size={16} />
          </button>
        </div>
      )}

      {/* Main 3 Navigation Tabs */}
      <div className="flex border-b-2 border-slate-200 bg-white p-2 rounded-2xl shadow-sm gap-2">
        <button
          onClick={() => setActiveTab('queue')}
          className={`flex-1 py-3.5 px-4 rounded-xl font-black text-sm sm:text-base flex items-center justify-center gap-2.5 transition-all relative ${
            activeTab === 'queue'
              ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30'
              : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <Clock size={18} />
          <span>طابور الإرسال والعمليات المعلقة</span>
          {queueMeta.total > 0 && (
            <span
              className={`text-xs px-2.5 py-0.5 rounded-full font-black ${
                activeTab === 'queue'
                  ? 'bg-white text-emerald-800'
                  : 'bg-amber-100 text-amber-900 border border-amber-300'
              }`}
            >
              {toEnglishDigits(queueMeta.total)}
            </span>
          )}
        </button>

        <button
          onClick={() => setActiveTab('sent')}
          className={`flex-1 py-3.5 px-4 rounded-xl font-black text-sm sm:text-base flex items-center justify-center gap-2.5 transition-all relative ${
            activeTab === 'sent'
              ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30'
              : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <CheckCheck size={18} />
          <span>سجل الرسائل المرسلة</span>
          {sentMeta.total > 0 && (
            <span
              className={`text-xs px-2.5 py-0.5 rounded-full font-black ${
                activeTab === 'sent'
                  ? 'bg-white text-emerald-800'
                  : 'bg-slate-200 text-slate-800'
              }`}
            >
              {toEnglishDigits(sentMeta.total)}
            </span>
          )}
        </button>

        <button
          onClick={() => setActiveTab('gateway')}
          className={`flex-1 py-3.5 px-4 rounded-xl font-black text-sm sm:text-base flex items-center justify-center gap-2.5 transition-all ${
            activeTab === 'gateway'
              ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30'
              : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <Smartphone size={18} />
          <span>ربط الجهاز وجلسة الواتساب</span>
        </button>
      </div>

      {/* ========================================================================= */}
      {/* TAB 1: طابور الإرسال والعمليات المعلقة (Queue & Outbox) */}
      {/* ========================================================================= */}
      {activeTab === 'queue' && (
        <div className="space-y-6">
          {/* Controls & Filter Bar */}
          <div className="bg-white p-5 rounded-3xl border-2 border-slate-200 shadow-sm space-y-4">
            <div className="flex flex-col lg:flex-row items-stretch lg:items-center justify-between gap-4">
              {/* Search Box */}
              <div className="relative flex-1">
                <Search size={18} className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  type="text"
                  placeholder="ابحث برقم الهاتف (مثال: 773245776)، نص الرسالة، أو رقم المشترك..."
                  value={queueSearch}
                  onChange={(e) => {
                    setQueueSearch(e.target.value);
                    setQueuePage(1);
                  }}
                  className="w-full pl-4 pr-11 py-3 bg-slate-50 border-2 border-slate-200 rounded-2xl text-sm font-bold text-slate-800 focus:outline-none focus:border-emerald-500 focus:bg-white transition"
                />
              </div>

              {/* Status Filter */}
              <div className="flex items-center gap-2">
                <Filter size={16} className="text-slate-500 shrink-0" />
                <select
                  value={queueStatusFilter}
                  onChange={(e) => {
                    setQueueStatusFilter(e.target.value);
                    setQueuePage(1);
                  }}
                  className="px-3.5 py-2.5 bg-slate-50 border-2 border-slate-200 rounded-xl text-xs sm:text-sm font-bold text-slate-800 focus:outline-none focus:border-emerald-500"
                >
                  <option value="all">كافة المعلقة والفاشلة</option>
                  <option value="PENDING">في الانتظار (PENDING)</option>
                  <option value="QUEUED">في الطابور (QUEUED)</option>
                  <option value="FAILED">تعثر الإرسال (FAILED)</option>
                </select>

                {/* Type Filter */}
                <select
                  value={queueTypeFilter}
                  onChange={(e) => {
                    setQueueTypeFilter(e.target.value);
                    setQueuePage(1);
                  }}
                  className="px-3.5 py-2.5 bg-slate-50 border-2 border-slate-200 rounded-xl text-xs sm:text-sm font-bold text-slate-800 focus:outline-none focus:border-emerald-500"
                >
                  <option value="all">كافة الأنواع</option>
                  <option value="INVOICE">فواتير استهلاك</option>
                  <option value="RECEIPT">سندات سداد</option>
                  <option value="WARNING">إنذارات فصل</option>
                  <option value="CUSTOM">إشعارات عامة</option>
                </select>
              </div>

              {/* Bulk Queue Actions */}
              <div className="flex flex-wrap items-center gap-2">
                <button
                  onClick={() => refetchQueue()}
                  disabled={isFetchingQueue}
                  className="px-3.5 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold rounded-xl text-xs transition flex items-center gap-1.5 border border-slate-300"
                  title="تحديث القائمة"
                >
                  <RefreshCw size={14} className={isFetchingQueue ? 'animate-spin' : ''} />
                  <span>تحديث</span>
                </button>

                <button
                  onClick={() => {
                    if (window.confirm('هل تريد بالتأكيد إعادة جدولة ومحاولة إرسال كافة الرسائل المعلقة والفاشلة الآن؟')) {
                      retryAllMutation.mutate();
                    }
                  }}
                  disabled={retryAllMutation.isPending || queueMessages.length === 0}
                  className="px-4 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white font-black rounded-xl text-xs transition flex items-center gap-1.5 shadow-sm disabled:opacity-50"
                >
                  <RotateCcw size={14} className={retryAllMutation.isPending ? 'animate-spin' : ''} />
                  <span>إعادة محاولة الكل ({toEnglishDigits(queueMeta.total)})</span>
                </button>

                <button
                  onClick={() => {
                    if (window.confirm('تحذير: هل أنت متأكد من تفريغ وإلغاء كافة الرسائل المعلقة في الطابور؟ لن يتم إرسالها.')) {
                      clearQueueMutation.mutate();
                    }
                  }}
                  disabled={clearQueueMutation.isPending || queueMessages.length === 0}
                  className="px-4 py-2.5 bg-rose-50 hover:bg-rose-100 text-rose-700 border-2 border-rose-300 font-black rounded-xl text-xs transition flex items-center gap-1.5 disabled:opacity-50"
                >
                  <Trash2 size={14} className={clearQueueMutation.isPending ? 'animate-spin' : ''} />
                  <span>تفريغ الطابور</span>
                </button>
              </div>
            </div>
          </div>

          {/* Queue Messages List */}
          {queueMessages.length === 0 ? (
            <div className="bg-white rounded-3xl p-12 text-center border-2 border-dashed border-slate-300 shadow-sm">
              <div className="w-16 h-16 bg-emerald-50 border-2 border-emerald-200 rounded-3xl flex items-center justify-center mx-auto text-emerald-600 mb-4 shadow-sm">
                <CheckCircle size={32} />
              </div>
              <h3 className="text-lg font-black text-slate-800 mb-1">
                طابور الإرسال فارغ تماماً
              </h3>
              <p className="text-slate-500 text-sm max-w-md mx-auto">
                لا توجد رسائل معلقة أو متعثرة في الطابور حالياً. كافة العمليات والفواتير تم إرسالها بنجاح أو لم يتم إنشاء مهام إرسال جديدة.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {queueMessages.map((msg) => {
                const isExpanded = expandedQueueId === msg.id;
                const isRetrying = retrySingleMutation.isPending && retrySingleMutation.variables === msg.id;
                const isDeleting = deleteSingleMutation.isPending && deleteSingleMutation.variables === msg.id;

                return (
                  <div
                    key={msg.id}
                    className={`bg-white rounded-2xl border-2 transition-all overflow-hidden ${
                      msg.status === 'FAILED'
                        ? 'border-red-200 bg-red-50/20'
                        : 'border-slate-200 hover:border-emerald-300'
                    } shadow-sm`}
                  >
                    <div className="p-4 sm:p-5 flex flex-col md:flex-row md:items-center justify-between gap-4">
                      {/* Left / Info Side */}
                      <div className="flex items-start gap-3.5 flex-1 min-w-0">
                        <div
                          className={`w-11 h-11 rounded-2xl flex items-center justify-center shrink-0 border-2 ${
                            msg.status === 'FAILED'
                              ? 'bg-red-100 border-red-300 text-red-700'
                              : 'bg-amber-100 border-amber-300 text-amber-800'
                          }`}
                        >
                          {msg.status === 'FAILED' ? (
                            <AlertTriangle size={20} />
                          ) : (
                            <Clock size={20} className="animate-pulse" />
                          )}
                        </div>

                        <div className="space-y-1.5 flex-1 min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            {getTypeBadge(msg.type)}
                            {getStatusBadge(msg.status)}
                            <span className="text-xs font-mono font-bold text-slate-500 bg-slate-100 px-2.5 py-0.5 rounded-lg">
                              #{toEnglishDigits(msg.id)}
                            </span>
                            {msg.attempts !== undefined && msg.attempts > 0 && (
                              <span className="text-xs font-bold text-slate-600 bg-slate-100 px-2 py-0.5 rounded-md">
                                محاولات: {toEnglishDigits(msg.attempts)}
                              </span>
                            )}
                          </div>

                          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
                            <span className="font-black text-slate-900 font-mono tracking-wide">
                              {formatDisplayPhone(msg.phone_number)}
                            </span>
                            {msg.source_entity && (
                              <span className="text-xs font-bold text-emerald-800 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded-lg">
                                {msg.source_entity}
                              </span>
                            )}
                            <span className="text-xs text-slate-400 font-medium">
                              أُضيفت: {formatDateTime(msg.created_at)}
                            </span>
                          </div>

                          {/* Error Message Snippet if failed */}
                          {msg.error_message && (
                            <div className="text-xs font-bold text-red-700 bg-red-100/70 border border-red-300 px-3 py-1.5 rounded-xl inline-block">
                              سبب التعثر: {msg.error_message}
                            </div>
                          )}
                        </div>
                      </div>

                      {/* Right / Actions Side */}
                      <div className="flex items-center gap-2 self-end md:self-center">
                        <button
                          onClick={() => setExpandedQueueId(isExpanded ? null : msg.id)}
                          className="px-3 py-2 text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 rounded-xl text-xs font-bold transition flex items-center gap-1"
                        >
                          {isExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                          <span>{isExpanded ? 'إخفاء النص' : 'معاينة النص'}</span>
                        </button>

                        <button
                          onClick={() => retrySingleMutation.mutate(msg.id)}
                          disabled={isRetrying}
                          className="px-3.5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-xs font-black transition flex items-center gap-1.5 shadow-sm disabled:opacity-50"
                          title="إعادة محاولة الإرسال الفوري"
                        >
                          <RotateCcw size={13} className={isRetrying ? 'animate-spin' : ''} />
                          <span>إعادة المحاولة</span>
                        </button>

                        <button
                          onClick={() => {
                            if (window.confirm('هل تريد بالتأكيد حذف هذه الرسالة من طابور الإرسال؟')) {
                              deleteSingleMutation.mutate(msg.id);
                            }
                          }}
                          disabled={isDeleting}
                          className="p-2 text-rose-600 hover:bg-rose-50 border border-transparent hover:border-rose-200 rounded-xl transition disabled:opacity-50"
                          title="حذف الرسالة من الطابور"
                        >
                          <Trash2 size={16} />
                        </button>
                      </div>
                    </div>

                    {/* Expandable Text View */}
                    {isExpanded && (
                      <div className="px-5 pb-5 pt-2 border-t border-slate-100 bg-slate-50/70 space-y-3">
                        <div className="flex items-center justify-between text-xs text-slate-500 font-bold">
                          <span>نص الرسالة الكامل:</span>
                          <button
                            onClick={() => handleCopyText(msg.id, msg.message)}
                            className="flex items-center gap-1 text-emerald-700 hover:text-emerald-900 font-black"
                          >
                            {copiedId === msg.id ? <Check size={13} /> : <Copy size={13} />}
                            <span>{copiedId === msg.id ? 'تم النسخ' : 'نسخ النص'}</span>
                          </button>
                        </div>
                        <div className="p-3.5 bg-white border border-slate-200 rounded-xl text-xs sm:text-sm text-slate-800 whitespace-pre-wrap font-sans leading-relaxed shadow-inner select-text">
                          {msg.message}
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}

              {/* Pagination */}
              {queueMeta.totalPages > 1 && (
                <div className="flex items-center justify-center gap-2 pt-4">
                  <button
                    onClick={() => setQueuePage((p) => Math.max(1, p - 1))}
                    disabled={queuePage === 1}
                    className="px-4 py-2 rounded-xl bg-white border border-slate-300 font-bold text-xs disabled:opacity-40"
                  >
                    الصفحة السابقة
                  </button>
                  <span className="text-xs font-black text-slate-700 px-3">
                    صفحة {toEnglishDigits(queuePage)} من {toEnglishDigits(queueMeta.totalPages)}
                  </span>
                  <button
                    onClick={() => setQueuePage((p) => Math.min(queueMeta.totalPages, p + 1))}
                    disabled={queuePage >= queueMeta.totalPages}
                    className="px-4 py-2 rounded-xl bg-white border border-slate-300 font-bold text-xs disabled:opacity-40"
                  >
                    الصفحة التالية
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* ========================================================================= */}
      {/* TAB 2: سجل الرسائل المرسلة (Sent Messages Archive) */}
      {/* ========================================================================= */}
      {activeTab === 'sent' && (
        <div className="space-y-6">
          {/* Controls & Filter Bar */}
          <div className="bg-white p-5 rounded-3xl border-2 border-slate-200 shadow-sm space-y-4">
            <div className="flex flex-col lg:flex-row items-stretch lg:items-center justify-between gap-4">
              {/* Search Box */}
              <div className="relative flex-1">
                <Search size={18} className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  type="text"
                  placeholder="ابحث برقم المستلم (مثال: 773245776)، محتوى الرسالة، أو الكيان المرتبط..."
                  value={sentSearch}
                  onChange={(e) => {
                    setSentSearch(e.target.value);
                    setSentPage(1);
                  }}
                  className="w-full pl-4 pr-11 py-3 bg-slate-50 border-2 border-slate-200 rounded-2xl text-sm font-bold text-slate-800 focus:outline-none focus:border-emerald-500 focus:bg-white transition"
                />
              </div>

              {/* Type Filter */}
              <div className="flex items-center gap-2">
                <Filter size={16} className="text-slate-500 shrink-0" />
                <select
                  value={sentTypeFilter}
                  onChange={(e) => {
                    setSentTypeFilter(e.target.value);
                    setSentPage(1);
                  }}
                  className="px-3.5 py-2.5 bg-slate-50 border-2 border-slate-200 rounded-xl text-xs sm:text-sm font-bold text-slate-800 focus:outline-none focus:border-emerald-500"
                >
                  <option value="all">كافة الرسائل المرسلة</option>
                  <option value="INVOICE">فواتير استهلاك</option>
                  <option value="RECEIPT">سندات سداد</option>
                  <option value="WARNING">إنذارات فصل</option>
                  <option value="CUSTOM">إشعارات ورسائل عامة</option>
                </select>
              </div>

              {/* Actions */}
              <div className="flex items-center gap-2">
                <button
                  onClick={() => refetchSent()}
                  disabled={isFetchingSent}
                  className="px-3.5 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold rounded-xl text-xs transition flex items-center gap-1.5 border border-slate-300"
                  title="تحديث السجل"
                >
                  <RefreshCw size={14} className={isFetchingSent ? 'animate-spin' : ''} />
                  <span>تحديث</span>
                </button>

                <button
                  onClick={() => {
                    if (window.confirm('تحذير: هل أنت متأكد من مسح كافة سجلات الرسائل المرسلة والتاريخية من النظام؟')) {
                      clearAllMutation.mutate();
                    }
                  }}
                  disabled={clearAllMutation.isPending || sentMessages.length === 0}
                  className="px-4 py-2.5 bg-slate-100 hover:bg-rose-50 text-slate-700 hover:text-rose-700 border-2 border-slate-300 hover:border-rose-300 font-bold rounded-xl text-xs transition flex items-center gap-1.5 disabled:opacity-50"
                >
                  <Trash2 size={14} className={clearAllMutation.isPending ? 'animate-spin' : ''} />
                  <span>مسح السجل كاملاً</span>
                </button>
              </div>
            </div>
          </div>

          {/* Sent Messages List */}
          {sentMessages.length === 0 ? (
            <div className="bg-white rounded-3xl p-12 text-center border-2 border-dashed border-slate-300 shadow-sm">
              <div className="w-16 h-16 bg-slate-100 border-2 border-slate-200 rounded-3xl flex items-center justify-center mx-auto text-slate-500 mb-4 shadow-sm">
                <Inbox size={32} />
              </div>
              <h3 className="text-lg font-black text-slate-800 mb-1">
                سجل الرسائل المرسلة فارغ
              </h3>
              <p className="text-slate-500 text-sm max-w-md mx-auto">
                لم يتم إرسال أي رسائل بعد أو تمت تصفية السجل. ستظهر هنا كافة الفواتير والسندات بعد إرسالها بنجاح.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {sentMessages.map((msg) => {
                const isExpanded = expandedSentId === msg.id;
                const isDeleting = deleteSingleMutation.isPending && deleteSingleMutation.variables === msg.id;

                return (
                  <div
                    key={msg.id}
                    className="bg-white rounded-2xl border-2 border-slate-200 hover:border-emerald-300 transition-all overflow-hidden shadow-sm"
                  >
                    <div className="p-4 sm:p-5 flex flex-col md:flex-row md:items-center justify-between gap-4">
                      {/* Left Info */}
                      <div className="flex items-start gap-3.5 flex-1 min-w-0">
                        <div className="w-11 h-11 rounded-2xl bg-emerald-50 border-2 border-emerald-300 flex items-center justify-center shrink-0 text-emerald-700">
                          <CheckCheck size={20} />
                        </div>

                        <div className="space-y-1 flex-1 min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            {getTypeBadge(msg.type)}
                            {getStatusBadge(msg.status)}
                            <span className="text-xs font-mono font-bold text-slate-500 bg-slate-100 px-2.5 py-0.5 rounded-lg">
                              #{toEnglishDigits(msg.id)}
                            </span>
                          </div>

                          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
                            <span className="font-black text-slate-900 font-mono tracking-wide">
                              {formatDisplayPhone(msg.phone_number)}
                            </span>
                            {msg.source_entity && (
                              <span className="text-xs font-bold text-emerald-800 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded-lg">
                                {msg.source_entity}
                              </span>
                            )}
                            <span className="text-xs text-slate-500 font-medium">
                              تاريخ الإرسال: {formatDateTime(msg.sent_at || msg.created_at)}
                            </span>
                          </div>
                        </div>
                      </div>

                      {/* Right Actions */}
                      <div className="flex items-center gap-2 self-end md:self-center">
                        <button
                          onClick={() => handleCopyText(msg.id, msg.message)}
                          className="px-3 py-2 text-slate-600 hover:text-emerald-700 bg-slate-100 hover:bg-emerald-50 rounded-xl text-xs font-bold transition flex items-center gap-1"
                          title="نسخ نص الرسالة"
                        >
                          {copiedId === msg.id ? <Check size={14} className="text-emerald-600" /> : <Copy size={14} />}
                          <span>{copiedId === msg.id ? 'تم النسخ' : 'نسخ'}</span>
                        </button>

                        <button
                          onClick={() => setExpandedSentId(isExpanded ? null : msg.id)}
                          className="px-3 py-2 text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 rounded-xl text-xs font-bold transition flex items-center gap-1"
                        >
                          {isExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                          <span>{isExpanded ? 'إخفاء' : 'عرض الرسالة'}</span>
                        </button>

                        <button
                          onClick={() => {
                            if (window.confirm('هل تريد حذف هذه الرسالة من السجل؟')) {
                              deleteSingleMutation.mutate(msg.id);
                            }
                          }}
                          disabled={isDeleting}
                          className="p-2 text-rose-500 hover:bg-rose-50 border border-transparent hover:border-rose-200 rounded-xl transition disabled:opacity-50"
                          title="حذف من السجل"
                        >
                          <Trash2 size={15} />
                        </button>
                      </div>
                    </div>

                    {/* Expandable Text View */}
                    {isExpanded && (
                      <div className="px-5 pb-5 pt-2 border-t border-slate-100 bg-slate-50/70 space-y-3">
                        <div className="p-3.5 bg-white border border-slate-200 rounded-xl text-xs sm:text-sm text-slate-800 whitespace-pre-wrap font-sans leading-relaxed shadow-inner select-text">
                          {msg.message}
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}

              {/* Pagination */}
              {sentMeta.totalPages > 1 && (
                <div className="flex items-center justify-center gap-2 pt-4">
                  <button
                    onClick={() => setSentPage((p) => Math.max(1, p - 1))}
                    disabled={sentPage === 1}
                    className="px-4 py-2 rounded-xl bg-white border border-slate-300 font-bold text-xs disabled:opacity-40"
                  >
                    الصفحة السابقة
                  </button>
                  <span className="text-xs font-black text-slate-700 px-3">
                    صفحة {toEnglishDigits(sentPage)} من {toEnglishDigits(sentMeta.totalPages)}
                  </span>
                  <button
                    onClick={() => setSentPage((p) => Math.min(sentMeta.totalPages, p + 1))}
                    disabled={sentPage >= sentMeta.totalPages}
                    className="px-4 py-2 rounded-xl bg-white border border-slate-300 font-bold text-xs disabled:opacity-40"
                  >
                    الصفحة التالية
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* ========================================================================= */}
      {/* TAB 3: ربط الجهاز وجلسة الواتساب (Device Connection & Gateway) */}
      {/* ========================================================================= */}
      {activeTab === 'gateway' && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Card 1: QR & Gateway Connection */}
          <div className="bg-white p-6 sm:p-8 rounded-3xl border-2 border-slate-200 shadow-sm space-y-6">
            <div className="flex items-center justify-between border-b pb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-2xl bg-emerald-50 text-emerald-700 flex items-center justify-center border border-emerald-200">
                  <Smartphone size={22} />
                </div>
                <div>
                  <h3 className="text-lg font-black text-slate-900">حالة خادم الواتساب</h3>
                  <p className="text-xs text-slate-500 font-medium">جلسة الربط والاتصال الفعلي مع تطبيق واتساب</p>
                </div>
              </div>

              <button
                onClick={() => refetchStatus()}
                disabled={isFetchingStatus}
                className="p-2 text-slate-600 hover:bg-slate-100 rounded-xl border border-slate-200"
                title="تحديث حالة الجلسة"
              >
                <RefreshCw size={16} className={isFetchingStatus ? 'animate-spin' : ''} />
              </button>
            </div>

            {/* QR Code / Connection Box */}
            <div className="flex flex-col items-center justify-center p-6 bg-slate-50 rounded-2xl border-2 border-dashed border-slate-300 text-center">
              {connectionStatus === 'CONNECTED' || connectionStatus === 'READY' ? (
                <div className="space-y-3 py-6">
                  <div className="w-20 h-20 bg-emerald-100 text-emerald-600 rounded-full flex items-center justify-center mx-auto shadow-inner border-2 border-emerald-300">
                    <CheckCircle size={40} />
                  </div>
                  <h4 className="text-lg font-black text-emerald-950">الجلسة متصلة ونشطة بنجاح</h4>
                  <p className="text-xs text-slate-600 max-w-xs font-bold">
                    الجهاز متصل ومستعد لمعالجة وإرسال كافة الفواتير والسندات في الطابور تلقائياً.
                  </p>
                </div>
              ) : connectionStatus === 'RECONNECTING' || connectionStatus === 'CONNECTING' ? (
                <div className="space-y-3 py-6">
                  <div className="w-20 h-20 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center mx-auto shadow-inner border-2 border-blue-300">
                    <RefreshCw size={40} className="animate-spin" />
                  </div>
                  <h4 className="text-lg font-black text-blue-950">جارٍ استعادة الاتصال تلقائياً...</h4>
                  <p className="text-xs text-slate-600 max-w-xs font-bold">
                    تم رصد استئناف الشبكة وجارٍ التحقق من نبض المقبس وإعادة المصادقة مع خوادم الواتساب فوراً.
                  </p>
                </div>
              ) : qrImage ? (
                <div className="space-y-4">
                  <div className="p-3 bg-white rounded-2xl border-2 border-slate-300 shadow-md inline-block">
                    <img
                      src={qrImage.startsWith('data:') ? qrImage : `data:image/png;base64,${qrImage}`}
                      alt="WhatsApp QR Code"
                      className="w-56 h-56 object-contain rounded-lg"
                    />
                  </div>
                  <div className="space-y-1">
                    <div className="text-sm font-black text-slate-800">امسح الرمز بواسطة واتساب في هاتفك</div>
                    <div className="text-xs text-slate-500 font-medium max-w-xs">
                      افتح واتساب &gt; الأجهزة المرتبطة &gt; ربط جهاز &gt; وجّه الكاميرا نحو هذا الرمز
                    </div>
                  </div>
                </div>
              ) : (
                <div className="space-y-3 py-6 text-slate-500">
                  <QrCode size={48} className="mx-auto text-slate-400" />
                  <div className="text-sm font-bold">بانتظار توليد رمز الاستجابة السريعة...</div>
                  <button
                    onClick={() => restartMutation.mutate()}
                    disabled={restartMutation.isPending}
                    className="px-4 py-2 bg-emerald-600 text-white rounded-xl text-xs font-black shadow"
                  >
                    توليد رمز QR جديد
                  </button>
                </div>
              )}
            </div>

            {/* Gateway Control Action Buttons */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2">
              <button
                onClick={() => restartMutation.mutate()}
                disabled={restartMutation.isPending}
                className="py-3 px-4 bg-slate-100 hover:bg-slate-200 text-slate-800 rounded-2xl font-black text-xs transition flex items-center justify-center gap-2 border border-slate-300 disabled:opacity-50"
              >
                <RefreshCcw size={15} className={restartMutation.isPending ? 'animate-spin' : ''} />
                <span>إعادة تهيئة الجلسة</span>
              </button>

              <button
                onClick={() => {
                  if (window.confirm('هل أنت متأكد من تسجيل الخروج وقطع ربط جلسة الواتساب؟')) {
                    logoutMutation.mutate();
                  }
                }}
                disabled={logoutMutation.isPending}
                className="py-3 px-4 bg-rose-50 hover:bg-rose-100 text-rose-700 border-2 border-rose-300 rounded-2xl font-black text-xs transition flex items-center justify-center gap-2 disabled:opacity-50"
              >
                <LogOut size={15} className={logoutMutation.isPending ? 'animate-spin' : ''} />
                <span>تسجيل الخروج وقطع الربط</span>
              </button>
            </div>
          </div>

          {/* Card 2: Send Test Message Form */}
          <div className="bg-white p-6 sm:p-8 rounded-3xl border-2 border-slate-200 shadow-sm space-y-6">
            <div className="flex items-center gap-3 border-b pb-4">
              <div className="w-10 h-10 rounded-2xl bg-blue-50 text-blue-700 flex items-center justify-center border border-blue-200">
                <SendHorizontal size={22} />
              </div>
              <div>
                <h3 className="text-lg font-black text-slate-900">إرسال رسالة تجريبية</h3>
                <p className="text-xs text-slate-500 font-medium">فحص واختبار دقة الإرسال الفوري لأي رقم هاتف</p>
              </div>
            </div>

            <form onSubmit={handleSendTest} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-xs font-black text-slate-700 block">
                  رقم هاتف المستلم (يمني أو دولي):
                </label>
                <input
                  type="text"
                  placeholder="مثال: 773245776 أو 967773245776"
                  value={testNumber}
                  onChange={(e) => setTestNumber(toEnglishDigits(e.target.value))}
                  className="w-full px-4 py-3 bg-slate-50 border-2 border-slate-200 rounded-2xl text-sm font-bold text-slate-900 focus:outline-none focus:border-emerald-500 focus:bg-white transition font-mono"
                  required
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs font-black text-slate-700 block">
                  نص الرسالة:
                </label>
                <textarea
                  rows={4}
                  value={testMessage}
                  onChange={(e) => setTestMessage(e.target.value)}
                  className="w-full p-4 bg-slate-50 border-2 border-slate-200 rounded-2xl text-sm font-bold text-slate-900 focus:outline-none focus:border-emerald-500 focus:bg-white transition leading-relaxed resize-none"
                  required
                />
              </div>

              <button
                type="submit"
                disabled={testMutation.isPending || !testNumber}
                className="w-full py-3.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-2xl font-black text-sm transition flex items-center justify-center gap-2 shadow-lg shadow-emerald-600/30 disabled:opacity-50"
              >
                <Send size={16} className={testMutation.isPending ? 'animate-spin' : ''} />
                <span>{testMutation.isPending ? 'جاري الإضافة للطابور...' : 'إرسال الرسالة التجريبية الآن'}</span>
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default WhatsApp;
