import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { 
  X, User, Gauge, 
  FileText, CheckCircle2, 
  Clock, AlertCircle, RefreshCw, DollarSign
} from 'lucide-react';
import type { Customer } from '../types';
import { updateReadingApi, getCustomerById } from '../lib/api';
import { useAuth } from '../context/AuthContext';

interface StatementModalProps {
  isOpen: boolean;
  onClose: () => void;
  customer: Customer | null;
}

export const StatementModal: React.FC<StatementModalProps> = ({
  isOpen,
  onClose,
  customer,
}) => {
  const queryClient = useQueryClient();
  const { user } = useAuth();
  const [activeTab, setActiveTab] = useState<'profile' | 'readings' | 'invoices' | 'payments'>('profile');

  // Fetch full live customer details (readings, invoices, payments) via local backend API
  const { data: customerDetails, isLoading, refetch: refetchCustomerDetails } = useQuery({
    queryKey: ['customer_details_statement', customer?.id],
    queryFn: async () => {
      if (!customer?.id) return null;
      try {
        const details = await getCustomerById(customer.id);
        if (details) return details;
      } catch (e) {
        console.warn('Failed to fetch customer statement details:', e);
      }

      return customer;
    },
    enabled: isOpen && !!customer?.id,
  });

  const liveCustomer = customerDetails || customer;
  const readings = liveCustomer?.meter_readings || [];
  const invoices = liveCustomer?.invoices || [];
  const payments = liveCustomer?.payments || [];
  const isLoadingReadings = isLoading;
  const isLoadingInvoices = isLoading;
  const isLoadingPayments = isLoading;

  const updateReadingMutation = useMutation({
    mutationFn: ({ id, value }: { id: number; value: number }) => updateReadingApi(id, value),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard-summary'] });
      refetchCustomerDetails();
    },
    onError: (error: any) => alert(`تعذر تعديل القراءة: ${error.message}`)
  });

  if (!isOpen || !customer) return null;

  const totalDue = customer.total_due ?? customer.arrears ?? 0;
  const hasDue = totalDue > 0;

  const handleEditReading = (reading: any) => {
    const raw = window.prompt('أدخل قيمة القراءة الجديدة:', String(reading.reading_value));
    if (raw === null) return;
    const value = Number(raw);
    if (!Number.isFinite(value) || value < 0) {
      alert('قيمة القراءة غير صحيحة');
      return;
    }
    updateReadingMutation.mutate({ id: reading.id, value });
  };

  const getStatusBadge = (status?: string) => {
    const s = (status || 'Active').toLowerCase();
    if (s === 'active') {
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
          <CheckCircle2 size={12} />
          نشط (Active)
        </span>
      );
    }
    if (s === 'cut') {
      return (
        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold bg-rose-50 text-rose-700 border border-rose-200">
          <AlertCircle size={12} />
          مفصول للتعثر (Cut)
        </span>
      );
    }
    return (
      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold bg-slate-100 text-slate-700 border border-slate-300">
        <Clock size={12} />
        موقف (Inactive)
      </span>
    );
  };

  const handleRefreshAll = () => {
    refetchCustomerDetails();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fade-in">
      <div className="bg-white w-full max-w-4xl rounded-2xl shadow-2xl border border-slate-100 overflow-hidden flex flex-col max-h-[90vh]">
        
        {/* Header */}
        <div className="px-6 py-4 bg-gradient-to-r from-slate-900 via-blue-950 to-slate-900 text-white flex justify-between items-center">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-xl bg-blue-500/20 border border-blue-400/30 flex items-center justify-center text-blue-400">
              <User size={22} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-white">{customer.full_name}</h2>
                <span className="font-mono text-xs bg-blue-500/20 text-blue-300 px-2 py-0.5 rounded-lg border border-blue-400/30 font-bold">
                  #{customer.subscriber_number}
                </span>
                {getStatusBadge(customer.status)}
              </div>
              <p className="text-xs text-slate-300 mt-0.5 flex items-center gap-3">
                <span>هاتف: <span className="font-mono">{customer.phone_number}</span></span>
                <span>•</span>
                <span>عداد: <span className="font-mono">{customer.meter_number || 'بدون عداد'}</span></span>
                <span>•</span>
                <span>المسار: <span className="font-mono font-bold text-amber-300">{customer.route_number || 'A1'}</span></span>
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={handleRefreshAll}
              title="تحديث البيانات"
              className="p-2 hover:bg-white/10 rounded-xl text-slate-300 hover:text-white transition-colors"
            >
              <RefreshCw size={18} />
            </button>
            <button
              onClick={onClose}
              className="p-2 hover:bg-white/10 rounded-xl text-slate-300 hover:text-white transition-colors"
            >
              <X size={20} />
            </button>
          </div>
        </div>

        {/* Due summary ribbon */}
        <div className="bg-slate-50 border-b border-slate-200 px-6 py-3 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-6">
            <div>
              <div className="text-[11px] text-slate-500 font-medium">الرصيد المتبقي (المديونية)</div>
              <div className={`text-base font-black font-mono ${hasDue ? 'text-rose-600' : 'text-emerald-600'}`}>
                {Number(totalDue).toLocaleString('en-US')} ر.ي
              </div>
            </div>
            <div className="h-7 w-[1px] bg-slate-200" />
            <div>
              <div className="text-[11px] text-slate-500 font-medium">آخر قراءة معتمدة</div>
              <div className="text-sm font-bold font-mono text-blue-700">
                {Number(customer.last_reading ?? customer.initial_reading ?? 0).toLocaleString('en-US')} kWh
              </div>
            </div>
            <div className="h-7 w-[1px] bg-slate-200" />
            <div>
              <div className="text-[11px] text-slate-500 font-medium">التعريفة المطبقة</div>
              <div className="text-sm font-bold text-slate-800">
                {customer.subscription_plan?.plan_name || 'التعريفة الافتراضية'} ({Number(customer.subscription_plan?.kwh_price || 0).toLocaleString('en-US')} ر.ي)
              </div>
            </div>
          </div>

          {/* Navigation Tabs */}
          <div className="flex items-center gap-1 bg-slate-200/70 p-1 rounded-xl">
            <button
              onClick={() => setActiveTab('profile')}
              className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all flex items-center gap-1.5 ${
                activeTab === 'profile'
                  ? 'bg-white text-blue-700 shadow-sm'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              <User size={14} />
              بيانات المشترك
            </button>
            <button
              onClick={() => setActiveTab('readings')}
              className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all flex items-center gap-1.5 ${
                activeTab === 'readings'
                  ? 'bg-white text-blue-700 shadow-sm'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              <Gauge size={14} />
              سجل القراءات ({readings.length})
            </button>
            <button
              onClick={() => setActiveTab('invoices')}
              className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all flex items-center gap-1.5 ${
                activeTab === 'invoices'
                  ? 'bg-white text-blue-700 shadow-sm'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              <FileText size={14} />
              سجل الفواتير ({invoices.length})
            </button>
            <button
              onClick={() => setActiveTab('payments')}
              className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all flex items-center gap-1.5 ${
                activeTab === 'payments'
                  ? 'bg-white text-blue-700 shadow-sm'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              <DollarSign size={14} />
              سجل السدادات ({payments.length})
            </button>
          </div>
        </div>

        {/* Tab Content Body */}
        <div className="p-6 overflow-y-auto flex-1 bg-white">
          
          {/* TAB 1: Profile & General Info */}
          {activeTab === 'profile' && (
            <div className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200 space-y-3">
                  <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                    <User size={15} className="text-blue-600" />
                    المعلومات الشخصية والاشتراك
                  </h3>
                  <div className="space-y-2 text-xs">
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">الاسم الكامل:</span>
                      <span className="font-bold text-slate-900">{customer.full_name}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">رقم المشترك (الحساب):</span>
                      <span className="font-mono font-bold text-blue-600">#{customer.subscriber_number}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">رقم الهاتف:</span>
                      <span className="font-mono font-bold text-slate-900">{customer.phone_number}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">حالة الاشتراك:</span>
                      <span>{getStatusBadge(customer.status)}</span>
                    </div>
                    <div className="flex justify-between py-1.5">
                      <span className="text-slate-500 font-medium">العنوان والمنطقة:</span>
                      <span className="font-medium text-slate-800">{customer.address || 'غير محدد'}</span>
                    </div>
                  </div>
                </div>

                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200 space-y-3">
                  <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider flex items-center gap-1.5">
                    <Gauge size={15} className="text-amber-600" />
                    العداد والتعريفة الفنية
                  </h3>
                  <div className="space-y-2 text-xs">
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">رقم العداد:</span>
                      <span className="font-mono font-bold text-slate-900">{customer.meter_number || 'بدون عداد'}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">رقم المسار (Route):</span>
                      <span className="font-mono font-bold text-purple-700">{customer.route_number || 'A1'}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">خطة الاشتراك:</span>
                      <span className="font-bold text-slate-900">{customer.subscription_plan?.plan_name || 'التعريفة الافتراضية'}</span>
                    </div>
                    <div className="flex justify-between py-1.5 border-b border-slate-200/60">
                      <span className="text-slate-500 font-medium">سعر الكيلوواط:</span>
                      <span className="font-mono font-bold text-slate-900">{Number(customer.subscription_plan?.kwh_price || 0).toLocaleString('en-US')} ر.ي</span>
                    </div>
                    <div className="flex justify-between py-1.5">
                      <span className="text-slate-500 font-medium">القراءة الابتدائية:</span>
                      <span className="font-mono font-bold text-slate-900">{Number(customer.initial_reading || 0).toLocaleString('en-US')} kWh</span>
                    </div>
                  </div>
                </div>

              </div>

              {/* Financial Quick Card */}
              <div className={`p-4 rounded-xl border flex items-center justify-between ${
                hasDue ? 'bg-rose-50/60 border-rose-200' : 'bg-emerald-50/60 border-emerald-200'
              }`}>
                <div>
                  <div className="text-xs font-bold text-slate-700">الوضعية المالية للمشترك</div>
                  <div className="text-xs text-slate-500 mt-0.5">
                    {hasDue ? 'يوجد مبالغ ومتأخرات مستحقة بانتظار السداد' : 'الحساب خالص ولا توجد مديونية معلقة'}
                  </div>
                </div>
                <div className="text-left">
                  <div className={`text-xl font-black font-mono ${hasDue ? 'text-rose-600' : 'text-emerald-700'}`}>
                    {Number(totalDue).toLocaleString('en-US')} ر.ي
                  </div>
                  <div className="text-[10px] text-slate-400 font-medium">إجمالي المتبقي</div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: Meter Readings History */}
          {activeTab === 'readings' && (
            <div className="space-y-4">
              {isLoadingReadings ? (
                <div className="py-12 text-center text-slate-500 text-xs font-medium">جاري تحميل سجل القراءات...</div>
              ) : readings.length === 0 ? (
                <div className="py-12 text-center text-slate-500 text-xs font-medium bg-slate-50 rounded-xl border border-slate-200">
                  لا توجد قراءات مسجلة لهذا المشترك حتى الآن.
                </div>
              ) : (
                <div className="overflow-x-auto border border-slate-200 rounded-xl">
                  <table className="w-full text-right text-xs">
                    <thead>
                      <tr className="bg-slate-50 border-b border-slate-200 text-slate-600 font-bold">
                        <th className="px-4 py-3">القراءة (kWh)</th>
                        <th className="px-4 py-3">تاريخ القراءة</th>
                        <th className="px-4 py-3">بواسطة (المحصل / المسؤول)</th>
                        <th className="px-4 py-3">وقت وتاريخ الإدخال</th>
                        <th className="px-4 py-3 text-center">حالة الاعتماد</th>
                        {user?.role === 'ADMIN' && <th className="px-4 py-3 text-center">إجراء</th>}
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {readings.map((r: any) => {
                        const isApproved = (r.approval_status || 'APPROVED') === 'APPROVED';
                        return (
                          <tr key={r.id} className="hover:bg-slate-50/80 transition-colors">
                            <td className="px-4 py-3 font-mono font-bold text-blue-700 text-sm">
                              {Number(r.reading_value).toLocaleString('en-US')} kWh
                            </td>
                            <td className="px-4 py-3 font-medium text-slate-700">
                              {r.reading_date ? new Date(r.reading_date).toLocaleDateString('en-US') : '-'}
                            </td>
                            <td className="px-4 py-3 font-medium text-slate-900">
                              {r.collector_name || 'النظام'}
                            </td>
                            <td className="px-4 py-3 font-mono text-[11px] text-slate-500">
                              {r.created_at ? new Date(r.created_at).toLocaleString('en-US') : '-'}
                            </td>
                              <td className="px-4 py-3 text-center">
                                <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ${
                                  isApproved
                                    ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                                    : 'bg-amber-50 text-amber-800 border border-amber-200'
                                }`}>
                                  {isApproved ? 'معتمدة' : 'معلقة (بانتظار الاعتماد)'}
                                </span>
                              </td>
                              {user?.role === 'ADMIN' && (
                                <td className="px-4 py-3 text-center">
                                  {isApproved && (
                                    <button onClick={() => handleEditReading(r)} className="px-2.5 py-1 rounded-lg bg-blue-50 text-blue-700 border border-blue-200 font-bold hover:bg-blue-600 hover:text-white" disabled={updateReadingMutation.isPending}>
                                      تعديل
                                    </button>
                                  )}
                                </td>
                              )}
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {/* TAB 3: Invoices History */}
          {activeTab === 'invoices' && (
            <div className="space-y-4">
              {isLoadingInvoices ? (
                <div className="py-12 text-center text-slate-500 text-xs font-medium">جاري تحميل سجل الفواتير...</div>
              ) : invoices.length === 0 ? (
                <div className="py-12 text-center text-slate-500 text-xs font-medium bg-slate-50 rounded-xl border border-slate-200">
                  لا توجد فواتير مصدرة لهذا المشترك.
                </div>
              ) : (
                <div className="overflow-x-auto border border-slate-200 rounded-xl">
                  <table className="w-full text-right text-xs">
                    <thead>
                      <tr className="bg-slate-50 border-b border-slate-200 text-slate-600 font-bold">
                        <th className="px-4 py-3">رقم الفاتورة</th>
                        <th className="px-4 py-3">الدورة الشهرية</th>
                        <th className="px-4 py-3">الاستهلاك</th>
                        <th className="px-4 py-3">إجمالي المبلغ</th>
                        <th className="px-4 py-3">المسدد</th>
                        <th className="px-4 py-3">المتبقي</th>
                        <th className="px-4 py-3 text-center">الحالة</th>
                        <th className="px-4 py-3">تاريخ الإصدار</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {invoices.map((inv: any) => {
                        const status = (inv.status || 'UNPAID').toUpperCase();
                        const isPaid = status === 'PAID';
                        return (
                          <tr key={inv.id} className="hover:bg-slate-50/80 transition-colors">
                            <td className="px-4 py-3 font-mono font-bold text-blue-600">
                              #{inv.id}
                            </td>
                            <td className="px-4 py-3 font-medium text-slate-800">
                              {inv.billing_cycle || '-'}
                            </td>
                            <td className="px-4 py-3 font-mono font-semibold text-slate-700">
                              {Number(inv.consumption || (inv.current_reading - inv.previous_reading) || 0).toLocaleString('en-US')} kWh
                            </td>
                            <td className="px-4 py-3 font-mono font-bold text-slate-900">
                              {Number(inv.total_due || inv.total_amount || 0).toLocaleString('en-US')} ر.ي
                            </td>
                            <td className="px-4 py-3 font-mono font-semibold text-emerald-600">
                              {Number(inv.paid_amount || 0).toLocaleString('en-US')} ر.ي
                            </td>
                            <td className="px-4 py-3 font-mono font-bold text-rose-600">
                              {Number(inv.remaining_amount || 0).toLocaleString('en-US')} ر.ي
                            </td>
                            <td className="px-4 py-3 text-center">
                              <span className={`inline-flex px-2 py-0.5 rounded-full text-[10px] font-bold ${
                                isPaid
                                  ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                                  : 'bg-amber-50 text-amber-800 border border-amber-200'
                              }`}>
                                {isPaid ? 'مسددة بالكامل' : 'غير مسددة'}
                              </span>
                            </td>
                            <td className="px-4 py-3 font-mono text-[11px] text-slate-500">
                              {inv.created_at ? new Date(inv.created_at).toLocaleDateString('en-US') : '-'}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {/* TAB 4: Payments History */}
          {activeTab === 'payments' && (
            <div className="space-y-4">
              {isLoadingPayments ? (
                <div className="py-12 text-center text-slate-500 text-xs font-medium">جاري تحميل سجل السدادات...</div>
              ) : payments.length === 0 ? (
                <div className="py-12 text-center text-slate-500 text-xs font-medium bg-slate-50 rounded-xl border border-slate-200">
                  لا توجد سندات قبض أو سدادات مسجلة لهذا المشترك.
                </div>
              ) : (
                <div className="overflow-x-auto border border-slate-200 rounded-xl">
                  <table className="w-full text-right text-xs">
                    <thead>
                      <tr className="bg-slate-50 border-b border-slate-200 text-slate-600 font-bold">
                        <th className="px-4 py-3">رقم السند</th>
                        <th className="px-4 py-3">المبلغ المسدد</th>
                        <th className="px-4 py-3">المستلم (المحاسب / الكاشير)</th>
                        <th className="px-4 py-3">طريقة الدفع والملاحظات</th>
                        <th className="px-4 py-3">تاريخ ووقت السداد</th>
                        <th className="px-4 py-3 text-center">حالة السند</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {payments.map((p: any) => {
                        const status = (p.approval_status || 'APPROVED').toUpperCase();
                        const isReversed = status === 'REVERSED';
                        const isApproved = status === 'APPROVED';
                        return (
                          <tr key={p.id} className={`hover:bg-slate-50/80 transition-colors ${isReversed ? 'bg-rose-50/30' : ''}`}>
                            <td className="px-4 py-3 font-mono font-bold text-slate-900">
                              <div className="flex items-center gap-1.5">
                                <span>{p.receipt_number || `REC-${p.id}`}</span>
                                {isReversed && (
                                  <span className="bg-rose-100 text-rose-700 text-[10px] px-1 py-0.2 rounded font-sans font-bold">
                                    ملغي
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="px-4 py-3 font-mono font-bold text-sm">
                              <span className={isReversed ? 'line-through text-slate-400' : 'text-emerald-700'}>
                                {Number(p.amount_paid).toLocaleString('en-US')} ر.ي
                              </span>
                            </td>
                            <td className="px-4 py-3 font-medium text-slate-900">
                              {p.accountant_name || 'أمين الصندوق'}
                            </td>
                            <td className="px-4 py-3 text-slate-600">
                              <span className="font-medium text-slate-700">{p.payment_method || 'CASH'}</span>
                              {p.notes && <span className="text-slate-400 mr-1.5 block sm:inline font-normal">({p.notes})</span>}
                            </td>
                            <td className="px-4 py-3 font-mono text-[11px] text-slate-500">
                              {p.payment_date ? new Date(p.payment_date).toLocaleString('en-US') : (p.created_at ? new Date(p.created_at).toLocaleString('en-US') : '-')}
                            </td>
                            <td className="px-4 py-3 text-center">
                              {isReversed ? (
                                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200">
                                  ملغي ومسترجع
                                </span>
                              ) : (
                                <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ${
                                  isApproved
                                    ? 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                                    : 'bg-amber-50 text-amber-800 border border-amber-200'
                                }`}>
                                  {isApproved ? 'معتمد' : 'معلق (بانتظار الاعتماد)'}
                                </span>
                              )}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

        </div>

        {/* Footer */}
        <div className="px-6 py-3.5 bg-slate-50 border-t border-slate-200 flex justify-between items-center text-xs text-slate-500">
          <div>
            نظام Smart Power ERP • سجل الحسابات المالي والفني الموحد
          </div>
          <button
            onClick={onClose}
            className="px-5 py-2 bg-slate-800 hover:bg-slate-900 text-white font-bold rounded-xl transition-all shadow-sm"
          >
            إغلاق النافذة
          </button>
        </div>

      </div>
    </div>
  );
};
