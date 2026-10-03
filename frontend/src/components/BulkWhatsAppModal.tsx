import React from 'react';
import { X, Send, AlertTriangle, Clock, ListChecks, Activity } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

interface BulkWhatsAppModalProps {
  isOpen: boolean;
  onClose: () => void;
  selectedIds: number[];
  onStartBulkSend: () => Promise<void>;
  isSending: boolean;
  sentCount: number;
}

export const BulkWhatsAppModal: React.FC<BulkWhatsAppModalProps> = ({
  isOpen,
  onClose,
  selectedIds,
  onStartBulkSend,
  isSending,
  sentCount,
}) => {
  const navigate = useNavigate();
  const count = selectedIds.length;
  // Approximation based on server-side limits: ~3 seconds avg delay + 10s cooldown per 30 messages.
  const estimatedSeconds = (count * 3) + (Math.floor(count / 30) * 10);
  const estimatedMinutes = Math.ceil(estimatedSeconds / 60);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm rtl">
      <div className="bg-white w-full max-w-lg rounded-2xl shadow-xl overflow-hidden animate-in fade-in zoom-in-95 duration-200">
        <div className="flex justify-between items-center p-4 border-b border-slate-200 bg-emerald-50">
          <div className="flex items-center gap-2 text-emerald-800">
            <Send className="w-5 h-5" />
            <h3 className="font-bold text-lg">إرسال الفواتير عبر الواتساب</h3>
          </div>
          {!isSending && (
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-slate-600 hover:bg-slate-200 p-1 rounded-lg transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          )}
        </div>

        <div className="p-6 space-y-5">
          {/* Stats Cards */}
          <div className="grid grid-cols-2 gap-3">
            <div className="bg-slate-50 border border-slate-200 p-3 rounded-xl flex items-center gap-3">
              <div className="p-2 bg-blue-100 text-blue-600 rounded-lg">
                <ListChecks className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-slate-500 font-semibold">عدد الفواتير المحددة</p>
                <p className="font-mono text-xl font-bold text-slate-800">{count}</p>
              </div>
            </div>
            
            <div className="bg-slate-50 border border-slate-200 p-3 rounded-xl flex items-center gap-3">
              <div className="p-2 bg-purple-100 text-purple-600 rounded-lg">
                <Clock className="w-5 h-5" />
              </div>
              <div>
                <p className="text-xs text-slate-500 font-semibold">الوقت التقريبي</p>
                <p className="font-mono text-xl font-bold text-slate-800">~{estimatedMinutes} دقيقة</p>
              </div>
            </div>
          </div>

          {/* Warning Banner */}
          <div className="bg-amber-50 border border-amber-200 p-3.5 rounded-xl flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
            <div className="text-sm text-amber-800 font-medium leading-relaxed">
              <strong>تحذير هام لتجنب الحظر:</strong> النظام سيقوم بإدراج الرسائل في الطابور وإرسالها ببطء مع فترات راحة مبرمجة. 
              الرجاء عدم إغلاق البرنامج حتى تنتهي العملية لتفادي توقف الطابور.
            </div>
          </div>

          {/* Progress Section */}
          {isSending && (
            <div className="space-y-2 mt-4 border-t border-slate-200 pt-4">
              <div className="flex justify-between items-center text-sm font-bold text-slate-700">
                <span>جاري إدراج الفواتير في الطابور...</span>
                <span className="font-mono">{sentCount} / {count}</span>
              </div>
              <div className="h-3 w-full bg-slate-100 rounded-full overflow-hidden border border-slate-200">
                <div 
                  className="h-full bg-emerald-500 transition-all duration-300" 
                  style={{ width: `${(sentCount / count) * 100}%` }}
                ></div>
              </div>
            </div>
          )}
        </div>

        {/* Footer Actions */}
        <div className="p-4 bg-slate-50 border-t border-slate-200 flex justify-between items-center gap-3">
          <button
            type="button"
            onClick={() => {
              onClose();
              navigate('/whatsapp');
            }}
            className="px-4 py-2 bg-slate-200 hover:bg-slate-300 text-slate-700 font-bold rounded-lg text-sm transition-colors flex items-center gap-2"
          >
            <Activity className="w-4 h-4" />
            فتح سجل الواتساب
          </button>
          
          <div className="flex gap-2">
            {!isSending && (
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 bg-white border border-slate-300 hover:bg-slate-50 text-slate-700 font-bold rounded-lg text-sm transition-colors"
              >
                إلغاء
              </button>
            )}
            
            <button
              type="button"
              onClick={onStartBulkSend}
              disabled={isSending || count === 0}
              className="px-6 py-2 bg-emerald-600 hover:bg-emerald-700 text-white font-bold rounded-lg text-sm transition-colors flex items-center gap-2 disabled:opacity-50"
            >
              {isSending ? (
                <>
                  <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"></div>
                  جاري الإدراج...
                </>
              ) : (
                <>
                  <Send className="w-4 h-4" />
                  موافق، ابدأ الإرسال
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
