import React, { useState } from 'react';
import type { Payment } from '../types';
import { useQuery } from '@tanstack/react-query';
import { getSettings } from '../services/settings.service';
import { sendReceiptWhatsAppApi } from '../services/payment.service';
import { formatYemeniPhone } from '../types/excelGrid.types';
import { printElementViaIframe } from '../utils/printUtils';
import { formatStationPhones, formatBankAccount } from '../utils/formatters';
import { StationLogo } from './StationLogo';
import { Printer, Send, Sparkles, X, CheckCircle, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';

interface PaymentReceiptModalProps {
  isOpen: boolean;
  onClose: () => void;
  payment: Payment | null;
}

export const PaymentReceiptModal: React.FC<PaymentReceiptModalProps> = ({
  isOpen,
  onClose,
  payment,
}) => {
  const [isSendingWhatsApp, setIsSendingWhatsApp] = useState<boolean>(false);

  const { data: settings } = useQuery({
    queryKey: ['settings'],
    queryFn: getSettings,
  });

  if (!isOpen || !payment) return null;
  const isReversed = payment.approval_status === 'REVERSED' || Boolean((payment as any).reversed) || Boolean((payment as any).is_reversed);

  const stationName =
    settings?.station_name && settings.station_name !== 'محطة الطاقة الذكية'
      ? settings.station_name
      : 'محطة الضياء لتوليد الطاقة الكهربائية';
  const stationPhone = formatStationPhones(settings?.station_phone, settings?.station_phone_alt);
  const bankAccountNum = formatBankAccount(settings?.bank_accounts);

  const customer = payment.customer || ({} as any);
  const planPrice = Number(
    (customer as any)?.unitPrice ??
      (customer as any)?.unit_price ??
      (customer as any)?.kwh_price ??
      customer?.subscription_plan?.kwh_price ??
      1500
  );
  const planFee = Number(
    (customer as any)?.serviceFee ??
      (customer as any)?.service_fee ??
      (customer as any)?.fixed_fee ??
      customer?.subscription_plan?.fixed_fee ??
      1000
  );

  const defaultPolicyText = `o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.
o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.
o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان الف ريال
o يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة.
o سعر الكيلوواط/ ساعة ${planPrice.toLocaleString('en-US')} ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.`;

  const policyLines = (settings?.invoice_policy_text || defaultPolicyText)
    .replace(/1500/g, planPrice.toLocaleString('en-US'))
    .split('\n')
    .filter((l: string) => l.trim().length > 0);

  const receiptNo = payment.receipt_number || `REC-#${payment.id}`;
  const customerName = customer.full_name || (payment as any).customer_name || 'مشترك';
  const paidAmountNum = Number(payment.amount_paid || 0);
  const rawCycle = (payment as any)?.invoice?.billing_cycle || (payment as any)?.billing_cycle || '';
  const cleanCycle = rawCycle ? rawCycle.replace(/^دورة\s*/, '').trim() : '';

  // Computed readings and units
  const prevReading = Number(
    customer.previous_reading || customer.initial_reading || 0
  );
  const currReading = Number(customer.last_reading || prevReading);
  const units = currReading >= prevReading ? currReading - prevReading : 0;
  const consumptionCost = units * planPrice;
  const arrears = Number(customer.arrears || 0);
  const remaining =
    customer.remaining_amount !== undefined && customer.remaining_amount !== null
      ? Number(customer.remaining_amount)
      : consumptionCost + planFee + arrears - paidAmountNum;

  const paymentDate = payment.payment_date
    ? new Date(payment.payment_date).toLocaleDateString('en-GB')
    : new Date().toLocaleDateString('en-GB');

  const handlePrint = () => {
    const subNo = customer.subscriber_number || customer.id || payment.id;
    printElementViaIframe(
      'printable-official-invoice-grid',
      `فاتورة_${customerName}_${subNo}_${receiptNo}`,
      { orientation: 'landscape', pageSize: 'A4', margin: '4mm' }
    );
  };

  const handleSendWhatsApp = async () => {
    const phone = formatYemeniPhone(customer.phone_number);
    if (!phone || phone.length < 9) {
      toast.error('رقم هاتف المشترك غير صحيح أو غير متوفر');
      return;
    }

    setIsSendingWhatsApp(true);
    const loadToast = toast.loading('جاري إرسال سند القبض عبر واتساب...');
    try {
      const res = await sendReceiptWhatsAppApi(payment.id);
      toast.success(
        res?.message || `تم إرسال سند القبض إلى واتساب المشترك (${customerName}) بنجاح!`,
        { id: loadToast }
      );
    } catch (err: any) {
      const errorMsg =
        err.response?.data?.message ||
        err.message ||
        'خدمة الواتساب غير متصلة بالهاتف حالياً. يرجى ربط الهاتف أولاً من صفحة الإعدادات.';
      toast.error(errorMsg, { id: loadToast, duration: 5000 });
    } finally {
      setIsSendingWhatsApp(false);
    }
  };

  const handlePrintAndWhatsApp = async () => {
    handlePrint();
    await handleSendWhatsApp();
  };

  return (
    <div
      className="fixed inset-0 bg-slate-900/60 flex items-center justify-center z-50 p-2 sm:p-4 backdrop-blur-sm overflow-y-auto"
      dir="rtl"
    >
      <div className="bg-white border border-slate-300 rounded-3xl w-full max-w-5xl shadow-2xl relative overflow-hidden text-right my-3 max-h-[95vh] flex flex-col">
        {/* Top Action Controls Bar */}
        <div className="bg-slate-100 px-6 py-3.5 border-b border-slate-200 flex flex-wrap justify-between items-center gap-2 no-print">
          <div className="flex items-center gap-2">
            <div className="p-1.5 bg-emerald-100 text-emerald-700 rounded-lg">
              <CheckCircle size={18} />
            </div>
            <div>
              <h2 className="text-sm font-bold text-slate-900">
                الفاتورة الرسمية المعتمدة وسند القبض (الكعب المزدوج)
              </h2>
              <span className="text-[11px] text-slate-500 font-mono">
                سند: {receiptNo}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            <button
              type="button"
              onClick={handlePrintAndWhatsApp}
              className="bg-indigo-600 hover:bg-indigo-700 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-indigo-500/20 cursor-pointer"
              title="طباعة الفاتورة وفتح الواتساب معاً"
            >
              <Sparkles size={15} />
              <span>طباعة وإرسال واتساب</span>
            </button>

            <button
              type="button"
              onClick={handlePrint}
              className="bg-blue-600 hover:bg-blue-700 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-blue-500/20 cursor-pointer"
            >
              <Printer size={15} />
              <span>طباعة الفاتورة</span>
            </button>

            <button
              type="button"
              onClick={handleSendWhatsApp}
              disabled={isSendingWhatsApp}
              className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-60 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-emerald-500/20 cursor-pointer"
            >
              {isSendingWhatsApp ? (
                <Loader2 size={15} className="animate-spin" />
              ) : (
                <Send size={15} className="transform -rotate-45" />
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

        {/* Printable Official Invoice Container (Strict match to official design) */}
        <div className="p-4 overflow-y-auto flex-1 text-right">
          <div
            id="printable-official-invoice-grid"
            className="bg-white text-black font-sans mx-auto w-full max-w-[960px] text-right leading-tight text-xs p-1 relative overflow-hidden"
            dir="rtl"
          >
            {isReversed && (
              <div className="bg-rose-100 border-2 border-rose-600 text-rose-950 p-2 text-center font-black text-sm mb-2 rounded-lg print:border-rose-800">
                ⚠️ تنبيه رقابي: هذا السند ملغي مالياً ورسمياً (REVERSED / VOID) ولن يعتد به في التسويات ⚠️
              </div>
            )}
            {isReversed && (
              <div className="absolute inset-0 flex items-center justify-center pointer-events-none opacity-25 z-50 select-none">
                <span className="text-red-600 text-7xl font-black transform -rotate-45 border-8 border-red-600 px-8 py-3 rounded-3xl tracking-widest uppercase">
                  سند ملغي - VOID
                </span>
              </div>
            )}
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
                        <div className="text-xs font-black text-blue-700 font-mono dir-ltr my-0.5">
                          {stationPhone}
                        </div>
                      </div>
                      <div className="pt-0.5">
                        <StationLogo size={44} />
                      </div>
                    </div>

                    {/* Customer Info */}
                    <div className="space-y-1 text-[10px] font-black mb-2">
                      <div>
                        <span>اسم المشترك : </span>
                        <span className="font-black text-black">
                          {customerName}
                        </span>
                      </div>
                      <div>
                        <span>العنوان : </span>
                        <span>{customer.address || '-'}</span>
                      </div>
                      <div>
                        <span>رقم المشترك : </span>
                        <span className="font-mono font-black">
                          {customer.subscriber_number || '-'}
                        </span>
                      </div>
                      <div>
                        <span>رقم العداد : </span>
                        <span className="font-mono font-black">
                          {customer.meter_number || '-'}
                        </span>
                      </div>
                    </div>

                    {/* Red & Blue Title */}
                    <div className="text-center font-black text-[10px] my-2">
                      {cleanCycle ? (
                        <>
                          <span className="text-red-600">فاتورة استهلاك كهرباء دورة </span>
                          <span className="text-blue-900">{cleanCycle}</span>
                          <span className="text-red-600"> - سند سداد رسمي</span>
                        </>
                      ) : (
                        <span className="text-red-600">فاتورة استهلاك كهرباء - سند سداد رسمي</span>
                      )}
                    </div>

                    {/* Coupon Table (5 Columns) */}
                    <table className="w-full border-collapse text-center text-[9px] border-2 border-black mb-2">
                      <thead>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th colSpan={2} className="border border-black py-1">
                            قــــــراءة العداد
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            الفارق
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            متأخرات
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            المتبقي
                          </th>
                        </tr>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th className="border border-black py-0.5">ق.السابقة</th>
                          <th className="border border-black py-0.5">ق.الحالية</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr className="font-black text-[10px]">
                          <td className="border border-black py-1 font-mono">
                            {prevReading > 0
                              ? prevReading.toLocaleString('en-US')
                              : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {currReading > 0
                              ? currReading.toLocaleString('en-US')
                              : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {units > 0 ? units.toLocaleString('en-US') : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {arrears > 0 ? arrears.toLocaleString('en-US') : ''}
                          </td>
                          <td className="border border-black py-1 font-mono text-rose-700 font-extrabold">
                            {remaining !== 0
                              ? remaining > 0
                                ? remaining.toLocaleString('en-US')
                                : `-${Math.abs(remaining).toLocaleString('en-US')}`
                              : ''}
                          </td>
                        </tr>
                      </tbody>
                    </table>

                    {/* Financial Snapshot */}
                    <div className="bg-slate-100 border border-black p-1.5 text-[9px] font-black space-y-0.5">
                      <div className="flex justify-between">
                        <span>المقبوض بهذا السند:</span>
                        <span className="font-mono text-emerald-800">
                          {paidAmountNum.toLocaleString('en-US')} ر.ي
                        </span>
                      </div>
                      <div className="flex justify-between">
                        <span>
                          {remaining < 0
                            ? 'الرصيد الدائن:'
                            : 'المتبقي بعد السداد:'}
                        </span>
                        <span
                          className={`font-mono ${
                            remaining < 0
                              ? 'text-emerald-800 font-black'
                              : 'text-rose-800'
                          }`}
                        >
                          {remaining < 0
                            ? `-${Math.abs(remaining).toLocaleString('en-US')} ر.ي`
                            : `${remaining.toLocaleString('en-US')} ر.ي`}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Footer Signatures */}
                  <div className="pt-2 text-[10px] font-black mt-2">
                    <div className="flex justify-between items-center px-2">
                      <div className="text-center">
                        <div>المحصل</div>
                        <div className="text-slate-400 text-xs mt-1">
                          ....................
                        </div>
                      </div>
                      <div className="text-center">
                        <div>الحسابات</div>
                        <div className="text-slate-400 text-xs mt-1">
                          ....................
                        </div>
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
                        <h1 className="text-base font-black text-black">
                          {stationName}
                        </h1>
                        <div className="text-sm font-black text-blue-700 font-mono tracking-wider dir-ltr my-0.5">
                          {stationPhone}
                        </div>
                        <div className="text-[11px] font-black text-black">
                          يمكنك الإيداع على الحساب {bankAccountNum}
                        </div>
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
                          <span className="font-black text-black">
                            {customerName}
                          </span>
                        </div>
                        <div className="font-mono text-black">
                          <span>رقم السند : </span>
                          <span>{receiptNo}</span>
                        </div>
                      </div>

                      <div>
                        <span>العنوان : </span>
                        <span>{customer.address || '-'}</span>
                      </div>

                      <div>
                        <span>رقم المشترك : </span>
                        <span className="font-mono font-black">
                          {customer.subscriber_number || '-'}
                        </span>
                      </div>

                      <div className="flex justify-between items-center">
                        <div>
                          <span>رقم العداد : </span>
                          <span className="font-mono font-black">
                            {customer.meter_number || '-'}
                          </span>
                        </div>
                        <div className="font-mono pl-4">
                          <span>رقم خط السير : </span>
                          <span>{customer.route_number || '-'}</span>
                        </div>
                      </div>
                    </div>

                    {/* Red & Blue Title */}
                    <div className="text-center font-black text-xs my-2">
                      {cleanCycle ? (
                        <>
                          <span className="text-red-600">فاتورة استهلاك كهرباء دورة </span>
                          <span className="text-blue-900">{cleanCycle}</span>
                          <span className="text-red-600"> - سند سداد رسمي</span>
                        </>
                      ) : (
                        <span className="text-red-600">فاتورة استهلاك كهرباء - سند سداد رسمي</span>
                      )}
                    </div>

                    {/* Table (7 Columns) */}
                    <table className="w-full border-collapse text-center text-[10px] border-2 border-black mb-2">
                      <thead>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th colSpan={2} className="border border-black py-1">
                            قــــــراءة العداد
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            الفارق
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            اشتراك
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            القيمـة
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            المدفوع
                          </th>
                          <th rowSpan={2} className="border border-black py-1">
                            المتبقي
                          </th>
                        </tr>
                        <tr className="bg-white font-black border-b-2 border-black">
                          <th className="border border-black py-0.5">ق. السابقة</th>
                          <th className="border border-black py-0.5">ق. الحالية</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr className="font-black text-[11px]">
                          <td className="border border-black py-1 font-mono">
                            {prevReading > 0
                              ? prevReading.toLocaleString('en-US')
                              : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {currReading > 0
                              ? currReading.toLocaleString('en-US')
                              : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {units > 0 ? units.toLocaleString('en-US') : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {planFee > 0 ? planFee.toLocaleString('en-US') : ''}
                          </td>
                          <td className="border border-black py-1 font-mono">
                            {consumptionCost > 0
                              ? consumptionCost.toLocaleString('en-US')
                              : ''}
                          </td>
                          <td className="border border-black py-1 font-mono text-emerald-800 font-extrabold">
                            {paidAmountNum > 0
                              ? paidAmountNum.toLocaleString('en-US')
                              : ''}
                          </td>
                          <td
                            className={`border border-black py-1 font-mono font-extrabold ${
                              remaining < 0 ? 'text-emerald-800' : 'text-rose-800'
                            }`}
                          >
                            {remaining !== 0
                              ? remaining > 0
                                ? remaining.toLocaleString('en-US')
                                : `-${Math.abs(remaining).toLocaleString('en-US')}`
                              : ''}
                          </td>
                        </tr>
                      </tbody>
                    </table>

                    {/* Red Policy Lines */}
                    <div className="text-red-600 text-[10px] font-black space-y-0.5 my-2 leading-tight pr-1">
                      {policyLines.map((line: string, i: number) => (
                        <div key={i}>{line}</div>
                      ))}
                    </div>
                  </div>

                  {/* Footer Signatures */}
                  <div className="pt-2 text-[10px] font-black border-t border-black">
                    <div className="flex justify-between items-center px-4">
                      <div className="text-center">
                        <div>المحصل</div>
                        <div className="text-slate-400 text-xs mt-1">
                          ....................
                        </div>
                      </div>
                      <div className="text-center font-mono">
                        <div>التاريخ : {paymentDate}</div>
                      </div>
                      <div className="text-center">
                        <div>الحسابات</div>
                        <div className="text-slate-400 text-xs mt-1">
                          ....................
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PaymentReceiptModal;
