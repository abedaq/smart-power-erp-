import React, { useState, useEffect } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { X, Copy, Check, RefreshCw, Smartphone, Wifi, Radio, ShieldCheck, Edit2 } from 'lucide-react';
import api from '../lib/api';

interface Props {
  isOpen: boolean;
  onClose: () => void;
}

interface NetworkAdapter {
  ip: string;
  name: string;
  type: string;
}

interface NetworkInfoResponse {
  success: boolean;
  local_ip: string;
  port: string;
  mobile_url: string;
  adapters?: NetworkAdapter[];
}

export const MobileConnectModal: React.FC<Props> = ({ isOpen, onClose }) => {
  const [selectedIP, setSelectedIP] = useState<string>('127.0.0.1');
  const [port, setPort] = useState<string>('3000');
  const [adapters, setAdapters] = useState<NetworkAdapter[]>([]);
  const [isEditing, setIsEditing] = useState<boolean>(false);
  const [customIP, setCustomIP] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(true);
  const [copied, setCopied] = useState<boolean>(false);

  const fetchNetworkInfo = async () => {
    try {
      setLoading(true);
      const res = await api.get('/system/network-info');
      const data: NetworkInfoResponse = res.data;

      if (data && data.success) {
        setPort(data.port || '3000');
        const detectedAdapters = data.adapters || [];
        setAdapters(detectedAdapters);

        // Priority 1: Hotspot (192.168.137.1) or Wi-Fi
        const hotspot = detectedAdapters.find(a => a.ip === '192.168.137.1' || a.type === 'hotspot');
        const wifi = detectedAdapters.find(a => a.type === 'wifi');

        if (hotspot) {
          setSelectedIP(hotspot.ip);
          setCustomIP(hotspot.ip);
        } else if (wifi) {
          setSelectedIP(wifi.ip);
          setCustomIP(wifi.ip);
        } else if (data.local_ip) {
          setSelectedIP(data.local_ip);
          setCustomIP(data.local_ip);
        } else if (detectedAdapters.length > 0) {
          setSelectedIP(detectedAdapters[0].ip);
          setCustomIP(detectedAdapters[0].ip);
        }
      } else {
        const host = window.location.hostname || '127.0.0.1';
        setSelectedIP(host);
        setCustomIP(host);
      }
    } catch (err: any) {
      console.warn('Network info fetch warning, using fallback:', err);
      const host = window.location.hostname || '127.0.0.1';
      setSelectedIP(host);
      setCustomIP(host);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen) {
      fetchNetworkInfo();
      setIsEditing(false);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const currentIP = isEditing ? customIP : selectedIP;
  const mobileUrl = `http://${currentIP}:${port}`;

  const handleCopy = () => {
    if (mobileUrl) {
      navigator.clipboard.writeText(mobileUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 backdrop-blur-sm p-4 animate-in fade-in duration-200" dir="rtl">
      <div className="bg-white rounded-3xl shadow-2xl border border-slate-100 max-w-lg w-full overflow-hidden">
        
        {/* Header */}
        <div className="bg-gradient-to-l from-blue-700 to-indigo-800 p-5 text-white relative">
          <button
            onClick={onClose}
            className="absolute top-4 left-4 p-1.5 text-white/80 hover:text-white bg-white/10 hover:bg-white/20 rounded-xl transition-all"
            title="إغلاق"
          >
            <X size={18} />
          </button>

          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-white/15 backdrop-blur rounded-2xl flex items-center justify-center border border-white/20 shadow-inner">
              <Smartphone size={24} className="text-amber-300 animate-bounce" />
            </div>
            <div>
              <h2 className="text-base font-black">ربط الجوال بالنظام (QR Code)</h2>
              <p className="text-blue-100 text-xs font-medium mt-0.5">
                امسح الرمز بكاميرا هاتفك لفتح البرنامج فوراً
              </p>
            </div>
          </div>
        </div>

        {/* Body */}
        <div className="p-5 space-y-4 text-center">

          {/* Network Adapter Selector */}
          {adapters.length > 0 && (
            <div className="space-y-1.5 text-right">
              <label className="text-xs font-bold text-slate-700 flex items-center justify-between">
                <span>اختر نوع اتصال الجوال بالكمبيوتر:</span>
                <span className="text-[10px] text-blue-600 font-bold">({adapters.length} شبكات مكتشفة)</span>
              </label>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {adapters.map((adapter) => {
                  const isSelected = !isEditing && selectedIP === adapter.ip;
                  const isHotspot = adapter.ip === '192.168.137.1' || adapter.type === 'hotspot';
                  return (
                    <button
                      key={adapter.ip}
                      type="button"
                      onClick={() => {
                        setSelectedIP(adapter.ip);
                        setCustomIP(adapter.ip);
                        setIsEditing(false);
                      }}
                      className={`p-2.5 rounded-2xl text-right text-xs transition-all border flex flex-col justify-between gap-1 relative ${
                        isSelected
                          ? 'bg-blue-50 border-blue-500 shadow-sm ring-2 ring-blue-500/20 text-blue-900 font-bold'
                          : 'bg-slate-50 hover:bg-slate-100 border-slate-200 text-slate-700 font-medium'
                      }`}
                    >
                      <div className="flex items-center justify-between w-full">
                        <span className="flex items-center gap-1.5 truncate">
                          {isHotspot ? (
                            <Radio size={14} className={isSelected ? 'text-amber-600' : 'text-slate-500'} />
                          ) : (
                            <Wifi size={14} className={isSelected ? 'text-blue-600' : 'text-slate-500'} />
                          )}
                          <span className="truncate">{adapter.name}</span>
                        </span>
                        {isSelected && <span className="w-2 h-2 rounded-full bg-blue-600"></span>}
                      </div>
                      <span className="font-mono text-[11px] font-bold text-slate-500 dir-ltr text-left" dir="ltr">
                        {adapter.ip}
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* QR Code Container */}
          <div className="bg-slate-50 border-2 border-dashed border-slate-200 rounded-3xl p-4 flex flex-col items-center justify-center relative shadow-inner">
            {loading ? (
              <div className="h-48 flex flex-col items-center justify-center gap-3 text-slate-400">
                <RefreshCw size={28} className="animate-spin text-blue-600" />
                <span className="text-xs font-bold">جاري الكشف عن الشبكات المتاحة...</span>
              </div>
            ) : (
              <div className="bg-white p-3 rounded-2xl shadow-md border border-slate-100">
                <QRCodeSVG
                  value={mobileUrl}
                  size={190}
                  level="M"
                  includeMargin={false}
                  imageSettings={{
                    src: "/icon.png",
                    x: undefined,
                    y: undefined,
                    height: 36,
                    width: 36,
                    excavate: true,
                  }}
                />
              </div>
            )}

            <div className="mt-3 flex items-center gap-2 text-[11px] font-bold text-emerald-700 bg-emerald-50 px-3 py-1 rounded-full border border-emerald-200">
              <Wifi size={13} className="text-emerald-600 animate-pulse" />
              <span>جاهز للاتصال المباشر على الآيبي: <strong className="font-mono" dir="ltr">{currentIP}</strong></span>
            </div>
          </div>

          {/* URL Display, Manual Edit & Copy */}
          <div className="space-y-1.5 text-right">
            <div className="flex items-center justify-between">
              <label className="text-xs font-bold text-slate-600 flex items-center gap-1">
                <span>رابط الجوال المباشر (URL):</span>
              </label>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setIsEditing(!isEditing)}
                  className="text-[11px] text-slate-600 hover:text-slate-900 flex items-center gap-1 font-bold"
                  title="تعديل الـ IP يدوياً"
                >
                  <Edit2 size={11} />
                  {isEditing ? 'إلغاء التعديل' : 'تعديل الـ IP'}
                </button>
                <button
                  type="button"
                  onClick={fetchNetworkInfo}
                  className="text-[11px] text-blue-600 hover:text-blue-800 flex items-center gap-1 font-bold"
                  title="إعادة فحص الشبكات"
                >
                  <RefreshCw size={11} className={loading ? 'animate-spin' : ''} />
                  تحديث
                </button>
              </div>
            </div>

            {isEditing ? (
              <div className="flex items-center gap-2 bg-slate-50 border border-blue-400 rounded-2xl p-1.5 px-3 ring-2 ring-blue-500/20">
                <span className="text-xs font-bold text-slate-400">http://</span>
                <input
                  type="text"
                  value={customIP}
                  onChange={(e) => setCustomIP(e.target.value.trim())}
                  placeholder="192.168.137.1"
                  className="font-mono text-xs font-bold text-slate-800 flex-1 bg-transparent focus:outline-none text-left"
                  dir="ltr"
                />
                <span className="text-xs font-bold text-slate-400">:3000</span>
              </div>
            ) : (
              <div className="flex items-center gap-2 bg-slate-50 border border-slate-200 rounded-2xl p-2 px-3">
                <span className="font-mono text-xs font-black text-slate-800 flex-1 text-left select-all truncate" dir="ltr">
                  {mobileUrl}
                </span>
                <button
                  type="button"
                  onClick={handleCopy}
                  className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center gap-1 shrink-0 ${
                    copied
                      ? 'bg-emerald-600 text-white'
                      : 'bg-blue-600 hover:bg-blue-700 text-white shadow-sm shadow-blue-500/20'
                  }`}
                >
                  {copied ? (
                    <>
                      <Check size={13} />
                      تم النسخ!
                    </>
                  ) : (
                    <>
                      <Copy size={13} />
                      نسخ
                    </>
                  )}
                </button>
              </div>
            )}
          </div>

          {/* Quick Guidance */}
          <div className="bg-blue-50/70 border border-blue-100 rounded-2xl p-3 text-right text-[11px] text-blue-900 space-y-1">
            <p className="font-black text-blue-950 flex items-center gap-1.5">
              <ShieldCheck size={14} className="text-blue-600" />
              طرق ربط الجوال بالكمبيوتر:
            </p>
            <ul className="list-disc list-inside space-y-0.5 text-blue-800 pr-1">
              <li><strong>نقطة اتصال اللابتوب (Hotspot):</strong> اربط الجوال بنقطة اتصال اللابتوب واختر <code className="font-mono bg-blue-100/70 px-1 rounded">192.168.137.1</code></li>
              <li><strong>راوتر الواي فاي (Wi-Fi):</strong> اربط الجوال واللابتوب بنفس الراوتر وامسح الباركود مباشرة.</li>
            </ul>
          </div>

        </div>
      </div>
    </div>
  );
};

