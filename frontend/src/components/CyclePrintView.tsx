import React from 'react';
import type { Invoice } from '../types';
import { printElementViaIframe } from '../utils/printUtils';
import { formatDateOnly, formatStationPhones, formatBankAccount } from '../utils/formatters';
import { StationLogo } from './StationLogo';
import { Printer, X, FileSpreadsheet, Receipt } from 'lucide-react';

interface CyclePrintViewProps {
  isOpen: boolean;
  onClose: () => void;
  cycleName: string;
  invoices: Invoice[];
  mode: 'summary' | 'individual';
  stationSettings?: any;
}

export const CyclePrintView: React.FC<CyclePrintViewProps> = ({
  isOpen,
  onClose,
  cycleName,
  invoices,
  mode,
  stationSettings,
}) => {
  if (!isOpen) return null;

  const stationName = stationSettings?.station_name && stationSettings.station_name !== 'محطة الطاقة الذكية'
    ? stationSettings.station_name
    : 'محطة الضياء لتوليد الطاقة الكهربائية';

  const stationPhone = formatStationPhones(stationSettings?.station_phone, stationSettings?.station_phone_alt);
  const bankAccountNum = formatBankAccount(stationSettings?.bank_accounts);
  
  const policyText = `o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.
o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.
o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان ألف ريال
o يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة.
o سعر الكيلوواط/ ساعة 1400 ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.`;

  const policyLines = policyText.split('\n').filter((l: string) => l.trim().length > 0);

  const totalBilled = invoices.reduce((sum, inv) => sum + Number(inv.total_due || 0), 0);
  const totalPaid = invoices.reduce((sum, inv) => sum + Number(inv.paid_amount || 0), 0);
  const totalRemaining = invoices.reduce((sum, inv) => sum + Number(inv.remaining_amount || 0), 0);

  const handlePrint = () => {
    const isSummary = mode === 'summary';
    printElementViaIframe(
      'printable-cycle-content',
      isSummary ? `كشف_تجميعي_دورة_${cycleName}` : `فواتير_دورة_${cycleName}`,
      {
        orientation: isSummary ? 'landscape' : 'portrait',
        pageSize: 'A4',
        margin: isSummary ? '4mm' : '5mm'
      }
    );
  };

  return (
    <div className="fixed inset-0 bg-slate-900/60 flex items-center justify-center z-50 p-2 sm:p-4 backdrop-blur-sm overflow-y-auto">
      <div className="bg-white border border-slate-300 rounded-3xl w-full max-w-5xl overflow-hidden shadow-2xl space-y-4 text-slate-900 text-right my-4 max-h-[95vh] flex flex-col">
        
        {/* Top Controls Bar (Hidden during print) */}
        <div className="bg-slate-100 px-6 py-3.5 border-b border-slate-200 flex justify-between items-center no-print">
          <div className="flex items-center gap-2">
            {mode === 'summary' ? (
              <FileSpreadsheet className="text-blue-600" size={22} />
            ) : (
              <Receipt className="text-blue-600" size={22} />
            )}
            <div>
              <h2 className="text-base font-bold text-slate-900">
                {mode === 'summary'
                  ? `الكشف التجميعي الشامل لدورة: ${cycleName}`
                  : `فواتير المشتركين المفردة لدورة: ${cycleName}`}
              </h2>
              <p className="text-xs text-slate-500 font-medium">
                إجمالي المشتركين: {invoices.length} • الإجمالي: {totalBilled.toLocaleString('en-US')} ر.ي
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={handlePrint}
              className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-xl text-xs font-bold transition-all shadow-md shadow-blue-600/20 flex items-center gap-1.5"
            >
              <Printer size={16} />
              <span>طباعة / حفظ PDF</span>
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

        {/* Printable Content Area */}
        <div className="p-4 overflow-y-auto flex-1 text-right">
          <div id="printable-cycle-content" className="bg-white text-slate-900 p-2 font-sans" dir="rtl">
            
            {/* Printable Header for Summary Mode */}
            {mode === 'summary' && (
              <div className="border-b-2 border-slate-800 pb-3 mb-4 text-center">
                <div className="flex items-center justify-center gap-3 mb-1">
                  <StationLogo size={44} />
                  <h1 className="text-xl font-black text-slate-900">{stationName}</h1>
                </div>
                <p className="text-xs text-slate-600 mt-1 font-bold">
                  كشف الفواتير والتحصيل لدورة: <span className="text-blue-700 font-extrabold">{cycleName}</span> (نصف شهرية)
                </p>
                <div className="flex justify-between items-center text-[11px] text-slate-500 mt-2 border-t border-slate-200 pt-1 font-mono dir-ltr">
                  <span>عدد المشتركين: {invoices.length}</span>
                  <span>هاتف المحطة: {stationPhone}</span>
                  <span>تاريخ التقرير: {new Date().toLocaleDateString('en-US')}</span>
                </div>
              </div>
            )}

            {mode === 'summary' ? (
              /* Mode 1: Summary Table */
              <div className="overflow-x-auto">
                <table className="w-full text-xs text-right border-collapse border border-slate-900">
                  <thead>
                    <tr className="bg-slate-100 text-slate-900 font-bold border-b border-slate-900">
                      <th className="p-2 border border-slate-900 text-center">#</th>
                      <th className="p-2 border border-slate-900">اسم المشترك</th>
                      <th className="p-2 border border-slate-900 text-center">الاشتراك</th>
                      <th className="p-2 border border-slate-900 text-center">خط السير</th>
                      <th className="p-2 border border-slate-900 text-center">ق.السابقة</th>
                      <th className="p-2 border border-slate-900 text-center">ق.الحالية</th>
                      <th className="p-2 border border-slate-900 text-center">الاستهلاك</th>
                      <th className="p-2 border border-slate-900 text-center">المستحق (ر.ي)</th>
                      <th className="p-2 border border-slate-900 text-center">المسدد (ر.ي)</th>
                      <th className="p-2 border border-slate-900 text-center">المتبقي (ر.ي)</th>
                      <th className="p-2 border border-slate-900 text-center">الحالة</th>
                    </tr>
                  </thead>
                  <tbody>
                    {invoices.map((inv, idx) => (
                      <tr key={inv.id} className={idx % 2 === 0 ? 'bg-white' : 'bg-slate-50'}>
                        <td className="p-1.5 border border-slate-900 text-center font-mono font-bold">{idx + 1}</td>
                        <td className="p-1.5 border border-slate-900 font-bold text-slate-900">{inv.customer?.full_name || 'مشترك'}</td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono">{inv.customer?.subscriber_number || '-'}</td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono">{inv.customer?.route_number || '-'}</td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono">{inv.previous_reading ?? '-'}</td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono">{inv.current_reading ?? '-'}</td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono font-bold">
                          {Number(inv.consumption || 0) > 0 ? Number(inv.consumption).toLocaleString('en-US') : ''}
                        </td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono font-bold text-slate-900">
                          {Number(inv.total_due || 0) > 0 ? Number(inv.total_due).toLocaleString('en-US') : ''}
                        </td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono text-emerald-700 font-bold">
                          {Number(inv.paid_amount || 0) > 0 ? Number(inv.paid_amount).toLocaleString('en-US') : ''}
                        </td>
                        <td className="p-1.5 border border-slate-900 text-center font-mono font-bold">
                          {Number(inv.remaining_amount || 0) !== 0 
                            ? (Number(inv.remaining_amount) > 0 
                                ? Number(inv.remaining_amount).toLocaleString('en-US') 
                                : `-${Math.abs(Number(inv.remaining_amount)).toLocaleString('en-US')}`)
                            : ''}
                        </td>
                        <td className="p-1.5 border border-slate-900 text-center font-bold text-[10px]">
                          {inv.status === 'Paid' ? 'مكتمل' : inv.status === 'Partially_Paid' ? 'جزئي' : 'معلق'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot>
                    <tr className="bg-slate-100 font-black text-slate-900 border-t-2 border-slate-900">
                      <td colSpan={7} className="p-2 border border-slate-900 text-left">الإجمالي الكلي للدورة ({cycleName}):</td>
                      <td className="p-2 border border-slate-900 text-center font-mono text-blue-700 font-black">
                        {totalBilled.toLocaleString('en-US')} ر.ي
                      </td>
                      <td className="p-2 border border-slate-900 text-center font-mono text-emerald-700 font-black">
                        {totalPaid.toLocaleString('en-US')} ر.ي
                      </td>
                      <td className="p-2 border border-slate-900 text-center font-mono text-rose-700 font-black">
                        {totalRemaining.toLocaleString('en-US')} ر.ي
                      </td>
                      <td className="p-2 border border-slate-900"></td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            ) : (
              /* Mode 2: Individual 2-Part Split Bills matching photo_5769554780358381104_y.jpg */
              <div className="space-y-6">
                {invoices.map((inv) => {
                  const customer: any = inv.customer || {};
                  const cleanPeriod = (inv.billing_cycle || 'يوليو- 2 - 2026').replace(/^دورة\s*/, '').trim();

                  return (
                    <div 
                      key={inv.id} 
                      className="bg-white text-black font-sans mx-auto w-full max-w-[960px] text-right leading-tight text-xs page-break p-1"
                      dir="rtl"
                    >
                      {/* Outer Frame */}
                      <div className="border-2 border-black p-2">
                        
                        <div className="grid grid-cols-12 gap-0 items-stretch">
                          
                          {/* Part 1 (RIGHT SIDE): Collector Coupon (~40% Width) */}
                          <div className="col-span-5 pl-3 pr-1 flex flex-col justify-between">
                            <div>
                              {/* Header */}
                              <div className="flex items-start justify-between border-b-2 border-black pb-1.5 mb-1.5">
                                <div className="text-center flex-1">
                                  <h2 className="text-[11px] font-black text-black">{stationName}</h2>
                                  <div className="text-[9px] font-black text-blue-700 font-mono dir-ltr my-0.5">{stationPhone}</div>
                                </div>
                                <div className="pt-0.5">
                                  <StationLogo size={38} />
                                </div>
                              </div>

                              {/* Info */}
                              <div className="space-y-0.5 text-[9px] font-black mb-1">
                                <div>
                                  <span>اسم المشترك : </span>
                                  <span className="font-black text-black">{customer.full_name || '-'}</span>
                                </div>
                                <div>
                                  <span>العنوان : </span>
                                  <span>{customer.address || '-'}</span>
                                </div>
                                <div>
                                  <span>رقم المشترك : </span>
                                  <span className="font-mono font-black">{customer.subscriber_number || '-'}</span>
                                </div>
                                <div>
                                  <span>رقم العداد : </span>
                                  <span className="font-mono font-black">{customer.meter_number || '-'}</span>
                                </div>
                              </div>

                              {/* Red & Blue Cycle Title */}
                              <div className="text-center font-black text-[9px] my-1">
                                <span className="text-red-600">فاتورة استهلاك كهرباء دورة </span>
                                <span className="text-blue-900">{cleanPeriod}</span>
                              </div>

                              {/* Mini Table (5 Columns) */}
                              <table className="w-full border-collapse text-center text-[8px] border-2 border-black mb-1">
                                <thead>
                                  <tr className="bg-white font-black border-b-2 border-black">
                                    <th colSpan={2} className="border border-black py-0.5">قــــــراءة العداد</th>
                                    <th rowSpan={2} className="border border-black py-0.5">الفارق</th>
                                    <th rowSpan={2} className="border border-black py-0.5">متأخرات وغرامات</th>
                                    <th rowSpan={2} className="border border-black py-0.5">الاجمالي</th>
                                  </tr>
                                  <tr className="bg-white font-black border-b-2 border-black">
                                    <th className="border border-black py-0.5">ق.السابقة</th>
                                    <th className="border border-black py-0.5">ق.الحالية</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  <tr className="font-black text-[9px]">
                                    <td className="border border-black py-1 font-mono">{Number(inv.previous_reading || 0) > 0 ? Number(inv.previous_reading).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.current_reading || 0) > 0 ? Number(inv.current_reading).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.consumption || 0) > 0 ? Number(inv.consumption).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.arrears || 0) > 0 ? Number(inv.arrears).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.total_due || 0) > 0 ? Number(inv.total_due).toLocaleString('en-US') : ''}</td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>

                            {/* Footer Signatures */}
                            <div className="pt-1 text-[9px] font-black mt-1">
                              <div className="flex justify-between items-center px-1">
                                <div className="text-center">
                                  <div>المحصل</div>
                                  <div className="text-slate-400 text-[9px] mt-1">....................</div>
                                </div>
                                <div className="text-center">
                                  <div>الحسابات</div>
                                  <div className="text-slate-400 text-[9px] mt-1">....................</div>
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
                                  <h1 className="text-sm font-black text-black">{stationName}</h1>
                                  <div className="text-xs font-black text-blue-700 font-mono dir-ltr my-0.5">{stationPhone}</div>
                                  <div className="text-[10px] font-black text-black">يمكنك الإيداع على الحساب {bankAccountNum}</div>
                                </div>
                                <div className="pt-0.5">
                                  <StationLogo size={48} />
                                </div>
                              </div>

                              {/* Customer Info */}
                              <div className="text-[10px] font-black space-y-1 mb-1.5">
                                <div className="flex justify-between items-center">
                                  <div>
                                    <span>اسم المشترك : </span>
                                    <span className="font-black text-black">{customer.full_name || '-'}</span>
                                  </div>
                                  <div className="font-mono text-black">
                                    <span>رقم الفاتورة : </span>
                                    <span>{inv.id}</span>
                                  </div>
                                </div>

                                <div>
                                  <span>العنوان : </span>
                                  <span>{customer.address || '-'}</span>
                                </div>

                                <div>
                                  <span>رقم المشترك : </span>
                                  <span className="font-mono font-black">{customer.subscriber_number || '-'}</span>
                                </div>

                                <div className="flex justify-between items-center">
                                  <div>
                                    <span>رقم العداد : </span>
                                    <span className="font-mono font-black">{customer.meter_number || '-'}</span>
                                  </div>
                                  <div className="font-mono pl-4">
                                    <span>رقم خط السير : </span>
                                    <span>{customer.route_number || '-'}</span>
                                  </div>
                                </div>
                              </div>

                              {/* Red & Blue Cycle Title */}
                              <div className="text-center font-black text-xs my-1.5">
                                <span className="text-red-600">فاتورة استهلاك كهرباء دورة </span>
                                <span className="text-blue-900">{cleanPeriod}</span>
                              </div>

                              {/* Table (7 Columns) */}
                              <table className="w-full border-collapse text-center text-[9px] border-2 border-black mb-2">
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
                                  <tr className="font-black text-[10px]">
                                    <td className="border border-black py-1 font-mono">{Number(inv.previous_reading || 0) > 0 ? Number(inv.previous_reading).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.current_reading || 0) > 0 ? Number(inv.current_reading).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.consumption || 0) > 0 ? Number(inv.consumption).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.fixed_fee_snapshot || 0) > 0 ? Number(inv.fixed_fee_snapshot).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number((inv as any).consumption_value || (inv as any).consumption_cost || (Number(inv.consumption || 0) * Number(inv.kwh_price_snapshot || 1400)) || 0) > 0 ? Number((inv as any).consumption_value || (inv as any).consumption_cost || (Number(inv.consumption || 0) * Number(inv.kwh_price_snapshot || 1400)) || 0).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.arrears || 0) > 0 ? Number(inv.arrears).toLocaleString('en-US') : ''}</td>
                                    <td className="border border-black py-1 font-mono">{Number(inv.total_due || 0) > 0 ? Number(inv.total_due).toLocaleString('en-US') : ''}</td>
                                  </tr>
                                </tbody>
                              </table>

                              {/* Red Policy (5 Policy Points) */}
                              <div className="text-red-600 text-[9px] font-black space-y-0.5 my-1.5 leading-tight pr-1">
                                {policyLines.map((line: string, idx: number) => (
                                  <div key={`${line}-${idx}`} className="flex items-start gap-1">
                                    <span className="font-mono">o</span>
                                    <span>{line.replace(/^o\s*/, '')}</span>
                                  </div>
                                ))}
                              </div>
                            </div>

                            {/* Footer Signatures */}
                            <div className="pt-1.5 text-[10px] font-black mt-1">
                              <div className="flex justify-between items-center mb-1 px-3">
                                <div className="text-center">
                                  <div>المحصل</div>
                                  <div className="text-slate-400 text-[10px] mt-1">..........................</div>
                                </div>
                                <div className="text-center">
                                  <div>الحسابات</div>
                                  <div className="text-slate-400 text-[10px] mt-1">..........................</div>
                                </div>
                              </div>
                            </div>
                          </div>

                        </div>

                        {/* Bottom Outside Date Label (Bottom-Left) */}
                        <div className="text-[9px] text-black text-left font-mono font-black pt-1.5 border-t border-black mt-1.5">
                          التاريخ : {formatDateOnly(String(inv.created_at || ''))}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

          </div>
        </div>
      </div>
    </div>
  );
};
