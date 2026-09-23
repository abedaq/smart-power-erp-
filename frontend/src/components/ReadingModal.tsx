import React, { useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { createReading, getCustomerById, getSettings } from '../lib/api';
import { sanitizeDecimalInput, generateUUID } from '../utils/formatters';
import { useAuth } from '../context/AuthContext';
import { Gauge, CheckCircle, X, Clock, Calendar, Zap, AlertTriangle, RefreshCw, Calculator } from 'lucide-react';
import toast from 'react-hot-toast';
import { QUERY_KEYS, invalidateReadingsTree } from '../constants/queryKeys';

interface ReadingModalProps {
  isOpen: boolean;
  onClose: () => void;
  customer: any;
}

export const ReadingModal: React.FC<ReadingModalProps> = ({ isOpen, onClose, customer }) => {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const [readingValue, setReadingValue] = useState<string>('');
  const mutationIdRef = useRef<string | null>(null);
  const [collectorName, setCollectorName] = useState<string>(
    user?.full_name || 'المحصل الميداني'
  );

  React.useEffect(() => {
    if (user?.full_name) {
      setCollectorName(user.full_name);
    }
  }, [user, isOpen]);

  React.useEffect(() => {
    if (isOpen) {
      setReadingValue('');
      mutationIdRef.current = null;
    }
  }, [isOpen, customer?.id]);

  // Fetch settings for tariff calculation
  const { data: settings } = useQuery({
    queryKey: QUERY_KEYS.settings,
    queryFn: getSettings,
    enabled: !!isOpen
  });

  // Fetch latest live customer details (with meter_readings & invoices) from backend when modal opens
  const { data: customerDetails, isLoading: isFetchingDetails } = useQuery({
    queryKey: QUERY_KEYS.customers.detail(customer?.id),
    queryFn: () => getCustomerById(customer.id),
    enabled: !!isOpen && !!customer?.id,
    refetchOnWindowFocus: true
  });

  const activeCustomer = customerDetails || customer;

  const mutation = useMutation({
    mutationFn: createReading,
    onSuccess: () => {
      invalidateReadingsTree(queryClient, customer?.id);
      toast.success('تم تسجيل القراءة الميدانية بنجاح! (قيد مراجعة واعتماد المدير)');
      setReadingValue('');
      onClose();
    },
    onError: async (err: any) => {
      toast.error(`فشل تسجيل القراءة: ${err.response?.data?.message || err.message}`);
    }
  });

  if (!isOpen || !customer) return null;

  // Extract previous reading and date from live customer details (sorted descending to guarantee latest reading)
  const sortedReadings = activeCustomer?.meter_readings
    ? [...activeCustomer.meter_readings].sort((a, b) => {
      const timeA = a.reading_date ? new Date(a.reading_date).getTime() : (a.id || 0);
      const timeB = b.reading_date ? new Date(b.reading_date).getTime() : (b.id || 0);
      return timeB - timeA;
    })
    : [];
  const lastReadingObj = sortedReadings[0];
  const previousReading = lastReadingObj ? Number(lastReadingObj.reading_value) : (Number(activeCustomer?.initial_reading) || 0);

  const previousReadingDateFormatted = lastReadingObj?.reading_date
    ? new Date(lastReadingObj.reading_date).toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: true
    })
    : 'قراءة ابتدائية عند الاشتراك';

  const newReadingNum = parseFloat(readingValue);
  const consumption = !isNaN(newReadingNum) ? newReadingNum - previousReading : null;

  // Tariff & Estimated Total Calculation
  const kwhPrice = activeCustomer?.subscription_plan?.kwh_price
    ? Number(activeCustomer.subscription_plan.kwh_price)
    : (settings?.default_kwh_price ? Number(settings.default_kwh_price) : 1400);

  const fixedFee = activeCustomer?.subscription_plan?.fixed_fee !== undefined
    ? Number(activeCustomer.subscription_plan.fixed_fee)
    : (settings?.default_fixed_fee ? Number(settings.default_fixed_fee) : 1000);

  const unpaidInvoices = activeCustomer?.invoices?.filter((inv: any) => inv.status === 'Unpaid' || inv.status === 'Partially_Paid') || [];
  const arrears = unpaidInvoices.reduce((sum: number, inv: any) => sum + Number(inv.remaining_amount || 0), 0);

  const estimatedConsumptionValue = consumption && consumption > 0 ? consumption * kwhPrice : 0;
  const estimatedTotalDue = consumption && consumption >= 0 ? estimatedConsumptionValue + fixedFee + arrears : null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isNaN(newReadingNum) || newReadingNum <= 0) {
      toast.error('يرجى إدخال قيمة قراءة صحيحة أكبر من الصفر');
      return;
    }
    if (newReadingNum < previousReading) {
      toast.error(`لا يمكن أن تكون القراءة الجديدة (${newReadingNum}) أقل من القراءة السابقة (${previousReading})`);
      return;
    }

    try {
      mutation.mutate({
        customer_id: activeCustomer.id,
        reading_value: newReadingNum,
        collector_name: collectorName,
        client_mutation_id: mutationIdRef.current ?? (mutationIdRef.current = generateUUID())
      });
    } catch (err: any) {
      toast.error(`فشل تسجيل القراءة: ${err.message}`);
    }
  };

  return (
    <div className="fixed inset-0 bg-slate-900/40 flex items-center justify-center z-50 p-4 backdrop-blur-sm" dir="rtl">
      <div className="bg-white border border-slate-200 rounded-3xl w-full max-w-md shadow-2xl overflow-hidden text-right text-slate-900">
        {/* Modal Header */}
        <div className="flex items-center justify-between p-5 border-b border-slate-200 bg-slate-50/80">
          <div className="flex items-center gap-2.5">
            <div className="p-2 bg-blue-50 text-blue-600 rounded-xl border border-blue-200">
              <Gauge size={20} />
            </div>
            <div>
              <h3 className="font-bold text-base text-slate-900">إدخال قراءة العداد الحالية</h3>
              <p className="text-slate-500 text-xs mt-0.5 font-medium">تسجيل القراءة الكلية واحتساب الفاتورة فوراً</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-slate-800 rounded-xl hover:bg-slate-100 transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        {/* Customer Summary Card */}
        <div className="p-5 space-y-4">
          <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 space-y-2 relative">
            {isFetchingDetails && (
              <div className="absolute left-3 top-3 text-blue-600 animate-spin">
                <RefreshCw size={14} />
              </div>
            )}
            <div className="flex justify-between items-center">
              <span className="text-slate-500 text-xs font-semibold">اسم المشترك:</span>
              <span className="font-bold text-slate-900 text-sm">{activeCustomer.full_name}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-slate-500 text-xs font-semibold">رقم المشترك:</span>
              <span className="font-mono text-blue-600 text-xs font-bold">#{activeCustomer.subscriber_number}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-slate-500 text-xs font-semibold">رقم العداد:</span>
              <span className="font-mono text-slate-900 text-xs font-bold">{activeCustomer.meter_number || 'بدون رقم'}</span>
            </div>
          </div>

          {/* Highlighted Previous Reading & Date Card */}
          <div className="bg-blue-50/80 p-4 rounded-2xl border border-blue-200 shadow-sm space-y-2.5">
            <div className="flex justify-between items-center">
              <span className="text-slate-600 text-xs flex items-center gap-1.5 font-bold">
                <Clock size={15} className="text-blue-600" />
                القراءة السابقة المسجلة للعداد:
              </span>
              <span className="font-mono text-blue-700 text-base font-bold">
                {previousReading.toLocaleString('en-US')} kWh
              </span>
            </div>
            <div className="flex justify-between items-center text-xs border-t border-blue-200/60 pt-2">
              <span className="text-slate-500 flex items-center gap-1.5">
                <Calendar size={13} className="text-slate-400" />
                تاريخ القراءة السابقة:
              </span>
              <span className="text-slate-700 font-semibold font-mono text-[11px]">{previousReadingDateFormatted}</span>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-slate-800 text-xs font-bold mb-1.5">
                إجمالي قراءة العداد الحالية الجديدة (الأرقام والكسور الظاهرة على العداد) *
              </label>
              <input
                required
                type="text"
                inputMode="decimal"
                placeholder="أدخل القراءة الحالية (مثال: 1.30 أو 15.50)..."
                value={readingValue}
                onChange={(e) => setReadingValue(sanitizeDecimalInput(e.target.value))}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl px-4 py-3 text-slate-900 text-lg font-mono text-center focus:outline-none focus:border-blue-600 transition-colors font-bold shadow-inner"
              />

              {/* Real-time Meter Total & Invoice Preview Card */}
              {consumption !== null && (
                <div className="mt-3 text-xs font-medium space-y-2">
                  {consumption < 0 ? (
                    <div className="bg-rose-50 border border-rose-200 text-rose-700 p-3 rounded-2xl flex items-center gap-2">
                      <AlertTriangle size={18} className="shrink-0" />
                      <span>تنبيه: القراءة الجديدة أقل من القراءة السابقة بـ ({Math.abs(consumption).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 })} kWh)!</span>
                    </div>
                  ) : (
                    <div className="bg-emerald-50/80 border border-emerald-200 p-3.5 rounded-2xl space-y-2.5 shadow-sm">
                      <div className="flex justify-between items-center text-xs">
                        <span className="text-emerald-800 font-bold flex items-center gap-1">
                          <Zap size={14} className="text-emerald-600 animate-pulse" />
                          صافي الاستهلاك المحتسب:
                        </span>
                        <span className="font-mono font-bold text-emerald-700">
                          +{consumption.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 })} kWh
                        </span>
                      </div>

                      {estimatedTotalDue !== null && (
                        <div className="flex justify-between items-center border-t border-emerald-200/70 pt-2 text-xs">
                          <span className="text-slate-700 font-bold flex items-center gap-1">
                            <Calculator size={14} className="text-blue-600" />
                            إجمالي الفاتورة والمبلغ المستحق المتوقع:
                          </span>
                          <span className="font-mono font-black text-blue-700 text-sm">
                            {estimatedTotalDue.toLocaleString('en-US')} ر.ي
                          </span>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>



            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2.5 text-slate-500 hover:text-slate-800 text-xs font-semibold"
              >
                إلغاء
              </button>
              <button
                type="submit"
                disabled={mutation.isPending || (consumption !== null && consumption < 0)}
                className="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2.5 rounded-xl text-xs font-bold transition-all shadow-md shadow-blue-500/20 flex items-center gap-2 disabled:opacity-50"
              >
                <CheckCircle size={16} />
                {mutation.isPending ? 'جاري الحفظ...' : 'حفظ القراءة وإرسالها للمدير'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};
