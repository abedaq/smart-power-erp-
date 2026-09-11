import React, { useState } from 'react';
import { 
  LifeBuoy, 
  CloudUpload, 
  Download, 
  ShieldCheck, 
  CheckCircle2, 
  AlertCircle, 
  FileText, 
  Cpu, 
  Send
} from 'lucide-react';
import api from '../lib/api';

export const SupportDiagnostics: React.FC = () => {
  const [userNote, setUserNote] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [isExporting, setIsExporting] = useState(false);
  const [uploadSuccess, setUploadSuccess] = useState<string | null>(null);
  const [exportSuccess, setExportSuccess] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleCloudUpload = async () => {
    setIsUploading(true);
    setUploadSuccess(null);
    setErrorMessage(null);
    try {
      const res = await api.post('/system/diagnostics/upload', { user_note: userNote });
      if (res.data?.success) {
        setUploadSuccess(`تم إرسال تقرير التشخيص بنجاح إلى فريق الدعم الفني! الرقم المرجعي: ${res.data.reference_id}`);
        setUserNote('');
      } else {
        setErrorMessage(res.data?.message || 'حدث خطأ أثناء رفع التقرير.');
      }
    } catch (err: any) {
      setErrorMessage(err.response?.data?.message || err.message || 'فشل الاتصال بخادم الدعم الفني.');
    } finally {
      setIsUploading(false);
    }
  };

  const handleExportDesktop = async () => {
    setIsExporting(true);
    setExportSuccess(null);
    setErrorMessage(null);
    try {
      const res = await api.post('/system/diagnostics/export', { user_note: userNote });
      if (res.data?.success) {
        setExportSuccess(`تم حفظ ملف حزمة التشخيص بنجاح في: ${res.data.file_path}`);
      } else {
        setErrorMessage(res.data?.message || 'تعذر تصدير السجلات.');
      }
    } catch (err: any) {
      setErrorMessage(err.response?.data?.message || err.message || 'فشل تصدير السجلات.');
    } finally {
      setIsExporting(false);
    }
  };

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header Info Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-sky-950 to-slate-900 rounded-3xl p-6 sm:p-8 text-white shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-96 h-96 bg-sky-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 bg-white/10 rounded-full text-sky-300 text-xs font-bold border border-white/15">
              <LifeBuoy size={14} />
              <span>مركز التشخيص والدعم الفني الذكي</span>
            </div>
            <h2 className="text-2xl sm:text-3xl font-black tracking-tight">
              إرسال وتصدير تقارير فحص النظام
            </h2>
            <p className="text-slate-300 text-xs sm:text-sm max-w-xl font-medium leading-relaxed">
              إذا واجهت أي مشكلة أو استفسار، يمكنك بنقرة واحدة إرسال سجلات النظام المنقحة لفريق التطوير السحابي لتشخيص الخلل وتقديم الترقيع المناسب دون الحاجة لبرامج التحكم عن بعد.
            </p>
          </div>

          <div className="flex items-center gap-3">
            <div className="p-4 bg-white/10 backdrop-blur-md rounded-2xl border border-white/10 text-center">
              <FileText className="mx-auto text-sky-400 mb-1" size={24} />
              <div className="text-xs font-bold text-slate-300">سجلات آمنة ومشفّرة</div>
            </div>
          </div>
        </div>
      </div>

      {/* Main Action Card */}
      <div className="bg-white rounded-3xl p-6 sm:p-8 border-2 border-slate-200/80 shadow-sm space-y-6">
        <div className="border-b border-slate-100 pb-4">
          <h3 className="text-lg font-black text-slate-900 flex items-center gap-2">
            <Cpu size={20} className="text-sky-600" />
            <span>وصف المشكلة وتجهيز السجلات</span>
          </h3>
          <p className="text-xs text-slate-500 font-medium mt-1">
            يقوم النظام تلقائياً بدمج آخر سجلات الخادم ومحرك قاعدة البيانات وبيانات الإصدار.
          </p>
        </div>

        {/* User Note Input */}
        <div className="space-y-2">
          <label className="text-xs font-black text-slate-700 block">
            ملاحظة أو وصف مختصر للمشكلة (اختياري):
          </label>
          <textarea
            value={userNote}
            onChange={(e) => setUserNote(e.target.value)}
            placeholder="مثال: واجهت بطء عند النقر على طباعة الفواتير، أو حدث إغلاق مفاجئ أثناء المزامنة..."
            rows={3}
            className="w-full px-4 py-3 text-sm rounded-2xl border-2 border-slate-200 focus:border-sky-500 focus:ring-4 focus:ring-sky-500/10 transition-all font-medium resize-none"
          />
        </div>

        {/* Action Buttons */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
          {/* Cloud Upload Button */}
          <button
            onClick={handleCloudUpload}
            disabled={isUploading || isExporting}
            className="flex items-center justify-center gap-2.5 px-6 py-4 bg-gradient-to-r from-sky-600 to-blue-600 hover:from-sky-500 hover:to-blue-500 active:scale-95 text-white font-black text-sm rounded-2xl shadow-lg shadow-sky-500/25 transition-all cursor-pointer disabled:opacity-50"
          >
            {isUploading ? (
              <>
                <CloudUpload size={20} className="animate-bounce" />
                <span>جاري إرسال التقرير للسحابة...</span>
              </>
            ) : (
              <>
                <Send size={20} />
                <span>إرسال تقرير الدعم الفني سحابياً ☁️</span>
              </>
            )}
          </button>

          {/* Export to Desktop Button */}
          <button
            onClick={handleExportDesktop}
            disabled={isUploading || isExporting}
            className="flex items-center justify-center gap-2.5 px-6 py-4 bg-slate-800 hover:bg-slate-700 active:scale-95 text-white font-black text-sm rounded-2xl shadow-md transition-all cursor-pointer disabled:opacity-50"
          >
            {isExporting ? (
              <>
                <Download size={20} className="animate-bounce" />
                <span>جاري تصدير الحزمة...</span>
              </>
            ) : (
              <>
                <Download size={20} />
                <span>تصدير حزمة السجلات لسطح المكتب 💻</span>
              </>
            )}
          </button>
        </div>

        {/* Feedback Messages */}
        {uploadSuccess && (
          <div className="p-4 bg-emerald-50 border border-emerald-200 rounded-2xl flex items-start gap-3 text-emerald-800 text-sm font-bold animate-fadeIn">
            <CheckCircle2 size={20} className="text-emerald-600 shrink-0 mt-0.5" />
            <div>{uploadSuccess}</div>
          </div>
        )}

        {exportSuccess && (
          <div className="p-4 bg-blue-50 border border-blue-200 rounded-2xl flex items-start gap-3 text-blue-800 text-sm font-bold animate-fadeIn">
            <CheckCircle2 size={20} className="text-blue-600 shrink-0 mt-0.5" />
            <div>
              <p>{exportSuccess}</p>
              <p className="text-xs text-blue-600 font-normal mt-1">
                يمكنك الآن إرسال هذا الملف المضغوط إلى المطور مباشرة عبر واتساب.
              </p>
            </div>
          </div>
        )}

        {errorMessage && (
          <div className="p-4 bg-rose-50 border border-rose-200 rounded-2xl flex items-start gap-3 text-rose-800 text-sm font-bold animate-fadeIn">
            <AlertCircle size={20} className="text-rose-600 shrink-0 mt-0.5" />
            <div>{errorMessage}</div>
          </div>
        )}

        {/* Privacy & Safeguard Notice */}
        <div className="flex items-center gap-3 p-4 bg-slate-50 rounded-2xl border border-slate-200/80 text-slate-600 text-xs font-bold">
          <ShieldCheck size={20} className="text-emerald-600 shrink-0" />
          <span>
            🔒 أمان وخصوصية البيانات: يتم حجب كلمات المرور، والرموز السرية (Tokens)، والبيانات المالية تلقائياً قبل الإرسال؛ التقرير يتضمن فقط رسائل أخطاء النظام التقنية.
          </span>
        </div>
      </div>
    </div>
  );
};

export default SupportDiagnostics;
