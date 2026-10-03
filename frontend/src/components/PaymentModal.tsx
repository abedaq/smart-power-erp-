import React, { useRef, useState, useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { payInvoice, sendReceiptWhatsAppApi } from '../lib/api';
import { getSettings } from '../services/settings.service';
import { formatInputAsCurrency, parseFormattedNumber, generateUUID } from '../utils/formatters';
import { formatYemeniPhone, type ComputedGridRow } from '../types/excelGrid.types';
import { printElementViaIframe } from '../utils/printUtils';
import { StationLogo } from './StationLogo';
import { useAuth } from '../context/AuthContext';
import { QUERY_KEYS, invalidateFinancialTree } from '../constants/queryKeys';
import { Banknote, CheckCircle, X, AlertTriangle, Printer, Send, Smartphone, Gauge, Hash, User, Sparkles, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import type { Customer } from '../types';

interface PaymentModalProps {
  isOpen: boolean;
  onClose: () => void;
  customer: Customer | null;
  onPaymentSuccess?: (customer: Customer, amountPaid: number) => void;
}

export const PaymentModal: React.FC<PaymentModalProps> = ({ isOpen, onClose, customer, onPaymentSuccess }) => {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const [amountPaid, setAmountPaid] = useState<string>('');
  const [isSendingDirectWhatsApp, setIsSendingDirectWhatsApp] = useState<boolean>(false);
  const [lastPaymentResult, setLastPaymentResult] = useState<{
    paymentId?: number;
    receiptNo: string;
    amount: number;
    newRemaining: number;
    date: string;
  } | null>(null);
  const mutationIdRef = useRef<string | null>(null);

  const { data: settings } = useQuery({
    queryKey: ['settings'],
    queryFn: getSettings,
  });

  const collectorName = user?.full_name || 'المحصل الميداني';
  const stationName = settings?.station_name && settings.station_name !== 'محطة الطاقة الذكية'
    ? settings.station_name
    : 'محطة الضياء لتوليد الطاقة الكهربائية';
  const stationPhone = settings?.station_phone || '783270260 _ 736955883';
  const bankAccountNum = settings?.bank_accounts || '3052001225';

  const planPrice = Number((customer as any)?.unitPrice ?? (customer as any)?.unit_price ?? (customer as any)?.kwh_price ?? customer?.subscription_plan?.kwh_price ?? 1500);
  const planFee = Number((customer as any)?.serviceFee ?? (customer as any)?.service_fee ?? (customer as any)?.fixed_fee ?? customer?.subscription_plan?.fixed_fee ?? 1000);

  const defaultPolicyText = `o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.
o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.
o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان الف ريال
o يتحمل المشترك مديونية أي موظف إن لم يكن هناك سند رسمي مختوم بختم المحطة.
o سعر الكيلوواط/ ساعة ${planPrice.toLocaleString('en-US')} ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.`;

  const policyLines = (settings?.invoice_policy_text || defaultPolicyText)
    .replace(/1500/g, planPrice.toLocaleString('en-US'))
    .split('\n')
    .filter((l: string) => l.trim().length > 0);

  const cycleVal = (customer as any)?.billing_cycle || (customer as any)?.cycle || (customer?.invoices?.[0]?.billing_cycle) || '';
  const cleanCycle = cycleVal ? cycleVal.replace(/^دورة\s*/, '').trim() : '';

  React.useEffect(() => {
    if (isOpen) {
      setAmountPaid('');
      setLastPaymentResult(null);
      mutationIdRef.current = null;
    }
  }, [isOpen, customer?.id]);

  // Compute units consumed with fallback logic
  const computedUnits = useMemo(() => {
    if (!customer) return 0;
    
    // 1. Explicit properties passed directly
    const directUnits = (customer as any).units ?? (customer as any).units_consumed ?? (customer as any).consumption;
    if (directUnits !== undefined && directUnits !== null && !Number.isNaN(Number(directUnits)) && Number(directUnits) > 0) {
      return Number(directUnits);
    }

    // 2. From recent invoices
    if (customer.invoices && customer.invoices.length > 0) {
      const inv = customer.invoices[0];
      const invUnits = inv.consumption ?? inv.units_consumed ?? (Number(inv.current_reading || 0) - Number(inv.previous_reading || 0));
      if (invUnits !== undefined && !Number.isNaN(Number(invUnits)) && Number(invUnits) > 0) {
        return Number(invUnits);
      }
    }

    // 3. From recent meter readings list
    if (customer.meter_readings && customer.meter_readings.length > 0) {
      const mr = customer.meter_readings[0];
      const mrUnits = mr.units ?? mr.consumption ?? mr.units_consumed;
      if (mrUnits !== undefined && !Number.isNaN(Number(mrUnits)) && Number(mrUnits) > 0) {
        return Number(mrUnits);
      }
      const readingVal = Number(mr.reading_value || mr.current_reading || 0);
      const prevVal = Number(mr.previous_reading || (customer.meter_readings.length > 1 ? customer.meter_readings[1].reading_value : customer.previous_reading || customer.initial_reading || 0));
      if (readingVal > prevVal) {
        return readingVal - prevVal;
      }
      return 0;
    }

    // 4. From customer's last_reading / currReading vs prevReading
    const curr = Number((customer as any).currReading ?? customer.last_reading ?? 0);
    const prev = Number((customer as any).prevReading ?? customer.previous_reading ?? customer.initial_reading ?? 0);
    if (curr > prev) {
      return curr - prev;
    }

    return 0;
  }, [customer]);

  // 1. Compute total invoice gross amount
  const invoiceTotalDue = useMemo(() => {
    if (!customer) return 0;
    const candidates = [
      (customer as any).totalDue,
      customer.total_due,
      (customer as any).total_amount,
      (customer as any).dueAmount,
    ];
    for (const val of candidates) {
      if (val !== undefined && val !== null && !Number.isNaN(Number(val)) && Number(val) !== 0) {
        return Number(val);
      }
    }
    const consumptionCost = computedUnits * planPrice;
    const arrears = Number((customer as any).arrears ?? customer.arrears ?? 0);
    return consumptionCost + planFee + arrears;
  }, [customer, computedUnits, planPrice, planFee]);

  // 2. Compute previously paid amount on this invoice/customer
  const previousPaidAmount = useMemo(() => {
    if (!customer) return 0;
    const candidates = [
      (customer as any).paidAmount,
      (customer as any).paid_amount,
      (customer as any).total_paid,
    ];
    for (const val of candidates) {
      if (val !== undefined && val !== null && !Number.isNaN(Number(val)) && Number(val) >= 0) {
        return Number(val);
      }
    }
    return 0;
  }, [customer]);

  // 3. Compute net current remaining balance due before this payment
  const currentRemaining = useMemo(() => {
    if (!customer) return 0;
    if ((customer as any).remaining !== undefined && (customer as any).remaining !== null && !Number.isNaN(Number((customer as any).remaining))) {
      return Number((customer as any).remaining);
    }
    if ((customer as any).remaining_amount !== undefined && (customer as any).remaining_amount !== null && !Number.isNaN(Number((customer as any).remaining_amount))) {
      return Number((customer as any).remaining_amount);
    }
    if (invoiceTotalDue > 0 || previousPaidAmount > 0) {
      return invoiceTotalDue - previousPaidAmount;
    }
    return Number(customer.arrears ?? customer.balance ?? 0);
  }, [customer, invoiceTotalDue, previousPaidAmount]);

  // Build the complete ComputedGridRow representing the updated invoice
  const updatedComputedRow: ComputedGridRow | null = useMemo(() => {
    if (!customer || !lastPaymentResult) return null;
    const consumptionCost = computedUnits * planPrice;
    const prevReading = Number((customer as any).prevReading ?? customer.previous_reading ?? customer.initial_reading ?? 0);
    const currReading = Number((customer as any).currReading ?? customer.last_reading ?? (prevReading + computedUnits));
    const arrears = Number((customer as any).arrears ?? customer.arrears ?? 0);
    
    return {
      id: customer.id,
      subNumber: customer.subscriber_number || `${customer.id}`,
      route: customer.route_number || '1',
      name: customer.full_name,
      address: customer.address || '',
      meterNumber: customer.meter_number || '',
      phone: customer.phone_number || '',
      prevReading,
      currReading,
      units: computedUnits,
      unitPrice: planPrice,
      serviceFee: planFee,
      consumptionCost,
      arrears,
      totalDue: invoiceTotalDue,
      currentReceiptAmount: lastPaymentResult.amount,
      paidAmount: lastPaymentResult.amount,
      totalPaid: (lastPaymentResult as any).totalPaid ?? (previousPaidAmount + lastPaymentResult.amount),
      remaining: lastPaymentResult.newRemaining,
      sent: false,
    };
  }, [customer, lastPaymentResult, computedUnits, invoiceTotalDue, previousPaidAmount, planPrice, planFee]);

  const mutation = useMutation({
    mutationFn: ({ id, invoiceId, amount, name, clientMutationId }: { id: number; invoiceId?: number; amount: number; name: string; clientMutationId: string }) => 
      payInvoice(id, amount, name, clientMutationId, invoiceId),
    onSuccess: (data: any) => {
      invalidateFinancialTree(queryClient);
      queryClient.invalidateQueries({ queryKey: QUERY_KEYS.customers.detail(customer?.id) });

      const paidNum = parseFormattedNumber(amountPaid);
      const newRemaining = currentRemaining - paidNum;
      const newTotalPaid = previousPaidAmount + paidNum;
      const receiptNo = data?.payment?.receipt_number || `REC-${Date.now().toString().slice(-6)}`;
      const paymentId = Number(data?.payment?.id || data?.payment_id || data?.data?.id);

      setLastPaymentResult({
        paymentId: Number.isInteger(paymentId) && paymentId > 0 ? paymentId : undefined,
        receiptNo,
        amount: paidNum,
        totalPaid: newTotalPaid,
        newRemaining,
        date: new Date().toLocaleDateString('en-GB'),
      } as any);

      toast.success(
        user?.role === 'ADMIN' 
          ? 'تم تسجيل السداد واعتماده وتحديث الفاتورة بنجاح!' 
          : 'تم تسجيل السداد وهو قيد المراجعة!'
      );

      if (onPaymentSuccess && customer) {
        onPaymentSuccess(customer, paidNum);
      }
    },
    onError: (err: any) => {
      toast.error(err.response?.data?.message || err.message || 'فشل عملية السداد');
    }
  });

  if (!isOpen || !customer) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const num = parseFormattedNumber(amountPaid);
    if (!amountPaid || Number.isNaN(num) || num <= 0) {
      toast.error('يرجى إدخال مبلغ سداد صحيح أكبر من الصفر');
      return;
    }

    try {
      const targetInvoiceId = (customer as any).invoice_id || (customer as any).invoiceId || customer.invoices?.[0]?.id;
      mutation.mutate({
        id: customer.id,
        invoiceId: targetInvoiceId,
        amount: num,
        name: collectorName,
        clientMutationId: mutationIdRef.current ?? (mutationIdRef.current = generateUUID())
      });
    } catch (err: any) {
      toast.error(`فشل تسجيل السداد: ${err.message}`);
    }
  };

  const handlePrintInvoice = () => {
    const custName = customer.full_name || 'مشترك';
    const subNo = customer.subscriber_number || customer.id;
    printElementViaIframe(
      'printable-official-invoice-grid',
      `فاتورة_${custName}_${subNo}`,
      { orientation: 'landscape', pageSize: 'A4', margin: '4mm' }
    );
  };

  const handleSendWhatsAppInvoice = async () => {
    if (!updatedComputedRow) return;
    const phone = formatYemeniPhone(customer.phone_number);
    if (!phone || phone.length < 9) {
      toast.error('رقم هاتف المشترك غير صحيح أو غير متوفر');
      return;
    }

    if (!lastPaymentResult?.paymentId) {
      toast.error('لا يوجد معرّف سند سداد صالح للإرسال');
      return;
    }

    setIsSendingDirectWhatsApp(true);
    const loadToast = toast.loading('جاري إرسال سند القبض عبر واتساب...');
    try {
      const res = await sendReceiptWhatsAppApi(lastPaymentResult.paymentId);
      toast.success(res?.message || `تم إرسال سند القبض إلى واتساب المشترك (${customer.full_name}) بنجاح!`, { id: loadToast });
    } catch (err: any) {
      const errorMsg = err.response?.data?.message || err.message || 'خدمة الواتساب غير متصلة بالهاتف حالياً. يرجى ربط الهاتف أولاً من صفحة الإعدادات.';
      toast.error(errorMsg, { id: loadToast, duration: 5000 });
    } finally {
      setIsSendingDirectWhatsApp(false);
    }
  };

  const handlePrintAndWhatsApp = async () => {
    handlePrintInvoice();
    await handleSendWhatsAppInvoice();
  };

  return (
    <div className="fixed inset-0 bg-slate-900/60 flex items-center justify-center z-50 p-2 sm:p-4 backdrop-blur-sm overflow-y-auto" dir="rtl">
      <div className={`bg-white border border-slate-300 rounded-3xl w-full shadow-2xl relative overflow-hidden text-right my-3 max-h-[95vh] flex flex-col ${
        lastPaymentResult ? 'max-w-5xl' : 'max-w-lg p-6'
      }`}>
        
        {/* Post-Payment Full Official Double-Stub Invoice View */}
        {lastPaymentResult && updatedComputedRow ? (
          <>
            {/* Top Action Controls Bar */}
            <div className="bg-slate-100 px-6 py-3.5 border-b border-slate-200 flex flex-wrap justify-between items-center gap-2 no-print">
              <div className="flex items-center gap-2">
                <div className="p-1.5 bg-emerald-100 text-emerald-700 rounded-lg">
                  <CheckCircle size={18} />
                </div>
                <div>
                  <h2 className="text-sm font-bold text-slate-900">تم السداد بنجاح - الفاتورة الرسمية المعتمدة (الكعب المزدوج)</h2>
                  <span className="text-[11px] text-slate-500 font-mono">سند: {lastPaymentResult.receiptNo}</span>
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
                  onClick={handlePrintInvoice}
                  className="bg-blue-600 hover:bg-blue-700 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-blue-500/20 cursor-pointer"
                >
                  <Printer size={15} />
                  <span>طباعة الفاتورة</span>
                </button>

                <button
                  type="button"
                  onClick={handleSendWhatsAppInvoice}
                  disabled={isSendingDirectWhatsApp}
                  className="bg-emerald-600 hover:bg-emerald-700 disabled:opacity-60 text-white px-3.5 py-2 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md shadow-emerald-500/20 cursor-pointer"
                >
                  {isSendingDirectWhatsApp ? (
                    <Loader2 size={15} className="animate-spin" />
                  ) : (
                    <Send size={15} className="transform -rotate-45" />
                  )}
                  <span>{isSendingDirectWhatsApp ? 'جاري الإرسال...' : 'إرسال واتساب'}</span>
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
                            <span className="font-black text-black">{updatedComputedRow.name || '-'}</span>
                          </div>
                          <div>
                            <span>العنوان : </span>
                            <span>{updatedComputedRow.address || '-'}</span>
                          </div>
                          <div>
                            <span>رقم المشترك : </span>
                            <span className="font-mono font-black">{updatedComputedRow.subNumber || '-'}</span>
                          </div>
                          <div>
                            <span>رقم العداد : </span>
                            <span className="font-mono font-black">{updatedComputedRow.meterNumber || '-'}</span>
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
                              <th colSpan={2} className="border border-black py-1">قــــــراءة العداد</th>
                              <th rowSpan={2} className="border border-black py-1">الفارق</th>
                              <th rowSpan={2} className="border border-black py-1">متأخرات</th>
                              <th rowSpan={2} className="border border-black py-1">الاجمالي</th>
                            </tr>
                            <tr className="bg-white font-black border-b-2 border-black">
                              <th className="border border-black py-0.5">ق.السابقة</th>
                              <th className="border border-black py-0.5">ق.الحالية</th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr className="font-black text-[10px]">
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.prevReading || 0) > 0 ? Number(updatedComputedRow.prevReading).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.currReading || 0) > 0 ? Number(updatedComputedRow.currReading).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.units || 0) > 0 ? Number(updatedComputedRow.units).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.arrears || 0) > 0 ? Number(updatedComputedRow.arrears).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono text-black font-extrabold">
                                {Number(updatedComputedRow.totalDue || 0) !== 0 
                                  ? (Number(updatedComputedRow.totalDue) > 0 ? Number(updatedComputedRow.totalDue).toLocaleString('en-US') : `-${Math.abs(Number(updatedComputedRow.totalDue)).toLocaleString('en-US')}`) 
                                  : ''}
                              </td>
                            </tr>
                          </tbody>
                        </table>

                        {/* Financial Snapshot */}
                        <div className="bg-slate-100 border border-black p-1.5 text-[9px] font-black space-y-0.5">
                          <div className="flex justify-between">
                            <span>إجمالي المستحق:</span>
                            <span className="font-mono text-black font-black">{Number(updatedComputedRow.totalDue || 0).toLocaleString('en-US')} ر.ي</span>
                          </div>
                          <div className="flex justify-between">
                            <span>المقبوض بهذا السند:</span>
                            <span className="font-mono text-emerald-800 font-black">{Number(lastPaymentResult.amount || 0).toLocaleString('en-US')} ر.ي</span>
                          </div>
                          <div className="flex justify-between border-t border-black/30 pt-0.5">
                            <span>{updatedComputedRow.remaining < 0 ? 'الرصيد الدائن (فائض):' : 'المتبقي بعد السداد:'}</span>
                            <span className={`font-mono ${updatedComputedRow.remaining < 0 ? 'text-emerald-800 font-black' : 'text-rose-800 font-black'}`}>
                              {updatedComputedRow.remaining < 0 
                                ? `-${Math.abs(Number(updatedComputedRow.remaining)).toLocaleString('en-US')} ر.ي`
                                : `${Number(updatedComputedRow.remaining || 0).toLocaleString('en-US')} ر.ي`}
                            </span>
                          </div>
                        </div>
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
                              <span className="font-black text-black">{updatedComputedRow.name || '-'}</span>
                            </div>
                            <div className="font-mono text-black">
                              <span>رقم السند : </span>
                              <span>{lastPaymentResult.receiptNo}</span>
                            </div>
                          </div>

                          <div>
                            <span>العنوان : </span>
                            <span>{updatedComputedRow.address || '-'}</span>
                          </div>

                          <div>
                            <span>رقم المشترك : </span>
                            <span className="font-mono font-black">{updatedComputedRow.subNumber || '-'}</span>
                          </div>

                          <div className="flex justify-between items-center">
                            <div>
                              <span>رقم العداد : </span>
                              <span className="font-mono font-black">{updatedComputedRow.meterNumber || '-'}</span>
                            </div>
                            <div className="font-mono pl-4">
                              <span>رقم خط السير : </span>
                              <span>{updatedComputedRow.route || '-'}</span>
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
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.prevReading || 0) > 0 ? Number(updatedComputedRow.prevReading).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.currReading || 0) > 0 ? Number(updatedComputedRow.currReading).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.units || 0) > 0 ? Number(updatedComputedRow.units).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.serviceFee || 0) > 0 ? Number(updatedComputedRow.serviceFee).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.consumptionCost || 0) > 0 ? Number(updatedComputedRow.consumptionCost).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono">{Number(updatedComputedRow.arrears || 0) > 0 ? Number(updatedComputedRow.arrears).toLocaleString('en-US') : ''}</td>
                              <td className="border border-black py-1 font-mono text-black font-extrabold">
                                {Number(updatedComputedRow.totalDue || 0) !== 0 
                                  ? (Number(updatedComputedRow.totalDue) > 0 ? Number(updatedComputedRow.totalDue).toLocaleString('en-US') : `-${Math.abs(Number(updatedComputedRow.totalDue)).toLocaleString('en-US')}`) 
                                  : ''}
                              </td>
                            </tr>
                          </tbody>
                        </table>

                        {/* Financial Settlement Breakdown Card in Main Invoice */}
                        <div className="border-2 border-black bg-slate-50 p-1.5 rounded mb-2 text-[10px] font-black">
                          <div className={`grid ${Number((lastPaymentResult as any)?.totalPaid || 0) > Number(lastPaymentResult.amount || 0) ? 'grid-cols-4' : 'grid-cols-3'} gap-1 text-center`}>
                            <div className="border-l border-black pl-1">
                              <span className="text-slate-700 block text-[9px]">إجمالي المستحق</span>
                              <span className="font-mono text-black text-[11px] font-black">{Number(updatedComputedRow.totalDue || 0).toLocaleString('en-US')} ر.ي</span>
                            </div>
                            <div className="border-l border-black pl-1">
                              <span className="text-emerald-800 block text-[9px]">المقبوض بهذا السند</span>
                              <span className="font-mono text-emerald-700 text-[11px] font-black">{Number(lastPaymentResult.amount || 0).toLocaleString('en-US')} ر.ي</span>
                            </div>
                            {Number((lastPaymentResult as any)?.totalPaid || 0) > Number(lastPaymentResult.amount || 0) && (
                              <div className="border-l border-black pl-1">
                                <span className="text-blue-800 block text-[9px]">إجمالي المدفوع حتى الآن</span>
                                <span className="font-mono text-blue-800 text-[11px] font-black">{Number((lastPaymentResult as any)?.totalPaid || 0).toLocaleString('en-US')} ر.ي</span>
                              </div>
                            )}
                            <div>
                              <span className="text-slate-700 block text-[9px]">
                                {updatedComputedRow.remaining < 0 ? 'الرصيد الدائن (فائض)' : 'الرصيد المتبقي'}
                              </span>
                              <span className={`font-mono text-[11px] font-black ${updatedComputedRow.remaining > 0 ? 'text-red-700' : 'text-emerald-700 font-extrabold'}`}>
                                {updatedComputedRow.remaining > 0
                                  ? `+${Number(updatedComputedRow.remaining).toLocaleString('en-US')} ر.ي (متبقي عليك)`
                                  : updatedComputedRow.remaining < 0
                                  ? `-${Math.abs(Number(updatedComputedRow.remaining)).toLocaleString('en-US')} ر.ي (دائن لك ✅)`
                                  : '0 ر.ي (مسدد بالكامل ✅)'}
                              </span>
                            </div>
                          </div>
                        </div>

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
                            <div className="text-slate-400 text-xs mt-1">....................</div>
                          </div>
                          <div className="text-center font-mono">
                            <div>التاريخ : {lastPaymentResult.date}</div>
                          </div>
                          <div className="text-center">
                            <div>الحسابات</div>
                            <div className="text-slate-400 text-xs mt-1">....................</div>
                          </div>
                        </div>
                      </div>
                    </div>

                  </div>
                </div>
              </div>
            </div>
          </>
        ) : (
          /* Payment Form View */
          <div>
            {/* Header */}
            <div className="flex items-center justify-between pb-4 border-b border-slate-200 mb-5 relative z-10">
              <h2 className="text-xl font-black text-slate-900 flex items-center gap-2">
                <div className="p-2 bg-emerald-50 text-emerald-600 rounded-xl">
                  <Banknote size={24} />
                </div>
                سداد فاتورة / سند قبض مالي
              </h2>
              <button 
                onClick={onClose} 
                className="text-slate-400 hover:text-rose-600 hover:bg-rose-50 p-2 rounded-xl transition-colors"
              >
                <X size={20} />
              </button>
            </div>

            {/* Comprehensive Customer Details Card */}
            <div className="bg-slate-50 border border-slate-200 rounded-2xl p-4 mb-5 space-y-2.5 text-xs">
              <div className="flex justify-between items-center border-b border-slate-200 pb-2">
                <span className="text-slate-500 font-semibold flex items-center gap-1">
                  <User size={14} className="text-blue-600" />
                  اسم المشترك
                </span>
                <span className="text-slate-900 font-extrabold text-sm">{customer.full_name}</span>
              </div>

              <div className="grid grid-cols-2 gap-2 text-slate-700">
                <div className="flex items-center gap-1">
                  <Hash size={13} className="text-slate-400" />
                  <span>رقم الحساب:</span>
                  <strong className="font-mono text-slate-900">{customer.subscriber_number || customer.id}</strong>
                </div>
                <div className="flex items-center gap-1">
                  <Smartphone size={13} className="text-slate-400" />
                  <span>الهاتف:</span>
                  <strong className="font-mono text-slate-900">{customer.phone_number || '--'}</strong>
                </div>
                <div className="flex items-center gap-1">
                  <Gauge size={13} className="text-slate-400" />
                  <span>العداد:</span>
                  <strong className="font-mono text-slate-900">{customer.meter_number || '--'}</strong>
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-amber-700 font-bold">⚡ الاستهلاك:</span>
                  <strong className="font-mono text-amber-900 font-bold">{computedUnits.toLocaleString('en-US')} ك.و</strong>
                </div>
              </div>

              <div className="bg-slate-100 border border-slate-200 p-3 rounded-2xl mt-2 space-y-2">
                <div className="flex justify-between items-center text-xs">
                  <span className="text-slate-600 font-bold">إجمالي الفاتورة:</span>
                  <span className="text-slate-900 font-extrabold font-mono">
                    {invoiceTotalDue.toLocaleString('en-US')} ر.ي
                  </span>
                </div>

                {previousPaidAmount > 0 && (
                  <div className="flex justify-between items-center text-xs text-emerald-800 font-bold">
                    <span>المسدد سابقاً:</span>
                    <span className="font-mono font-extrabold">{previousPaidAmount.toLocaleString('en-US')} ر.ي</span>
                  </div>
                )}

                <div className={`flex justify-between items-center text-xs font-bold border-t border-slate-200 pt-1.5 ${
                  currentRemaining > 0 ? 'text-rose-700' : 'text-emerald-700'
                }`}>
                  <span>{currentRemaining >= 0 ? 'المتبقي الحالي المطلوب سداده:' : 'الرصيد الدائن الحالي للمشترك:'}</span>
                  <span className="text-sm font-mono font-black">
                    {currentRemaining === 0 
                      ? '0 ر.ي (خالص تماماً ✅)' 
                      : currentRemaining > 0
                        ? `${currentRemaining.toLocaleString('en-US')} ر.ي`
                        : `-${Math.abs(currentRemaining).toLocaleString('en-US')} ر.ي`}
                  </span>
                </div>

                {parseFormattedNumber(amountPaid) > 0 && (
                  <>
                    <div className="flex justify-between items-center text-xs border-t border-slate-200 pt-1.5 text-emerald-800 font-bold">
                      <span>المبلغ المخصوم (المدفوع الآن):</span>
                      <span className="font-mono font-extrabold">- {parseFormattedNumber(amountPaid).toLocaleString('en-US')} ر.ي</span>
                    </div>

                    <div className={`flex justify-between items-center text-xs font-bold border-t border-slate-200 pt-1.5 ${
                      (currentRemaining - parseFormattedNumber(amountPaid)) > 0 ? 'text-rose-700' : 'text-emerald-700'
                    }`}>
                      <span>{(currentRemaining - parseFormattedNumber(amountPaid)) >= 0 ? 'المتبقي بعد هذا السداد:' : 'رصيد دائن للمشترك (فائض):'}</span>
                      <span className="text-base font-mono font-black">
                        {(currentRemaining - parseFormattedNumber(amountPaid)) === 0 
                          ? '0 ر.ي (تم السداد بالكامل ✅)' 
                          : (currentRemaining - parseFormattedNumber(amountPaid)) > 0
                            ? `${(currentRemaining - parseFormattedNumber(amountPaid)).toLocaleString('en-US')} ر.ي`
                            : `-${Math.abs(currentRemaining - parseFormattedNumber(amountPaid)).toLocaleString('en-US')} ر.ي`}
                      </span>
                    </div>
                  </>
                )}
              </div>
            </div>

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label htmlFor="payment-amount-input" className="text-slate-700 text-xs font-bold mb-1.5 flex items-center gap-1.5 cursor-pointer">
                  <AlertTriangle size={15} className="text-amber-500" />
                  المبلغ المراد سداده (ريال يمني) *
                </label>
                <input
                  id="payment-amount-input"
                  name="amountPaid"
                  type="text"
                  inputMode="decimal"
                  required
                  autoFocus
                  aria-label="المبلغ المدفوع بالريال اليمني"
                  data-testid="payment-amount-input"
                  placeholder="مثال: 5,000"
                  value={amountPaid}
                  onChange={(e) => setAmountPaid(formatInputAsCurrency(e.target.value))}
                  className="w-full bg-slate-50 border-2 border-slate-300 rounded-2xl px-4 py-3.5 text-slate-900 text-2xl font-mono font-black focus:outline-none focus:border-emerald-600 focus:bg-white transition-all text-center shadow-inner"
                />
                {parseFormattedNumber(amountPaid) > 0 && (
                  <div className="mt-2.5 p-3 bg-emerald-50 border-2 border-emerald-300 rounded-2xl space-y-1.5 text-xs animate-in fade-in duration-150">
                    <div className="flex justify-between items-center">
                      <span className="text-emerald-900 font-bold">المبلغ المسدد بالتنسيق المالي:</span>
                      <span className="text-emerald-800 font-mono font-black text-base">
                        {parseFormattedNumber(amountPaid).toLocaleString('en-US')} ريال يمني
                      </span>
                    </div>
                    <div className="flex justify-between items-center border-t border-emerald-200 pt-1.5">
                      <span className="text-slate-700 font-bold">الباقي بعد خصم هذا المبلغ:</span>
                      <span className={`font-mono font-black text-base ${
                        (currentRemaining - parseFormattedNumber(amountPaid)) > 0 ? 'text-rose-700' : 'text-emerald-700'
                      }`}>
                        {(currentRemaining - parseFormattedNumber(amountPaid)) === 0 
                          ? '0 ر.ي (خالص تماماً ✅)' 
                          : (currentRemaining - parseFormattedNumber(amountPaid)) > 0 
                            ? `${(currentRemaining - parseFormattedNumber(amountPaid)).toLocaleString('en-US')} ر.ي` 
                            : `-${Math.abs(currentRemaining - parseFormattedNumber(amountPaid)).toLocaleString('en-US')} ر.ي`}
                      </span>
                    </div>
                  </div>
                )}
              </div>

              <div className="pt-2 flex gap-3">
                <button
                  type="button"
                  id="cancel-payment-btn"
                  onClick={onClose}
                  className="flex-1 px-4 py-3 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-xl text-xs font-bold transition-all"
                >
                  إلغاء
                </button>
                <button
                  type="submit"
                  id="confirm-payment-btn"
                  data-testid="confirm-payment-btn"
                  disabled={mutation.isPending}
                  className="flex-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-emerald-500/20 flex items-center justify-center gap-2 disabled:opacity-50 cursor-pointer py-3"
                >
                  <CheckCircle size={16} />
                  {mutation.isPending ? 'جاري السداد وتحديث الحساب...' : 'تأكيد السداد وإصدار الفاتورة'}
                </button>
              </div>
            </form>
          </div>
        )}
      </div>
    </div>
  );
};
