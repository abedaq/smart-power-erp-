import React from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { getSettings } from '../services/settings.service';
import { sendInvoiceWhatsApp } from '../services/invoice.service';
import { formatDateOnly, formatStationPhones, formatBankAccount } from '../utils/formatters';
import { printElementViaIframe } from '../utils/printUtils';
import { StationLogo } from './StationLogo';
import { X, Printer, Smartphone, RefreshCw, Zap } from 'lucide-react';
import toast from 'react-hot-toast';

interface InvoicePreviewModalProps {
  isOpen: boolean;
  onClose: () => void;
  invoice: any;
}

export const InvoicePreviewModal: React.FC<InvoicePreviewModalProps> = ({ isOpen, onClose, invoice }) => {
  const { data: settings } = useQuery({ queryKey: ['settings'], queryFn: getSettings });

  const sendWhatsAppMutation = useMutation({
    mutationFn: (invoiceId: number) => sendInvoiceWhatsApp(invoiceId),
    onSuccess: () => {
      toast.success('تم إضافة الفاتورة الرسمية لطابور الإرسال عبر الواتساب بنجاح!');
    },
    onError: (err: any) => {
      toast.error(`فشل إرسال الفاتورة عبر الواتساب: ${err.response?.data?.message || err.message}`);
    }
  });

  if (!isOpen || !invoice) return null;

  const customer = invoice.customer || {};
  
  // Exact defaults matching photo_5769554780358381104_y.jpg
  const stationName = settings?.station_name && settings.station_name !== 'محطة الطاقة الذكية' 
    ? settings.station_name 
    : 'محطة الضياء لتوليد الطاقة الكهربائية';
  
  const stationPhone = formatStationPhones(settings?.station_phone, settings?.station_phone_alt);
  const bankAccountNum = formatBankAccount(settings?.bank_accounts);
  
  const policyText = `o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.
o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.
o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان ألف ريال
o يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة.
o سعر الكيلوواط/ ساعة 1400 ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.`;

  const policyLines = policyText.split('\n').filter((l: string) => l.trim().length > 0);

  const handlePrint = () => {
    const custName = customer?.full_name || 'مشترك';
    const subNo = customer?.subscriber_number || invoice.id;
    const cycle = invoice?.billing_cycle ? `_${invoice.billing_cycle}` : '';
    printElementViaIframe(
      'printable-official-invoice',
      `فاتورة_${custName}_${subNo}${cycle}`,
      { orientation: 'portrait', pageSize: 'A4', margin: '5mm' }
    );
  };

  const cleanPeriod = (invoice.billing_cycle || 'يوليو- 2 - 2026').replace(/^دورة\s*/, '').trim();

  return (
    <div className="fixed inset-0 bg-slate-900/60 flex items-center justify-center z-50 p-2 sm:p-4 backdrop-blur-sm overflow-y-auto">
      <div className="bg-white border border-slate-300 rounded-3xl w-full max-w-5xl overflow-hidden shadow-2xl space-y-4 text-slate-900 text-right my-4 max-h-[95vh] flex flex-col">
        
        {/* Top Controls */}
        <div className="bg-slate-100 px-6 py-3.5 border-b border-slate-200 flex justify-between items-center no-print">
          <div className="flex items-center gap-2">
            <Zap className="text-blue-600" size={20} />
            <h2 className="text-base font-bold text-slate-900">معاينة نموذج الفاتورة المعتمد (المطابق للصورة الرسمية)</h2>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handlePrint}
              className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 shadow-md shadow-blue-500/20"
            >
              <Printer size={16} />
              <span>طباعة / حفظ PDF</span>
            </button>

            <button
              type="button"
              onClick={() => sendWhatsAppMutation.mutate(invoice.id)}
              disabled={sendWhatsAppMutation.isPending}
              className="bg-emerald-600 hover:bg-emerald-700 text-white px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 shadow-md shadow-emerald-500/20 disabled:opacity-50"
            >
              {sendWhatsAppMutation.isPending ? (
                <>
                  <RefreshCw size={15} className="animate-spin" />
                  <span>جاري الإرسال...</span>
                </>
              ) : (
                <>
                  <Smartphone size={15} />
                  <span>إرسال واتساب</span>
                </>
              )}
            </button>

            <button type="button" onClick={onClose} className="text-slate-400 hover:text-slate-800 transition-colors p-1.5 rounded-xl hover:bg-slate-200">
              <X size={20} />
            </button>
          </div>
        </div>

        {/* Printable Official Invoice Container (Exact match to photo_5769554780358381104_y.jpg) */}
        <div className="p-4 overflow-y-auto flex-1 text-right">
          <div 
            id="printable-official-invoice"
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
                          <td className="border border-black py-1 font-mono">{Number(invoice.previous_reading || 0) > 0 ? Number(invoice.previous_reading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(invoice.current_reading || 0) > 0 ? Number(invoice.current_reading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(invoice.consumption || 0) > 0 ? Number(invoice.consumption).toLocaleString('en-US') : ''}</td>
                          <td className={`border border-black py-1 font-mono ${Number(invoice.arrears || 0) < 0 ? 'text-emerald-800' : ''}`}>
                            {Number(invoice.arrears || 0) !== 0 
                              ? (Number(invoice.arrears) > 0 ? Number(invoice.arrears).toLocaleString('en-US') : `-${Math.abs(Number(invoice.arrears)).toLocaleString('en-US')}`) 
                              : ''}
                          </td>
                          <td className={`border border-black py-1 font-mono ${Number(invoice.total_due || 0) < 0 ? 'text-emerald-800' : ''}`}>
                            {Number(invoice.total_due || 0) !== 0 
                              ? (Number(invoice.total_due) > 0 ? Number(invoice.total_due).toLocaleString('en-US') : `-${Math.abs(Number(invoice.total_due)).toLocaleString('en-US')}`) 
                              : ''}
                          </td>
                        </tr>
                      </tbody>
                    </table>

                    {/* Payment & Remaining Breakdown in Coupon */}
                    {(Number(invoice.paid_amount || 0) > 0 || Number(invoice.remaining_amount || 0) !== 0) && (
                      <div className="border border-black bg-slate-50 p-1 mb-2 text-[9px] font-black space-y-0.5 text-right">
                        <div className="flex justify-between">
                          <span>المبلغ المسدد:</span>
                          <span className="font-mono text-emerald-800">{Number(invoice.paid_amount || 0).toLocaleString('en-US')} ر.ي</span>
                        </div>
                        <div className="flex justify-between border-t border-black/40 pt-0.5">
                          <span>{Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) < 0 ? 'رصيد دائن لك (فائض):' : 'المتبقي عليك:'}</span>
                          <span className={`font-mono ${Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) > 0 ? 'text-red-700' : 'text-emerald-700 font-extrabold'}`}>
                            {Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) > 0
                              ? `+${Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))).toLocaleString('en-US')}`
                              : Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) < 0
                              ? `-${Math.abs(Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0)))).toLocaleString('en-US')}`
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
                          <span className="font-black text-black">{customer.full_name || '-'}</span>
                        </div>
                        <div className="font-mono text-black">
                          <span>رقم الفاتورة : </span>
                          <span>{invoice.id}</span>
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
                          <td className="border border-black py-1 font-mono">{Number(invoice.previous_reading || 0) > 0 ? Number(invoice.previous_reading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(invoice.current_reading || 0) > 0 ? Number(invoice.current_reading).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(invoice.consumption || 0) > 0 ? Number(invoice.consumption).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(invoice.fixed_fee_snapshot || 0) > 0 ? Number(invoice.fixed_fee_snapshot).toLocaleString('en-US') : ''}</td>
                          <td className="border border-black py-1 font-mono">{Number(invoice.consumption_value || invoice.consumption_cost || (Number(invoice.consumption || 0) * Number(invoice.kwh_price_snapshot || 1400)) || 0) > 0 ? Number(invoice.consumption_value || invoice.consumption_cost || (Number(invoice.consumption || 0) * Number(invoice.kwh_price_snapshot || 1400)) || 0).toLocaleString('en-US') : ''}</td>
                          <td className={`border border-black py-1 font-mono ${Number(invoice.arrears || 0) < 0 ? 'text-emerald-800' : ''}`}>
                            {Number(invoice.arrears || 0) !== 0 
                              ? (Number(invoice.arrears) > 0 ? Number(invoice.arrears).toLocaleString('en-US') : `-${Math.abs(Number(invoice.arrears)).toLocaleString('en-US')}`) 
                              : ''}
                          </td>
                          <td className={`border border-black py-1 font-mono ${Number(invoice.total_due || 0) < 0 ? 'text-emerald-800' : ''}`}>
                            {Number(invoice.total_due || 0) !== 0 
                              ? (Number(invoice.total_due) > 0 ? Number(invoice.total_due).toLocaleString('en-US') : `-${Math.abs(Number(invoice.total_due)).toLocaleString('en-US')}`) 
                              : ''}
                          </td>
                        </tr>
                      </tbody>
                    </table>

                    {/* Financial Settlement Breakdown Card in Main Invoice */}
                    {(Number(invoice.paid_amount || 0) > 0 || Number(invoice.remaining_amount || 0) !== 0) && (
                      <div className="border-2 border-black bg-slate-50 p-1.5 rounded mb-2 text-[10px] font-black">
                        <div className="grid grid-cols-3 gap-1 text-center">
                          <div className="border-l border-black pl-1">
                            <span className="text-slate-700 block text-[9px]">إجمالي المستحق</span>
                            <span className="font-mono text-black text-[11px] font-black">{Number(invoice.total_due || 0).toLocaleString('en-US')} ر.ي</span>
                          </div>
                          <div className="border-l border-black pl-1">
                            <span className="text-emerald-800 block text-[9px]">المبلغ المسدد</span>
                            <span className="font-mono text-emerald-700 text-[11px] font-black">{Number(invoice.paid_amount || 0).toLocaleString('en-US')} ر.ي</span>
                          </div>
                          <div>
                            <span className="text-slate-700 block text-[9px]">
                              {Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) < 0 ? 'الرصيد الدائن (فائض)' : 'الرصيد المتبقي'}
                            </span>
                            <span className={`font-mono text-[11px] font-black ${Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) > 0 ? 'text-red-700' : 'text-emerald-700 font-extrabold'}`}>
                              {Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) > 0
                                ? `+${Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))).toLocaleString('en-US')} ر.ي (متبقي عليك)`
                                : Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0))) < 0
                                ? `-${Math.abs(Number(invoice.remaining_amount !== undefined ? invoice.remaining_amount : (Number(invoice.total_due || 0) - Number(invoice.paid_amount || 0)))).toLocaleString('en-US')} ر.ي (دائن لك ✅)`
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
                التاريخ : {formatDateOnly(invoice.created_at || Date.now())}
              </div>
            </div>

          </div>
        </div>

      </div>
    </div>
  );
};
