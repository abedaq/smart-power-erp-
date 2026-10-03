import React, { useState, useEffect, useRef, useCallback } from 'react';
import { 
  Zap, 
  Download, 
  RefreshCw, 
  AlertTriangle, 
  X, 
  ShieldCheck, 
  Loader2, 
  Sparkles, 
  ArrowLeft 
} from 'lucide-react';
import type { CheckUpdateResponse, UpdateProgress } from '../services/update.service';
import { 
  getUpdateStatusApi, 
  downloadUpdateApi, 
  applyUpdateApi 
} from '../services/update.service';
import { useRealtime } from '../context/RealtimeContext';
import { useAuth } from '../context/AuthContext';
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
  const { lastUpdateProgress } = useRealtime();
  const { user } = useAuth();

  const mountedRef = useRef<boolean>(true);
  const isDownloadingRef = useRef<boolean>(false);
  const isApplyingRef = useRef<boolean>(false);
  const hasTriggeredApplyRef = useRef<boolean>(false);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

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
          if (res && mountedRef.current) {
            setStatus(res.status);
            setProgress(res.progress);
            setBytesReceived(res.bytes_received);
            setTotalBytes(res.total_bytes);
            if (res.status === 'error') {
              setErrorMessage(res.last_error || 'حدث خطأ غير متوقع');
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

  // Safe apply update function
  const handleApplyUpdate = useCallback(async () => {
    if (isApplyingRef.current) return;
    try {
      isApplyingRef.current = true;
      if (mountedRef.current) {
        setIsApplying(true);
        setStatus('applying');
      }
      toast.loading('🔄 جاري تطبيق التحديث وإعادة تشغيل البرنامج...', { id: 'update-applying', duration: 4000 });
      await applyUpdateApi();
    } catch (err: any) {
      if (mountedRef.current) {
        setIsApplying(false);
        setStatus('error');
        setErrorMessage(err.response?.data?.message || err.message || 'فشل تطبيق التحديث واستبدال الملفات');
      }
      isApplyingRef.current = false;
      hasTriggeredApplyRef.current = false;
      toast.error('فشل تطبيق التحديث', { id: 'update-applying' });
    }
  }, []);

  // Single-Click Auto-Chaining: When status reaches 'ready', trigger handleApplyUpdate automatically!
  useEffect(() => {
    if (status === 'ready' && !hasTriggeredApplyRef.current && !isApplying) {
      hasTriggeredApplyRef.current = true;
      handleApplyUpdate();
    }
  }, [status, isApplying, handleApplyUpdate]);

  // Pure Event-Driven Architecture: Listen for push updates via shared RealtimeContext
  useEffect(() => {
    if (!isOpen || !lastUpdateProgress || !mountedRef.current) return;
    const p: UpdateProgress = lastUpdateProgress;
    if (p.status) {
      setStatus(p.status);
      if (p.status === 'ready') {
        isDownloadingRef.current = false;
      }
    }
    if (typeof p.progress === 'number') setProgress(p.progress);
    if (typeof p.bytes_received === 'number') setBytesReceived(p.bytes_received);
    if (typeof p.total_bytes === 'number') setTotalBytes(p.total_bytes);
    if (p.status === 'error') {
      setErrorMessage(p.last_error || 'حدث خطأ أثناء تحميل التحديث');
      isDownloadingRef.current = false;
      isApplyingRef.current = false;
      hasTriggeredApplyRef.current = false;
    }
  }, [isOpen, lastUpdateProgress]);

  // Fallback Resilient Polling: Guarantee continuous live updates even if SSE disconnects or lags
  useEffect(() => {
    if (!isOpen || status !== 'downloading') return;
    const pollInterval = setInterval(() => {
      getUpdateStatusApi()
        .then((res) => {
          if (res && mountedRef.current) {
            if (res.status) setStatus(res.status);
            if (typeof res.progress === 'number') setProgress(res.progress);
            if (typeof res.bytes_received === 'number') setBytesReceived(res.bytes_received);
            if (typeof res.total_bytes === 'number') setTotalBytes(res.total_bytes);
            if (res.status === 'ready') {
              isDownloadingRef.current = false;
            } else if (res.status === 'error') {
              setErrorMessage(res.last_error || 'حدث خطأ أثناء تحميل التحديث');
              isDownloadingRef.current = false;
              isApplyingRef.current = false;
              hasTriggeredApplyRef.current = false;
            }
          }
        })
        .catch(() => {});
    }, 600);

    return () => clearInterval(pollInterval);
  }, [isOpen, status]);

  const handleStartDownload = useCallback(async () => {
    if (!updateInfo || isDownloadingRef.current) return;
    try {
      isDownloadingRef.current = true;
      isApplyingRef.current = false;
      hasTriggeredApplyRef.current = false;
      setStatus('downloading');
      setProgress(0);
      setErrorMessage('');
      await downloadUpdateApi({
        download_url: updateInfo.download_url,
        sha256: updateInfo.sha256,
      });
    } catch (err: any) {
      if (mountedRef.current) {
        setStatus('error');
        setErrorMessage(err.response?.data?.message || err.message || 'فشل بدء تحميل التحديث');
      }
      isDownloadingRef.current = false;
      isApplyingRef.current = false;
      hasTriggeredApplyRef.current = false;
      toast.error('تعذر بدء تحميل التحديث');
    }
  }, [updateInfo]);

  const handleRetry = useCallback(() => {
    setErrorMessage('');
    isDownloadingRef.current = false;
    isApplyingRef.current = false;
    hasTriggeredApplyRef.current = false;

    // If update package was already fully downloaded, retry applying directly
    if (bytesReceived > 0 && totalBytes > 0 && bytesReceived >= totalBytes) {
      handleApplyUpdate();
    } else {
      handleStartDownload();
    }
  }, [bytesReceived, totalBytes, handleApplyUpdate, handleStartDownload]);

  if (!isOpen || !updateInfo) {
    return null;
  }

  const isMandatory = updateInfo.mandatory && user?.role === 'ADMIN';
  const isBusy = status === 'downloading' || status === 'ready' || status === 'applying' || isApplying;

  return (
    <div 
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/70 backdrop-blur-md animate-in fade-in duration-200"
      dir="rtl"
    >
      <div 
        className="bg-white rounded-3xl shadow-2xl border border-slate-100 w-full max-w-[440px] overflow-hidden transform transition-all animate-in zoom-in-95 duration-200"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Sleek Compact Header */}
        <div className="bg-gradient-to-r from-blue-600 via-indigo-600 to-indigo-700 p-5 text-white relative shadow-inner">
          {!isMandatory && !isBusy && (
            <button
              onClick={onClose}
              className="absolute left-3.5 top-3.5 p-1.5 text-white/80 hover:text-white bg-white/10 hover:bg-white/20 rounded-full transition-all cursor-pointer"
              title="إغلاق"
            >
              <X size={16} />
            </button>
          )}

          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-white/15 rounded-2xl backdrop-blur-md ring-1 ring-white/30 flex-shrink-0 shadow-sm">
              <Zap className="w-6 h-6 text-yellow-300 fill-yellow-300 animate-pulse" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h3 className="text-base font-black text-white leading-tight">
                  ⚡ يتوفر تحديث جديد للنظام (v{updateInfo.latest_version})
                </h3>
                {isMandatory && (
                  <span className="bg-rose-500 text-white text-[10px] px-2 py-0.5 rounded-full font-bold shadow-sm">
                    إجباري
                  </span>
                )}
              </div>
              <p className="text-blue-100/90 text-xs mt-0.5 font-medium truncate">
                SmartPower ERP Desktop Engine
              </p>
            </div>
          </div>

          {/* Compact Versions Pill Bar */}
          <div className="mt-3.5 flex items-center justify-between bg-black/20 px-3 py-1.5 rounded-xl border border-white/10 text-xs backdrop-blur-sm">
            <div className="flex items-center gap-1.5 text-blue-200">
              <span className="font-semibold text-[11px]">الحالي:</span>
              <span className="font-mono font-bold text-white bg-white/10 px-1.5 py-0.5 rounded text-[11px]">
                v{updateInfo.current_version}
              </span>
            </div>
            <ArrowLeft size={14} className="text-white/40" />
            <div className="flex items-center gap-1.5 text-emerald-300">
              <span className="font-semibold text-[11px]">الجديد:</span>
              <span className="font-mono font-bold text-emerald-300 bg-emerald-500/20 px-1.5 py-0.5 rounded text-[11px]">
                v{updateInfo.latest_version}
              </span>
            </div>
          </div>
        </div>

        {/* Content Body */}
        <div className="p-5 space-y-4">
          {/* Initial State: Features / Changelog & Safety Assurance */}
          {status === 'idle' && (
            <>
              {/* Changelog Highlights */}
              <div className="space-y-1.5">
                <label className="text-[11px] font-black text-slate-700 flex items-center gap-1">
                  <Sparkles className="w-3.5 h-3.5 text-indigo-600" />
                  أبرز تحسينات هذا الإصدار:
                </label>
                <div className="bg-slate-50 border border-slate-200/80 rounded-2xl p-3 max-h-36 overflow-y-auto text-xs text-slate-700 leading-relaxed font-medium space-y-1 shadow-inner">
                  {updateInfo.changelog ? (
                    updateInfo.changelog.split('\n').filter(Boolean).map((line, idx) => (
                      <div key={idx} className="flex items-start gap-1.5">
                        <span className="text-blue-600 font-bold">•</span>
                        <span>{line.trim()}</span>
                      </div>
                    ))
                  ) : (
                    <div className="text-slate-500 text-xs">تحسينات في الاستقرار والأداء وسرعة المعالجة.</div>
                  )}
                </div>
              </div>

              {/* Data Safety Assurance */}
              <div className="bg-emerald-50/90 border border-emerald-200/80 p-2.5 rounded-2xl flex items-center gap-2.5 text-xs text-emerald-900">
                <ShieldCheck className="w-5 h-5 text-emerald-600 flex-shrink-0" />
                <div className="text-[11px] leading-tight">
                  <span className="font-bold">أمان البيانات مضمون 100%: </span>
                  <span className="text-emerald-700">التحديث آمن وذري ولا يمس قواعد البيانات إطلاقاً.</span>
                </div>
              </div>
            </>
          )}

          {/* Downloading Progress State */}
          {status === 'downloading' && (
            <div className="space-y-3 bg-blue-50/70 border border-blue-200/80 rounded-2xl p-4 animate-in fade-in duration-200">
              <div className="flex justify-between items-center text-xs font-bold text-blue-950">
                <span className="flex items-center gap-2">
                  <Loader2 className="w-4 h-4 animate-spin text-blue-600" />
                  جاري تحميل حزمة التحديث بأمان...
                </span>
                <span className="font-mono text-blue-800 text-sm font-black">
                  {progress.toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%
                </span>
              </div>

              {/* Animated Progress Bar */}
              <div className="w-full bg-blue-200/70 rounded-full h-2.5 overflow-hidden shadow-inner">
                <div 
                  className="bg-gradient-to-r from-blue-600 via-indigo-600 to-cyan-500 h-full rounded-full transition-all duration-300 shadow"
                  style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
                />
              </div>

              <div className="flex justify-between items-center text-[11px] text-blue-700 font-mono font-medium">
                <span>تم تحميل: {formatMB(bytesReceived)}</span>
                <span>الإجمالي: {formatMB(totalBytes)}</span>
              </div>
            </div>
          )}

          {/* Applying State (Auto-Chained) */}
          {(status === 'ready' || status === 'applying' || isApplying) && (
            <div className="bg-gradient-to-b from-indigo-50 to-blue-50 border border-indigo-200 rounded-2xl p-5 text-center space-y-3 animate-in zoom-in-95 duration-200">
              <div className="relative inline-flex items-center justify-center">
                <div className="w-12 h-12 rounded-full bg-indigo-100 flex items-center justify-center animate-pulse">
                  <RefreshCw className="w-6 h-6 animate-spin text-indigo-600" />
                </div>
              </div>
              <div className="space-y-1">
                <div className="font-black text-sm text-indigo-950">
                  🔄 جاري تطبيق التحديث وإعادة تشغيل البرنامج...
                </div>
                <p className="text-indigo-700 text-xs leading-relaxed">
                  سيتم إغلاق البرنامج لثوانٍ معدودة وإعادة فتحه بالإصدار الجديد <span className="font-bold font-mono">v{updateInfo.latest_version}</span> تلقائياً.
                </p>
              </div>
            </div>
          )}

          {/* Error State */}
          {status === 'error' && (
            <div className="bg-rose-50 border border-rose-200 rounded-2xl p-4 flex items-start gap-2.5 text-xs text-rose-950 animate-in shake duration-200">
              <AlertTriangle className="w-5 h-5 text-rose-600 flex-shrink-0 mt-0.5" />
              <div className="space-y-1 flex-1 min-w-0">
                <div className="font-black text-xs text-rose-900">تعذر إكمال التحديث</div>
                <div className="text-rose-700 text-[11px] leading-relaxed break-words">{errorMessage}</div>
              </div>
            </div>
          )}
        </div>

        {/* Action Buttons Footer */}
        <div className="bg-slate-50 border-t border-slate-100 p-4 px-5 flex items-center justify-between gap-3">
          {/* Ghost / Cancel Button */}
          {!isMandatory && !isBusy ? (
            <button
              onClick={onClose}
              className="px-4 py-2 text-xs font-bold text-slate-600 hover:text-slate-900 hover:bg-slate-200/70 rounded-xl transition-all cursor-pointer"
            >
              تذكيري لاحقاً
            </button>
          ) : (
            <div />
          )}

          {/* Action Buttons */}
          <div className="flex items-center gap-2">
            {status === 'idle' && (
              <button
                onClick={handleStartDownload}
                className="flex items-center gap-2 px-5 py-2.5 bg-gradient-to-r from-blue-600 to-indigo-600 hover:from-blue-700 hover:to-indigo-700 text-white font-bold text-xs rounded-xl shadow-md shadow-blue-500/20 hover:shadow-blue-500/30 transition-all cursor-pointer transform active:scale-95"
              >
                <Download size={15} />
                <span>تحديث الآن</span>
              </button>
            )}

            {status === 'error' && (
              <>
                <button
                  onClick={onClose}
                  className="px-3.5 py-2 text-xs font-bold text-slate-600 hover:bg-slate-200/70 rounded-xl transition-all cursor-pointer"
                >
                  إغلاق
                </button>
                <button
                  onClick={handleRetry}
                  className="flex items-center gap-1.5 px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white font-bold text-xs rounded-xl shadow transition-all cursor-pointer transform active:scale-95"
                >
                  <RefreshCw size={14} />
                  <span>إعادة المحاولة</span>
                </button>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default UpdateNotificationModal;
