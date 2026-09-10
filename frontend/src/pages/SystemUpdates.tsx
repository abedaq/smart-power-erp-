import React from 'react';
import { 
  Sparkles, 
  RefreshCw, 
  CheckCircle2, 
  ShieldCheck, 
  Cpu, 
  HardDrive, 
  Download, 
  Clock, 
  Layers
} from 'lucide-react';
import { useUpdate } from '../context/UpdateContext';

export const SystemUpdates: React.FC = () => {
  const { 
    updateInfo, 
    hasUpdate, 
    isChecking, 
    openModal, 
    checkForUpdates 
  } = useUpdate();

  return (
    <div className="space-y-6" dir="rtl">
      {/* Header Info Banner */}
      <div className="bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 rounded-3xl p-6 sm:p-8 text-white shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-96 h-96 bg-blue-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-0 w-96 h-96 bg-purple-500/10 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 bg-white/10 rounded-full text-blue-300 text-xs font-bold border border-white/15">
              <Cpu size={14} />
              <span>نظام التحديث التلقائي الذري (Atomic Auto-Updater)</span>
            </div>
            <h2 className="text-2xl sm:text-3xl font-black tracking-tight">
              إدارة وتحديثات محرك SmartPower ERP
            </h2>
            <p className="text-slate-300 text-xs sm:text-sm max-w-xl font-medium leading-relaxed">
              تحقق من أحدث الترقيات البرمجية والتحسينات الأمنية لتطبيق سطح المكتب، وتطبيقها بنقرة واحدة بأمان تام.
            </p>
          </div>

          <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
            <button
              onClick={() => checkForUpdates(true)}
              disabled={isChecking}
              className="flex items-center justify-center gap-2 px-6 py-3.5 bg-blue-600 hover:bg-blue-500 active:scale-95 text-white font-black text-sm rounded-2xl shadow-lg shadow-blue-500/30 transition-all cursor-pointer disabled:opacity-50"
            >
              <RefreshCw size={18} className={isChecking ? 'animate-spin' : ''} />
              <span>{isChecking ? 'جاري التحقق...' : 'التحقق من وجود تحديثات'}</span>
            </button>

            {hasUpdate && (
              <button
                onClick={openModal}
                className="flex items-center justify-center gap-2 px-6 py-3.5 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 text-white font-black text-sm rounded-2xl shadow-lg shadow-emerald-500/30 animate-pulse transition-all cursor-pointer"
              >
                <Download size={18} />
                <span>تثبيت التحديث الآن (v{updateInfo?.latest_version})</span>
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Grid of System Metadata Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
        {/* Current Version Card */}
        <div className="bg-white rounded-3xl p-6 border-2 border-slate-200/80 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-black text-slate-500">الإصدار المثبت حالياً</span>
            <div className="p-2.5 bg-blue-50 text-blue-600 rounded-2xl">
              <Layers size={20} />
            </div>
          </div>
          <div>
            <div className="text-3xl font-black font-mono text-slate-900">
              v{updateInfo?.current_version || '1.0.0'}
            </div>
            <div className="flex items-center gap-1.5 mt-2 text-xs font-bold text-slate-500">
              <Clock size={14} />
              <span>SmartPower Desktop Standalone</span>
            </div>
          </div>
        </div>

        {/* Update Status Card */}
        <div className="bg-white rounded-3xl p-6 border-2 border-slate-200/80 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-black text-slate-500">حالة التحديثات السحابية</span>
            <div className={`p-2.5 rounded-2xl ${hasUpdate ? 'bg-amber-50 text-amber-600' : 'bg-emerald-50 text-emerald-600'}`}>
              {hasUpdate ? <Sparkles size={20} className="animate-pulse" /> : <CheckCircle2 size={20} />}
            </div>
          </div>
          <div>
            <div className={`text-xl font-black ${hasUpdate ? 'text-amber-700' : 'text-emerald-700'}`}>
              {hasUpdate ? `يتوفر إصدار أحدث (v${updateInfo?.latest_version})` : 'أحدث إصدار مثبت ومحدث'}
            </div>
            <p className="text-slate-500 text-xs mt-1.5 font-medium">
              {hasUpdate ? 'اضغط على زر التحديث لتنزيل الحزمة فوراً' : 'نظامك يعمل بأحدث إصدار رسمي مستقر ومؤمّن'}
            </p>
          </div>
        </div>

        {/* Critical Safety Card */}
        <div className="bg-white rounded-3xl p-6 border-2 border-slate-200/80 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-black text-slate-500">سلامة وحماية البيانات</span>
            <div className="p-2.5 bg-emerald-50 text-emerald-600 rounded-2xl">
              <ShieldCheck size={20} />
            </div>
          </div>
          <div>
            <div className="text-xl font-black text-slate-900">
              أمان مضمون 100%
            </div>
            <p className="text-slate-500 text-xs mt-1.5 font-medium leading-relaxed">
              عملية التحديث تستبدل الملف التنفيذي فقط دون المساس بقاعدة البيانات أو النسخ إطلاقاً.
            </p>
          </div>
        </div>
      </div>

      {/* Latest Release Changelog Card */}
      {hasUpdate && updateInfo && (
        <div className="bg-white rounded-3xl p-6 sm:p-8 border-2 border-blue-200 shadow-md space-y-4">
          <div className="flex items-center justify-between border-b border-slate-100 pb-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-100 text-blue-700 rounded-xl">
                <Sparkles size={20} />
              </div>
              <div>
                <h3 className="font-black text-slate-900 text-base">سجل التغييرات في الإصدار الجديد v{updateInfo.latest_version}</h3>
                <p className="text-xs text-slate-500 mt-0.5">تفاصيل ومميزات الترقية الرسمية</p>
              </div>
            </div>

            <button
              onClick={openModal}
              className="px-5 py-2.5 bg-blue-600 hover:bg-blue-700 text-white font-bold text-xs rounded-xl shadow transition-all cursor-pointer"
            >
              عرض نافذة التحديث
            </button>
          </div>

          <div className="bg-slate-50 p-5 rounded-2xl border border-slate-200 space-y-2 text-xs text-slate-700 leading-relaxed font-medium">
            {updateInfo.changelog ? (
              updateInfo.changelog.split('\n').map((line, idx) => (
                <div key={idx} className="flex items-start gap-2">
                  <span className="text-blue-600 font-bold">•</span>
                  <span>{line.trim()}</span>
                </div>
              ))
            ) : (
              <p className="text-slate-500">تحسينات شاملة في الأداء والسرعة والأمان.</p>
            )}
          </div>
        </div>
      )}

      {/* Technical Architecture Info */}
      <div className="bg-slate-100/80 rounded-3xl p-6 border-2 border-slate-200 text-slate-600 text-xs space-y-3">
        <div className="font-bold text-slate-800 flex items-center gap-2">
          <HardDrive size={16} className="text-slate-500" />
          <span>معلومات البنية التقنية للتطبيق:</span>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 pt-1 font-medium">
          <div className="bg-white p-3 rounded-xl border border-slate-200">
            <span className="text-slate-400 block text-[11px]">محرك الخادم:</span>
            <span className="font-bold text-slate-800">Go Fiber High-Performance</span>
          </div>
          <div className="bg-white p-3 rounded-xl border border-slate-200">
            <span className="text-slate-400 block text-[11px]">محرك قاعدة البيانات:</span>
            <span className="font-bold text-slate-800">Embedded PostgreSQL Engine</span>
          </div>
          <div className="bg-white p-3 rounded-xl border border-slate-200">
            <span className="text-slate-400 block text-[11px]">محرك الواجهة:</span>
            <span className="font-bold text-slate-800">React 19 + Microsoft WebView2</span>
          </div>
          <div className="bg-white p-3 rounded-xl border border-slate-200">
            <span className="text-slate-400 block text-[11px]">آلية التحديث:</span>
            <span className="font-bold text-slate-800">Windows Atomic Hot-Swap</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default SystemUpdates;
