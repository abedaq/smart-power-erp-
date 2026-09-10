import React, { useState } from 'react';
import { useLicense } from '../context/LicenseContext';
import { ShieldAlert, Key, CheckCircle, Copy, AlertTriangle, RefreshCw, Radio } from 'lucide-react';

interface Props {
  isOpen: boolean;
}

export const LicenseActivationModal: React.FC<Props> = ({ isOpen }) => {
  const { license, hwid, activate, activateEmergency } = useLicense();
  const [licenseKey, setLicenseKey] = useState('');
  const [emergencyCode, setEmergencyCode] = useState('');
  const [mode, setMode] = useState<'online' | 'emergency'>('online');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  if (!isOpen) return null;

  const handleCopyHWID = () => {
    if (hwid) {
      navigator.clipboard.writeText(hwid);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleOnlineSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!licenseKey.trim()) {
      setErrorMsg('يرجى إدخال مفتاح الترخيص');
      return;
    }
    setLoading(true);
    setErrorMsg(null);
    try {
      await activate(licenseKey);
    } catch (err: any) {
      setErrorMsg(err.message || 'فشل التفعيل عبر السحابة');
    } finally {
      setLoading(false);
    }
  };

  const handleEmergencySubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!emergencyCode.trim()) {
      setErrorMsg('يرجى إدخال كود الطوارئ');
      return;
    }
    setLoading(true);
    setErrorMsg(null);
    try {
      await activateEmergency(emergencyCode);
    } catch (err: any) {
      setErrorMsg(err.message || 'فشل تفعيل كود الطوارئ');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-md p-4 animate-in fade-in duration-200" dir="rtl">
      <div className="bg-white rounded-3xl shadow-2xl border border-slate-100 max-w-lg w-full overflow-hidden">
        {/* Modal Header */}
        <div className="bg-gradient-to-l from-blue-700 to-indigo-800 p-6 text-white text-center relative">
          <div className="w-14 h-14 bg-white/10 backdrop-blur rounded-2xl flex items-center justify-center mx-auto mb-3 border border-white/20 shadow-inner">
            <ShieldAlert size={32} className="text-amber-300 animate-pulse" />
          </div>
          <h2 className="text-xl font-black">تفعيل اشتراك SmartPower ERP</h2>
          <p className="text-blue-100 text-xs mt-1 font-medium">
            النظام مقفل ومحمي ببصمة العتاد السحابية
          </p>
        </div>

        {/* Modal Body */}
        <div className="p-6 space-y-5">
          {/* Status Message */}
          {license?.error_message && (
            <div className="bg-rose-50 border border-rose-200 p-3.5 rounded-2xl flex items-start gap-3 text-xs text-rose-900">
              <AlertTriangle size={18} className="text-rose-600 shrink-0 mt-0.5" />
              <div>
                <p className="font-bold">حالة النظام الحالية:</p>
                <p className="text-rose-700 mt-0.5">{license.error_message}</p>
              </div>
            </div>
          )}

          {/* Mode Switcher */}
          <div className="flex bg-slate-100 p-1 rounded-2xl text-xs font-bold text-slate-600">
            <button
              type="button"
              onClick={() => { setMode('online'); setErrorMsg(null); }}
              className={`flex-1 py-2.5 rounded-xl transition-all flex items-center justify-center gap-1.5 ${
                mode === 'online'
                  ? 'bg-white text-blue-700 shadow-sm font-black'
                  : 'hover:text-slate-900'
              }`}
            >
              <Key size={15} />
              التفعيل عبر السحابة (أونلاين)
            </button>
            <button
              type="button"
              onClick={() => { setMode('emergency'); setErrorMsg(null); }}
              className={`flex-1 py-2.5 rounded-xl transition-all flex items-center justify-center gap-1.5 ${
                mode === 'emergency'
                  ? 'bg-white text-amber-700 shadow-sm font-black'
                  : 'hover:text-slate-900'
              }`}
            >
              <Radio size={15} />
              كود طوارئ أوفلاين
            </button>
          </div>

          {/* Online Form */}
          {mode === 'online' && (
            <form onSubmit={handleOnlineSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  مفتاح الترخيص (License Key)
                </label>
                <div className="relative">
                  <input
                    type="text"
                    value={licenseKey}
                    onChange={(e) => setLicenseKey(e.target.value.toUpperCase())}
                    placeholder="SP-2026-XXXX-XXXX"
                    className="w-full px-4 py-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-mono text-center tracking-widest font-bold focus:bg-white focus:border-blue-500 focus:ring-2 focus:ring-blue-100 outline-none uppercase"
                    disabled={loading}
                    autoFocus
                  />
                </div>
                <p className="text-[11px] text-slate-400 mt-1">
                  أدخل المفتاح المستلم من مزود الخدمة، وسيتم ربطه تلقائياً بهذا الجهاز.
                </p>
              </div>

              {errorMsg && (
                <div className="p-3 bg-rose-50 border border-rose-200 text-rose-800 text-xs font-bold rounded-xl text-center">
                  {errorMsg}
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3.5 bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white rounded-2xl font-black text-sm shadow-lg shadow-blue-500/25 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <RefreshCw size={16} className="animate-spin" />
                    جاري التحقق والربط السحابي...
                  </>
                ) : (
                  <>
                    <CheckCircle size={16} />
                    تفعيل النظام والبدء
                  </>
                )}
              </button>
            </form>
          )}

          {/* Emergency Offline Form */}
          {mode === 'emergency' && (
            <form onSubmit={handleEmergencySubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  كود طوارئ الأوفلاين (Emergency Code)
                </label>
                <input
                  type="text"
                  value={emergencyCode}
                  onChange={(e) => setEmergencyCode(e.target.value.toUpperCase())}
                  placeholder="EMG-XXXXXXXXXXXXXXXX"
                  className="w-full px-4 py-3 bg-slate-50 border border-slate-200 rounded-2xl text-sm font-mono text-center tracking-widest font-bold focus:bg-white focus:border-amber-500 focus:ring-2 focus:ring-amber-100 outline-none uppercase"
                  disabled={loading}
                  autoFocus
                />
                <p className="text-[11px] text-amber-700 mt-1">
                  استخدم هذا الخيار في حال انقطاع الإنترنت التام عن المحطة بعد التواصل مع الإدارة.
                </p>
              </div>

              {errorMsg && (
                <div className="p-3 bg-rose-50 border border-rose-200 text-rose-800 text-xs font-bold rounded-xl text-center">
                  {errorMsg}
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3.5 bg-amber-600 hover:bg-amber-700 active:bg-amber-800 text-white rounded-2xl font-black text-sm shadow-lg shadow-amber-500/25 transition-all flex items-center justify-center gap-2 disabled:opacity-50"
              >
                {loading ? (
                  <>
                    <RefreshCw size={16} className="animate-spin" />
                    جاري تفعيل كود الطوارئ...
                  </>
                ) : (
                  <>
                    <CheckCircle size={16} />
                    تفعيل كود الطوارئ
                  </>
                )}
              </button>
            </form>
          )}

          {/* HWID Card for Technical Support */}
          <div className="bg-slate-50 border border-slate-200/80 p-3.5 rounded-2xl">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-[10px] font-bold text-slate-400 block">معرف عتاد هذا الكمبيوتر (HWID):</span>
                <span className="font-mono text-xs font-black text-slate-800 select-all">{hwid || 'جاري القراءة...'}</span>
              </div>
              <button
                type="button"
                onClick={handleCopyHWID}
                className="p-2 text-slate-500 hover:text-blue-600 hover:bg-blue-50 rounded-xl transition-all flex items-center gap-1 text-[11px] font-bold border border-slate-200"
                title="نسخ بصمة الجهاز"
              >
                <Copy size={13} />
                {copied ? 'تم النسخ!' : 'نسخ'}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
