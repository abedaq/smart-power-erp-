import React, { useState, useEffect } from 'react';
import { 
  Sparkles, 
  Download, 
  RefreshCw, 
  CheckCircle2, 
  AlertTriangle, 
  X, 
  ShieldCheck, 
  HardDrive
} from 'lucide-react';
import type { CheckUpdateResponse, UpdateProgress } from '../services/update.service';
import { 
  getUpdateStatusApi, 
  downloadUpdateApi, 
  applyUpdateApi 
} from '../services/update.service';
import { getSavedApiUrl } from '../lib/api';
import toast from 'react-hot-toast';

interface UpdateNotificationModalProps {
  isOpen: boolean;
  onClose: () => void;
  updateInfo?: CheckUpdateResponse | null;
  onCheckAgain?: () => void;
}

export const UpdateNotificationModal: React.FC<UpdateNotificationModalProps> = ({
  isOpen,
  onClose,
  updateInfo: initialUpdateInfo,
}) => {
  const [updateInfo, setUpdateInfo] = useState<CheckUpdateResponse | null>(initialUpdateInfo || null);
  const [status, setStatus] = useState<UpdateProgress['status']>('idle');
  const [progress, setProgress] = useState<number>(0);
  const [bytesReceived, setBytesReceived] = useState<number>(0);
  const [totalBytes, setTotalBytes] = useState<number>(0);
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [isApplying, setIsApplying] = useState<boolean>(false);

  useEffect(() => {
    if (initialUpdateInfo) {
      setUpdateInfo(initialUpdateInfo);
    }
  }, [initialUpdateInfo]);

  // Initial check on mount/open if download is already in progress
  useEffect(() => {
    if (isOpen) {
      getUpdateStatusApi()
        .then((res) => {
          if (res) {
            setStatus(res.status);
            setProgress(res.progress);
            setBytesReceived(res.bytes_received);
            setTotalBytes(res.total_bytes);
            if (res.status === 'error') {
              setErrorMessage(res.last_error || '');
            }
          }
        })
        .catch(() => {});
    }
  }, [isOpen]);

  // Format bytes into English formatted MB
  const formatMB = (bytes: number): string => {
    if (!bytes || bytes <= 0) return '0.0 MB';
    const mb = bytes / (1024 * 1024);
    return `${mb.toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} MB`;
  };

  // Pure Event-Driven Architecture: Listen for Server-Sent Events (SSE) push updates
  useEffect(() => {
    if (!isOpen) return;

    let eventSource: EventSource | null = null;
    try {
      const apiUrl = getSavedApiUrl();
      const streamUrl = `${apiUrl}/realtime/stream`;
      eventSource = new EventSource(streamUrl);

      eventSource.onmessage = (event) => {
        if (!event.data) return;
        try {
          const parsed = JSON.parse(event.data);
          if (parsed.type === 'system:update_progress' && parsed.payload) {
            const p: UpdateProgress = parsed.payload;
            if (p.status) setStatus(p.status);
            if (typeof p.progress === 'number') setProgress(p.progress);
            if (typeof p.bytes_received === 'number') setBytesReceived(p.bytes_received);
            if (typeof p.total_bytes === 'number') setTotalBytes(p.total_bytes);
            if (p.status === 'error') {
              setErrorMessage(p.last_error || 'حدث خطأ أثناء تحميل التحديث');
            }
          }
        } catch {
          // ignore non-json keepalive comments
        }
      };

      eventSource.onerror = () => {
        // SSE auto-reconnects natively
      };
    } catch (err) {
      console.error('Failed to connect SSE for update progress:', err);
    }

    return () => {
      if (eventSource) {
        eventSource.close();
        eventSource = null;
      }
    };
  }, [isOpen]);

  const handleStartDownload = async () => {
    if (!updateInfo) return;
    try {
      setStatus('downloading');
      setProgress(0);
      setErrorMessage('');
      await downloadUpdateApi({
        download_url: updateInfo.download_url,
        sha256: updateInfo.sha256,
      });
    } catch (err: any) {
      setStatus('error');
      setErrorMessage(err.response?.data?.message || err.message || 'فشل بدء تحميل التحديث');
      toast.error('تعذر بدء تحميل التحديث');
    }
  };

  const handleApplyUpdate = async () => {
    try {
      setIsApplying(true);
      setStatus('applying');
      toast.loading('جاري تجهيز التحديث وإعادة تشغيل التطبيق...', { duration: 5000 });
      await applyUpdateApi();
    } catch (err: any) {
      setIsApplying(false);
      setStatus('error');
      setErrorMessage(err.response?.data?.message || err.message || 'فشل تطبيق التحديث');
      toast.error('فشل استبدال ملف التطبيق');
    }
  };

  if (!isOpen || !updateInfo) {
    return null;
  }

  const isMandatory = updateInfo.mandatory;

  return (
    <div 
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/80 backdrop-blur-sm animate-in fade-in duration-200"
      dir="rtl"
    >
      <div 
        className="bg-white rounded-3xl shadow-2xl border border-slate-100 w-full max-w-xl overflow-hidden transform transition-all"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header Header Pattern */}
        <div className="bg-gradient-to-r from-blue-600 via-indigo-600 to-purple-700 p-6 text-white relative">
          {!isMandatory && status !== 'downloading' && status !== 'applying' && (
            <button
              onClick={onClose}
              className="absolute left-4 top-4 p-2 text-white/80 hover:text-white bg-white/10 hover:bg-white/20 rounded-full transition-all"
              title="إغلاق"
            >
              <X size={18} />
            </button>
          )}

          <div className="flex items-center gap-3">
            <div className="p-3 bg-white/15 rounded-2xl backdrop-blur-md ring-1 ring-white/30">
              <Sparkles className="w-8 h-8 text-yellow-300 animate-pulse" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-xl font-black text-white">تحديث جديد متوفر للنظام</h3>
                {isMandatory && (
                  <span className="bg-red-500 text-white text-xs px-2.5 py-0.5 rounded-full font-bold shadow-sm">
                    إجباري
                  </span>
                )}
              </div>
              <p className="text-blue-100 text-xs mt-1 font-medium">
                SmartPower ERP Desktop Engine
              </p>
            </div>
          </div>

          {/* Versions Bar */}
          <div className="mt-5 grid grid-cols-2 gap-2 bg-black/20 p-3 rounded-2xl border border-white/10 text-xs backdrop-blur-sm">
            <div className="flex items-center justify-between px-2">
              <span className="text-blue-200 font-semibold">الإصدار الحالي:</span>
              <span className="font-mono font-bold text-white bg-white/10 px-2 py-0.5 rounded-md">
                v{updateInfo.current_version}
              </span>
            </div>
            <div className="flex items-center justify-between px-2 border-r border-white/20">
              <span className="text-emerald-300 font-semibold">الإصدار الجديد:</span>
              <span className="font-mono font-bold text-emerald-300 bg-emerald-500/20 px-2 py-0.5 rounded-md">
                v{updateInfo.latest_version}
              </span>
            </div>
          </div>
        </div>

        {/* Content Body */}
        <div className="p-6 space-y-5">
          {/* Changelog Section */}
          <div className="space-y-2">
            <label className="text-xs font-black text-slate-700 flex items-center gap-1.5">
              <ShieldCheck className="w-4 h-4 text-indigo-600" />
              أبرز التحسينات والمميزات في هذا الإصدار:
            </label>
            <div className="bg-slate-50 border border-slate-200 rounded-2xl p-4 max-h-48 overflow-y-auto text-xs text-slate-700 leading-relaxed font-medium space-y-1.5 shadow-inner">
              {updateInfo.changelog ? (
                updateInfo.changelog.split('\n').map((line, idx) => (
                  <div key={idx} className="flex items-start gap-2">
                    <span className="text-blue-600 font-bold">•</span>
                    <span>{line.trim()}</span>
                  </div>
                ))
              ) : (
                <div className="text-slate-500">تحسينات في الاستقرار والأداء وسرعة المعالجة.</div>
              )}
            </div>
          </div>

          {/* Data Safety Assurance Banner */}
          <div className="bg-emerald-50 border border-emerald-200 p-3.5 rounded-2xl flex items-center gap-3 text-xs text-emerald-800">
            <HardDrive className="w-5 h-5 text-emerald-600 flex-shrink-0" />
            <div>
              <span className="font-bold">أمان وحماية البيانات مضمون 100%:</span>
              <p className="text-emerald-700 text-[11px] mt-0.5">
                تحديث البرنامج يتم بصورة ذرية دون التأثير على قاعدة البيانات أو النسخ الاحتياطية أو الإعدادات إطلاقاً.
              </p>
            </div>
          </div>

          {/* Downloading Progress Bar */}
          {status === 'downloading' && (
            <div className="space-y-3 bg-blue-50/70 border border-blue-200 rounded-2xl p-4">
              <div className="flex justify-between items-center text-xs font-bold text-blue-900">
                <span className="flex items-center gap-2">
                  <RefreshCw className="w-4 h-4 animate-spin text-blue-600" />
                  جاري تحميل ملفات التحديث بأمان...
                </span>
                <span className="font-mono text-blue-700">
                  {progress.toLocaleString('en-US', { maximumFractionDigits: 0 })}%
                </span>
              </div>

              {/* Visual Progress Bar */}
              <div className="w-full bg-blue-200/80 rounded-full h-3 overflow-hidden shadow-inner">
                <div 
                  className="bg-gradient-to-r from-blue-600 to-indigo-600 h-full rounded-full transition-all duration-300 shadow"
                  style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
                />
              </div>

              <div className="flex justify-between items-center text-[11px] text-blue-700 font-mono">
                <span>تم تحميل: {formatMB(bytesReceived)}</span>
                <span>الحجم الإجمالي: {formatMB(totalBytes)}</span>
              </div>
            </div>
          )}

          {/* Ready to Install State */}
          {status === 'ready' && (
            <div className="bg-emerald-50 border border-emerald-300 rounded-2xl p-4 flex items-center gap-3 text-xs text-emerald-900">
              <CheckCircle2 className="w-6 h-6 text-emerald-600 flex-shrink-0" />
              <div>
                <div className="font-black text-sm">اكتمل التحميل والتحقق من السلامة بنجاح!</div>
                <p className="text-emerald-700 text-xs mt-0.5">
                  تم التحقق من بصمة التشفير (SHA256). اضغط على "تثبيت وإعادة التشغيل" لتطبيق التحديث فوراً.
                </p>
              </div>
            </div>
          )}

          {/* Error State */}
          {status === 'error' && (
            <div className="bg-red-50 border border-red-200 rounded-2xl p-4 flex items-start gap-3 text-xs text-red-900">
              <AlertTriangle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
              <div className="space-y-1">
                <div className="font-bold">تعذر إكمال التحديث</div>
                <div className="text-red-700 text-[11px]">{errorMessage}</div>
              </div>
            </div>
          )}

          {/* Applying State */}
          {status === 'applying' && (
            <div className="bg-indigo-50 border border-indigo-200 rounded-2xl p-4 text-center space-y-2">
              <RefreshCw className="w-8 h-8 animate-spin text-indigo-600 mx-auto" />
              <div className="font-bold text-sm text-indigo-900">جاري استبدال التطبيق وإعادة التشغيل...</div>
              <p className="text-indigo-700 text-xs">
                سيتم إغلاق البرنامج لثوانٍ معدودة وإعادة فتحه بالإصدار الجديد تلقائياً.
              </p>
            </div>
          )}
        </div>

        {/* Action Buttons Footer */}
        <div className="bg-slate-50 border-t border-slate-100 p-4 px-6 flex items-center justify-between gap-3">
          {!isMandatory && status !== 'downloading' && status !== 'applying' ? (
            <button
              onClick={onClose}
              className="px-5 py-2.5 text-xs font-bold text-slate-600 hover:text-slate-900 hover:bg-slate-200/70 rounded-xl transition-all"
            >
              تذكيري لاحقاً
            </button>
          ) : <div />}

          <div className="flex items-center gap-2">
            {status === 'idle' && (
              <button
                onClick={handleStartDownload}
                className="flex items-center gap-2 px-6 py-2.5 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 text-white font-bold text-xs rounded-xl shadow-lg shadow-blue-500/20 hover:shadow-blue-500/30 transition-all cursor-pointer"
              >
                <Download size={16} />
                <span>{totalBytes > 0 ? `تحديث الآن (${formatMB(totalBytes)})` : 'تحديث الآن'}</span>
              </button>
            )}

            {status === 'ready' && (
              <button
                onClick={handleApplyUpdate}
                disabled={isApplying}
                className="flex items-center gap-2 px-6 py-2.5 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 text-white font-bold text-xs rounded-xl shadow-lg shadow-emerald-500/20 transition-all cursor-pointer disabled:opacity-50"
              >
                <RefreshCw size={16} className={isApplying ? 'animate-spin' : ''} />
                <span>تثبيت وإعادة التشغيل</span>
              </button>
            )}

            {status === 'error' && (
              <button
                onClick={handleStartDownload}
                className="flex items-center gap-2 px-5 py-2.5 bg-red-600 hover:bg-red-700 text-white font-bold text-xs rounded-xl shadow transition-all cursor-pointer"
              >
                <RefreshCw size={16} />
                <span>إعادة المحاولة</span>
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default UpdateNotificationModal;
