import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getSettings } from '../../services/settings.service';
import { sendInvoiceWhatsApp } from '../../services/invoice.service';
import type { ComputedGridRow } from '../../types/excelGrid.types';
import { buildWhatsAppText, formatYemeniPhone } from '../../types/excelGrid.types';
import { formatDateOnly, safeCopyToClipboard, formatStationPhones, formatBankAccount } from '../../utils/formatters';
import { printElementViaIframe } from '../../utils/printUtils';
import { StationLogo } from '../StationLogo';
import { Zap, X, Printer, Copy, Send, Check, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';

export interface InvoiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  row: ComputedGridRow | null;
  period?: string;
  onSendSuccess?: (id: number) => void;
}

export const InvoiceModal: React.FC<InvoiceModalProps> = ({
  isOpen,
  onClose,
  row,
  period = 'الشهر الحالي',
  onSendSuccess,
}) => {
  const [copied, setCopied] = useState(false);
  const [isSendingWhatsApp, setIsSendingWhatsApp] = useState(false);
  const { data: settings } = useQuery({ queryKey: ['settings'], queryFn: getSettings });

  if (!isOpen || !row) return null;

  const stationName = settings?.station_name && settings.station_name !== 'محطة الطاقة الذكية'
    ? settings.station_name
    : 'محطة الضياء لتوليد الطاقة الكهربائية';

  const stationPhone = formatStationPhones(settings?.station_phone, settings?.station_phone_alt);
  const bankAccountNum = formatBankAccount(settings?.bank_accounts);

  const defaultPolicyText = `o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.
o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.
o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان الف ريال
o يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة.
o سعر الكيلوواط/ ساعة 1500 ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.`;

  const policyLines = (settings?.invoice_policy_text || defaultPolicyText)
    .split('\n')
    .filter((l: string) => l.trim().length > 0);

  const cleanPeriod = (period || 'الدورة الحالية').replace(/^دورة\s*/, '').trim();

  const handlePrint = () => {
    const custName = row.name || 'مشترك';
    const subNo = row.subNumber || row.id;
    const cleanPeriod = period ? `_${period}` : '';
    printElementViaIframe(
      'printable-official-invoice-grid',
      `فاتورة_${custName}_${subNo}${cleanPeriod}`,
      { orientation: 'portrait', pageSize: 'A4', margin: '5mm' }
    );
  };

  const handleCopy = async () => {
    try {
      const text = buildWhatsAppText(row, period);
      const ok = await safeCopyToClipboard(text);
      if (ok) {
        setCopied(true);
        toast.success('تم نسخ نص رسالة الواتساب بنجاح');
        setTimeout(() => setCopied(false), 2500);
      } else {
        toast.error('فشل نسخ نص الفاتورة');
      }
    } catch (err) {
      toast.error('فشل نسخ نص الفاتورة');
    }
  };

  const handleSendWhatsApp = async () => {
    const formattedPhone = formatYemeniPhone(row.phone);
    if (!formattedPhone || formattedPhone.length < 9) {
      toast.error('يرجى التأكد من كتابة رقم هاتف يمني صحيح للمشترك');
      return;
    }

    if (!row.id) {
      toast.error('معرّف الفاتورة غير متوفر للإرسال');
      return;
    }

    setIsSendingWhatsApp(true);
    const loadToast = toast.loading('جاري إرسال الفاتورة عبر واتساب...');
    try {
      const res = await sendInvoiceWhatsApp(row.id);
      toast.success(res?.message || `تم إرسال الفاتورة إلى واتساب المشترك (${row.name}) بنجاح!`, { id: loadToast });
      if (onSendSuccess) {
        onSendSuccess(row.id);
      }
      onClose();
    } catch (err: any) {
      const errorMsg = err.response?.data?.message || err.message || 'خدمة الواتساب غير متصلة بالهاتف حالياً. يرجى ربط الهاتف أولاً من صفحة الإعدادات.';
      toast.error(errorMsg, { id: loadToast, duration: 5000 });
    } finally {
      setIsSendingWhatsApp(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-slate-900/60 flex items-center justify-center z-50 p-2 sm:p-4 backdrop-blur-sm overflow-y-auto">
      <div className="bg-white border border-slate-300 rounded-3xl w-full max-w-5xl overflow-hidden shadow-2xl space-y-4 text-slate-900 text-right my-4 max-h-[95vh] flex flex-col">
        
        {/* Top Controls Bar */}
        <div className="bg-slate-100 px-6 py-3.5 border-b border-slate-200 flex justify-between items-center no-print">
          <div className="flex items-center gap-2">
            <Zap className="text-blue-600" size={20} />
            <h2 className="text-base font-bold text-slate-900">معاينة نموذج الفاتورة المعتمد (الكعب المزدوج)</h2>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handlePrint}
              className="bg-blue-600 hover:bg-blue-700 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-blue-500/20"
            >
              <Printer size={15} />
              <span>طباعة / حفظ PDF</span>
            </button>

            <button
              type="button"
              onClick={handleCopy}
              className="bg-slate-700 hover:bg-slate-800 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 transition-all shadow-md shadow-slate-700/20"
            >
              {copied ? (
                <>
                  <Check size={15} className="text-emerald-400" />
                  <span>تم النسخ!</span>
                </>
              ) : (
                <>
                  <Copy size={15} />
                  <span>نسخ نص الواتس</span>
                </>
              )}
            </button>

            <button
              type="button"
              onClick={() => {
                if (row && onSendSuccess) onSendSuccess(row.id);
                toast.success(`تم اعتماد بيانات المشترك وترحيله للفوترة والتحصيل`);
                onClose();
              }}
              className="bg-emerald-700 hover:bg-emerald-800 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-emerald-700/20"
              title="موافق على الاعتماد والترحيل المباشر"
            >
              <Check size={15} />
              <span>موافق واعتماد</span>
            </button>

            <button
              type="button"
              onClick={handleSendWhatsApp}
              disabled={isSendingWhatsApp}
              className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-60 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-emerald-500/20"
            >
              {isSendingWhatsApp ? (
                <Loader2 size={15} className="animate-spin" />
              ) : (
                <Send size={15} />
              )}
              <span>{isSendingWhatsApp ? 'جاري الإرسال...' : 'إرسال واتساب'}</span>
            </button>

            <button
              type="button"
              onClick={onClose}
              className="text-slate-400 hover:text-slate-800 transition-colors p-1.5 rounded-xl hover:bg-slate-200"
            >
              <X size={20} />
            </button>
          </div>
        </div>

        {/* Printable Official Invoice Container (Strict match to photo_5769554780358381104_y.jpg) */}
        <div className="p-4 overflow-y-auto flex-1 text-right">
          <div
            id="printable-official-invoice-grid"
            className="bg-white text-black font-sans mx-auto w-full max-w-[960px] text-right leading-tight text-xs p-1"
            dir="rtl"
          >
            {/* Outer Thick Black Frame */}
            <div className="border-2 border-black p-2">
              
              {/* 2-Part Grid: Right = Collector Coupon (col-span-5), Left = Main Invoice (col-span-7) */}
              <div className="grid grid-cols-12 gap-0 items-stretch">
                
                {/* Part 1 (RIGHT SIDE): Collector Coupon (~40% Width) */}
                <div className="col-span-5 pl-3 pr-1 flex flex-col justify-between">
                  <div>
                    {/* Header */}
                    <div className="flex items-start justify-between border-b-2 border-black pb-1.5 mb-2">
                      <div className="text-center flex-1">
                        <h2 className="text-xs font-black text-black">{stationName}</h2>
                        <div className="text-xs font-black text-blue-700 font-mono dir-ltr my-0.5">{stationPhone}</div>
                      </div>
                      <div className="pt-0.5">
                        <StationLogo size={44} />
                      </div>
                    </div>

                    {/* Customer Info */}
                    <div className="space-y-1 text-[10px] font-black mb-2">
                      <div>
                        <span>اسم المشترك : </span>
                        <span className="font-black text-black">{row.name || '-'}</span>
                      </div>
                      <div>
                        <span>العنوان : </span>
                        <span>{row.address || '-'}</span>
                      </div>
                      <div>
                        <span>رقم المشترك : </span>
                        <span className="font-mono font-black">{row.subNumber || '-'}</span>
                      </div>
                      <div>
                        <span>رقم العداد : </span>
                        <span className="font-mono font-black">{row.meterNumber || '-'}</span>
                      </div>
                    </div>

                    {/* Red & Blue Cycle Title */}
                    <div className="text-center font-black text-[10px] my-2">
                      <span className="text-red-600">فاتورة استهلاك كهرباء دورة </span>
                      <span className="text-blue-900">{cleanPeriod}</span>
                    </div>

                    {/* Coupon Table (5 Columns) */}
                    <table className="w-full border-collapse text-center text-[9px] border-2 border-black mb-2">
                      <thead>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th colSpan={2} className="border border-black py-1">قــــــراءة العداد</th>
                          <th rowSpan={2} className="border border-black py-1">الفارق</th>
                          <th rowSpan={2} className="border border-black py-1">متأخرات وغرامات</th>
                          <th rowSpan={2} className="border border-black py-1">الاجمالي</th>
                        </tr>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th className="border border-black py-0.5">ق.السابقة</th>
                          <th className="border border-black py-0.5">ق.الحالية</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr className="font-black text-[10px]">
                          <td className="border border-black py-1 font-mono">{Number(row.prevReading || 0) > 0 ? Number(row.prevReading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.currReading || 0) > 0 ? Number(row.currReading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.units || 0) > 0 ? Number(row.units).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.arrears || 0) > 0 ? Number(row.arrears).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.totalDue || 0) > 0 ? Number(row.totalDue).toLocaleString('en-US') : ''}</td>
                        </tr>
                      </tbody>
                    </table>

                    {/* Payment & Remaining Breakdown in Coupon */}
                    {Number(row.paidAmount || 0) > 0 && (
                      <div className="border border-black bg-slate-50 p-1 mb-2 text-[9px] font-black space-y-0.5 text-right">
                        <div className="flex justify-between">
                          <span>المبلغ المسدد:</span>
                          <span className="font-mono text-emerald-800">{Number(row.paidAmount).toLocaleString('en-US')} ر.ي</span>
                        </div>
                        <div className="flex justify-between border-t border-black/40 pt-0.5">
                          <span>{(Number(row.totalDue || 0) - Number(row.paidAmount || 0)) <= 0 ? 'رصيد دائن لك:' : 'المتبقي عليك:'}</span>
                          <span className={`font-mono ${(Number(row.totalDue || 0) - Number(row.paidAmount || 0)) > 0 ? 'text-red-700' : 'text-emerald-700'}`}>
                            {(Number(row.totalDue || 0) - Number(row.paidAmount || 0)) > 0
                              ? `+${(Number(row.totalDue || 0) - Number(row.paidAmount || 0)).toLocaleString('en-US')}`
                              : (Number(row.totalDue || 0) - Number(row.paidAmount || 0)) < 0
                              ? `-${Math.abs(Number(row.totalDue || 0) - Number(row.paidAmount || 0)).toLocaleString('en-US')}`
                              : '0 (خالص)'} ر.ي
                          </span>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Footer Signatures */}
                  <div className="pt-2 text-[10px] font-black mt-2">
                    <div className="flex justify-between items-center px-2">
                      <div className="text-center">
                        <div>المحصل</div>
                        <div className="text-slate-400 text-xs mt-1">....................</div>
                      </div>
                      <div className="text-center">
                        <div>الحسابات</div>
                        <div className="text-slate-400 text-xs mt-1">....................</div>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Part 2 (LEFT SIDE): Main Invoice (~60% Width) */}
                <div className="col-span-7 border-r-2 border-black pr-3 pl-1 flex flex-col justify-between">
                  <div>
                    {/* Header */}
                    <div className="flex items-start justify-between border-b-2 border-black pb-1.5 mb-2">
                      <div className="text-center flex-1">
                        <h1 className="text-base font-black text-black">{stationName}</h1>
                        <div className="text-sm font-black text-blue-700 font-mono tracking-wider dir-ltr my-0.5">{stationPhone}</div>
                        <div className="text-[11px] font-black text-black">يمكنك الإيداع على الحساب {bankAccountNum}</div>
                      </div>
                      <div className="pt-0.5">
                        <StationLogo size={56} />
                      </div>
                    </div>

                    {/* Customer Info */}
                    <div className="text-[11px] font-black space-y-1 mb-2">
                      <div className="flex justify-between items-center">
                        <div>
                          <span>اسم المشترك : </span>
                          <span className="font-black text-black">{row.name || '-'}</span>
                        </div>
                        <div className="font-mono text-black">
                          <span>رقم الفاتورة : </span>
                          <span>{row.id}</span>
                        </div>
                      </div>

                      <div>
                        <span>العنوان : </span>
                        <span>{row.address || '-'}</span>
                      </div>

                      <div>
                        <span>رقم المشترك : </span>
                        <span className="font-mono font-black">{row.subNumber || '-'}</span>
                      </div>

                      <div className="flex justify-between items-center">
                        <div>
                          <span>رقم العداد : </span>
                          <span className="font-mono font-black">{row.meterNumber || '-'}</span>
                        </div>
                        <div className="font-mono pl-4">
                          <span>رقم خط السير : </span>
                          <span>{row.route || '-'}</span>
                        </div>
                      </div>
                    </div>

                    {/* Red & Blue Cycle Title */}
                    <div className="text-center font-black text-xs my-2">
                      <span className="text-red-600">فاتورة استهلاك كهرباء دورة </span>
                      <span className="text-blue-900">{cleanPeriod}</span>
                    </div>

                    {/* Table (7 Columns) */}
                    <table className="w-full border-collapse text-center text-[10px] border-2 border-black mb-2">
                      <thead>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th colSpan={2} className="border border-black py-1">قــــــراءة العداد</th>
                          <th rowSpan={2} className="border border-black py-1">الفارق</th>
                          <th rowSpan={2} className="border border-black py-1">اشتراك</th>
                          <th rowSpan={2} className="border border-black py-1">القيمـة</th>
                          <th rowSpan={2} className="border border-black py-1">متأخرات</th>
                          <th rowSpan={2} className="border border-black py-1">الاجمالي</th>
                        </tr>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th className="border border-black py-0.5">ق. السابقة</th>
                          <th className="border border-black py-0.5">ق. الحالية</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr className="font-black text-[11px]">
                          <td className="border border-black py-1 font-mono">{Number(row.prevReading || 0) > 0 ? Number(row.prevReading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.currReading || 0) > 0 ? Number(row.currReading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.units || 0) > 0 ? Number(row.units).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.serviceFee || 0) > 0 ? Number(row.serviceFee).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.consumptionCost || (Number(row.units || 0) * Number(row.unitPrice || 0)) || 0) > 0 ? Number(row.consumptionCost || (Number(row.units || 0) * Number(row.unitPrice || 0)) || 0).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.arrears || 0) > 0 ? Number(row.arrears).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(row.totalDue || 0) > 0 ? Number(row.totalDue).toLocaleString('en-US') : ''}</td>
                        </tr>
                      </tbody>
                    </table>

                    {/* Financial Settlement Breakdown Card in Main Invoice */}
                    {Number(row.paidAmount || 0) > 0 && (
                      <div className="border-2 border-black bg-slate-50 p-1.5 rounded mb-2 text-[10px] font-black">
                        <div className="grid grid-cols-3 gap-1 text-center">
                          <div className="border-l border-black pl-1">
                            <span className="text-slate-700 block text-[9px]">إجمالي المستحق</span>
                            <span className="font-mono text-black text-[11px] font-black">{Number(row.totalDue || 0).toLocaleString('en-US')} ر.ي</span>
                          </div>
                          <div className="border-l border-black pl-1">
                            <span className="text-emerald-800 block text-[9px]">المبلغ المسدد</span>
                            <span className="font-mono text-emerald-700 text-[11px] font-black">{Number(row.paidAmount).toLocaleString('en-US')} ر.ي</span>
                          </div>
                          <div>
                            <span className="text-slate-700 block text-[9px]">
                              {(Number(row.totalDue || 0) - Number(row.paidAmount || 0)) <= 0 ? 'الرصيد الدائن' : 'الرصيد المتبقي'}
                            </span>
                            <span className={`font-mono text-[11px] font-black ${(Number(row.totalDue || 0) - Number(row.paidAmount || 0)) > 0 ? 'text-red-700' : 'text-emerald-700'}`}>
                              {(Number(row.totalDue || 0) - Number(row.paidAmount || 0)) > 0
                                ? `+${(Number(row.totalDue || 0) - Number(row.paidAmount || 0)).toLocaleString('en-US')} ر.ي (متبقي عليك)`
                                : (Number(row.totalDue || 0) - Number(row.paidAmount || 0)) < 0
                                ? `-${Math.abs(Number(row.totalDue || 0) - Number(row.paidAmount || 0)).toLocaleString('en-US')} ر.ي (دائن لك)`
                                : '0 ر.ي (مسدد بالكامل ✅)'}
                            </span>
                          </div>
                        </div>
                      </div>
                    )}

                    {/* Red Policy Lines (5 Policy Points) */}
                    <div className="text-red-600 text-[10px] font-black space-y-0.5 my-2 leading-tight pr-1">
                      {policyLines.map((line: string, idx: number) => (
                        <div key={`${line}-${idx}`} className="flex items-start gap-1">
                          <span className="font-mono">o</span>
                          <span>{line.replace(/^o\s*/, '')}</span>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Footer Signatures */}
                  <div className="pt-2 text-[11px] font-black mt-2">
                    <div className="flex justify-between items-center mb-1 px-4">
                      <div className="text-center">
                        <div>المحصل</div>
                        <div className="text-slate-400 text-xs mt-1">..........................</div>
                      </div>
                      <div className="text-center">
                        <div>الحسابات</div>
                        <div className="text-slate-400 text-xs mt-1">..........................</div>
                      </div>
                    </div>
                  </div>
                </div>

              </div>

              {/* Bottom Outside Date Label (Bottom-Left) */}
              <div className="text-[10px] text-black text-left font-mono font-black pt-2 border-t border-black mt-2">
                التاريخ : {formatDateOnly(new Date())}
              </div>
            </div>

          </div>
        </div>

      </div>
    </div>
  );
};
