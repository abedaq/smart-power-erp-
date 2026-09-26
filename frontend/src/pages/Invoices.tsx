import React, { useState, useMemo, useEffect, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getInvoices, getInvoiceCycles, sendInvoiceWhatsApp, sendBulkInvoicesWhatsApp, sendDisconnectionWarning, generateNextCycleApi } from '../services/invoice.service';
import { getPayments, sendReceiptWhatsAppApi, reversePaymentApi } from '../services/payment.service';
import { getUniqueRoutes } from '../services/customer.service';
import { getSettings } from '../services/settings.service';
import api, { exportBillingCycle } from '../lib/api';
import { InvoicePreviewModal } from '../components/InvoicePreviewModal';
import { ReadingModal } from '../components/ReadingModal';
import { PaymentModal } from '../components/PaymentModal';
import { StatementModal } from '../components/StatementModal';
import { CyclePrintView } from '../components/CyclePrintView';
import { PaymentReceiptModal } from '../components/PaymentReceiptModal';
import { AddCustomerModal } from '../components/AddCustomerModal';
import { BulkWhatsAppModal } from '../components/BulkWhatsAppModal';
import { ExcelGrid } from '../components/common/ExcelGrid';
import {
  formatCycleName,
  type CycleOption,
  getUniqueCyclesFromInvoices,
  isHistoricalBillingCycle,
  isSameCycle,
  getLatestActiveCycle,
  getNextCycleLabel,
  normalizeMonth,
} from '../utils/cycleUtils';
import { getNormalizedArea } from '../utils/areaGrouping';
import {
  Landmark,
  Calendar,
  Search,
  Smartphone,
  RotateCcw,
  FileSpreadsheet,
  Printer,
  Receipt,
  Eye,
  DollarSign,
  Send,
  AlertTriangle,
  Lock,
  ChevronRight,
  ChevronLeft,
  UserPlus,
  Undo2,
  X,
} from 'lucide-react';
import toast from 'react-hot-toast';
import type { Invoice, Payment, Customer } from '../types';
import type { GridRowData, ComputedGridRow } from '../types/excelGrid.types';
import { useDebouncedRealtime } from '../utils/debouncedRealtime';
import { QUERY_KEYS, invalidateFinancialTree } from '../constants/queryKeys';

interface ExcelSheetTabsProps {
  cycles: Array<{ code: string; label: string; count: number }>;
  selectedCycle: string;
  onSelectCycle: (label: string) => void;
}

const ExcelSheetTabs: React.FC<ExcelSheetTabsProps> = ({
  cycles,
  selectedCycle,
  onSelectCycle,
}) => {
  const containerRef = React.useRef<HTMLDivElement>(null);
  const [isMouseDown, setIsMouseDown] = React.useState(false);
  const [startX, setStartX] = React.useState(0);
  const [scrollLeft, setScrollLeft] = React.useState(0);
  const [dragMoved, setDragMoved] = React.useState(false);

  const handleMouseDown = (e: React.MouseEvent) => {
    if (!containerRef.current) return;
    setIsMouseDown(true);
    setDragMoved(false);
    setStartX(e.pageX - containerRef.current.offsetLeft);
    setScrollLeft(containerRef.current.scrollLeft);
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!isMouseDown || !containerRef.current) return;
    e.preventDefault();
    const x = e.pageX - containerRef.current.offsetLeft;
    const walk = (x - startX) * 1.5;
    if (Math.abs(walk) > 4) {
      setDragMoved(true);
    }
    containerRef.current.scrollLeft = scrollLeft - walk;
  };

  const handleMouseUpOrLeave = () => {
    setIsMouseDown(false);
  };

  const scrollByAmount = (amount: number) => {
    if (containerRef.current) {
      containerRef.current.scrollBy({ left: amount, behavior: 'smooth' });
    }
  };

  return (
    <div dir="rtl" className="flex items-center gap-1 bg-white p-1 rounded-xl shadow-xs border border-slate-200/90 max-w-full overflow-hidden select-none grow flex-1 transition-all duration-300 ease-in-out">
      {/* Scroll Left Button */}
      <button
        type="button"
        onClick={() => scrollByAmount(-150)}
        className="p-1 hover:bg-slate-100 text-slate-500 hover:text-slate-900 rounded-lg transition-colors shrink-0 cursor-pointer"
        title="تمرير لليسار"
      >
        <ChevronRight className="w-3.5 h-3.5" />
      </button>

      {/* Draggable Tab Strip */}
      <div
        ref={containerRef}
        onMouseDown={handleMouseDown}
        onMouseMove={handleMouseMove}
        onMouseUp={handleMouseUpOrLeave}
        onMouseLeave={handleMouseUpOrLeave}
        dir="rtl"
        className={`flex items-center gap-1.5 overflow-x-auto select-none grow flex-1 [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none] transition-all duration-300 ease-in-out ${
          isMouseDown ? 'cursor-grabbing' : 'cursor-grab'
        }`}
      >
        {/* Dynamic Month Cycles (All, 15-day semi-monthly) */}
        {cycles.map((c) => {
          const isSelected = isSameCycle(selectedCycle, c.label);
          const isHist = isHistoricalBillingCycle(c.label, cycles);
          const displayLabel = c.label.startsWith('شهر') ? c.label : `شهر ${c.label}`;

          return (
            <button
              key={c.code}
              type="button"
              onClick={() => {
                if (!dragMoved) onSelectCycle(c.label);
              }}
              className={`px-3.5 py-1.5 rounded-lg text-xs font-bold whitespace-nowrap transition-all flex items-center justify-center gap-1.5 grow flex-1 min-w-[120px] border cursor-pointer ${
                isSelected
                  ? 'bg-emerald-600 text-white shadow-sm font-extrabold ring-1 ring-emerald-500 border-emerald-600'
                  : 'bg-slate-50 text-slate-700 hover:bg-slate-100 hover:text-slate-900 border-slate-200'
              }`}
            >
              {isHist ? (
                <Lock className="w-3 h-3 text-amber-500" />
              ) : (
                <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
              )}
              <span>{displayLabel}</span>
              <span
                className={`px-1.5 py-0.2 rounded text-[10px] font-mono font-bold ${
                  isSelected ? 'bg-emerald-800 text-emerald-100' : 'bg-slate-200 text-slate-700'
                }`}
              >
                {c.count.toLocaleString('en-US')}
              </span>
            </button>
          );
        })}
      </div>

      {/* Scroll Right Button */}
      <button
        type="button"
        onClick={() => scrollByAmount(150)}
        className="p-1 hover:bg-slate-100 text-slate-500 hover:text-slate-900 rounded-lg transition-colors shrink-0 cursor-pointer"
        title="تمرير لليمين"
      >
        <ChevronLeft className="w-3.5 h-3.5" />
      </button>
    </div>
  );
};

const Invoices: React.FC = () => {
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<'collections' | 'cycle' | 'cyclePrint'>('cycle');
  const [page, setPage] = useState(1);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRoute, setSelectedRoute] = useState('all');
  const [selectedStatus, setSelectedStatus] = useState('all');

  const hasUserSelectedCycleRef = useRef(false);
  const [selectedCycleLabel, setSelectedCycleLabel] = useState<string>('سبتمبر 1');
  const [isGeneratingNextCycle, setIsGeneratingNextCycle] = useState(false);

  const [showCyclePrintModal, setShowCyclePrintModal] = useState<boolean>(false);
  const [cyclePrintMode, setCyclePrintMode] = useState<'summary' | 'individual'>('summary');

  const [showPreviewModal, setShowPreviewModal] = useState(false);
  const [selectedInvoiceForPreview, setSelectedInvoiceForPreview] = useState<any>(null);

  const [showPaymentReceiptModal, setShowPaymentReceiptModal] = useState(false);
  const [selectedPaymentForReceipt, setSelectedPaymentForReceipt] = useState<Payment | null>(null);

  const [showReversePaymentModal, setShowReversePaymentModal] = useState(false);
  const [selectedPaymentForReverse, setSelectedPaymentForReverse] = useState<Payment | null>(null);
  const [reverseReason, setReverseReason] = useState('');

  const [showStatementModal, setShowStatementModal] = useState(false);
  const [showReadingModal, setShowReadingModal] = useState(false);
  const [showPaymentModal, setShowPaymentModal] = useState(false);
  const [selectedCustomerForAction, setSelectedCustomerForAction] = useState<Customer | null>(null);
  const [isAddCustomerOpen, setIsAddCustomerOpen] = useState(false);

  const [selectedRowIds, setSelectedRowIds] = useState<number[]>([]);
  const [showBulkWhatsAppModal, setShowBulkWhatsAppModal] = useState(false);
  const [isBulkSending, setIsBulkSending] = useState(false);
  const [bulkSentCount] = useState(0);

  const handleStartBulkSend = async () => {
    if (selectedRowIds.length === 0) return;
    setIsBulkSending(true);
    const toastId = toast.loading('جاري إدراج ' + selectedRowIds.length + ' فاتورة في طابور الواتساب...');
    try {
      const res = await sendBulkInvoicesWhatsApp(selectedRowIds);
      toast.success(res?.message || ('تم إدراج ' + selectedRowIds.length + ' فاتورة في طابور الواتساب بنجاح!'), { id: toastId, duration: 4000 });
      setSelectedRowIds([]);
      setShowBulkWhatsAppModal(false);
    } catch (error: any) {
      toast.error(error?.response?.data?.message || 'حدث خطأ أثناء إدراج الفواتير في الطابور', { id: toastId, duration: 5000 });
    } finally {
      setIsBulkSending(false);
    }
  };

  const [sentInvoiceIds, setSentInvoiceIds] = useState<Set<number>>(new Set());
  const [printedInvoiceIds, setPrintedInvoiceIds] = useState<Set<number>>(new Set());

  const { data: stationSettings } = useQuery({
    queryKey: ['settings'],
    queryFn: getSettings,
    staleTime: 5 * 60 * 1000,
  });

  const { data: routes = [] } = useQuery({
    queryKey: ['routes'],
    queryFn: getUniqueRoutes,
    staleTime: 5 * 60 * 1000,
  });

  // Strict 2-second debounced realtime subscription
  const realtimeConfigs = useMemo(
    () => [
      {
        channelName: 'invoices_page:invoices',
        table: 'invoices',
        queryKeysToInvalidate: [['invoices']],
        debounceMs: 2000,
      },
      {
        channelName: 'invoices_page:payments',
        table: 'payments',
        queryKeysToInvalidate: [['payments'], ['invoices']],
        debounceMs: 2000,
      },
    ],
    []
  );

  useDebouncedRealtime(realtimeConfigs);

  const { data: invoicesData, isLoading: isLoadingInvoices } = useQuery({
    queryKey: ['invoices', page, selectedRoute, selectedCycleLabel],
    queryFn: () => getInvoices(page, 1000, selectedRoute, 'all', selectedCycleLabel),
    staleTime: 0,
    refetchOnWindowFocus: true,
    placeholderData: (prev: any) => prev,
  });

  const { data: payments = [], isLoading: isLoadingPayments } = useQuery({
    queryKey: ['payments'],
    queryFn: getPayments,
    staleTime: 0,
    refetchOnWindowFocus: true,
    placeholderData: (prev: any) => prev,
  });

    const { data: fetchedCycles } = useQuery({
      queryKey: ['all-invoices-cycles'],
      queryFn: getInvoiceCycles,
      staleTime: 60 * 1000,
      refetchOnWindowFocus: true,
    });

    const rawInvoices: Invoice[] = useMemo(() => invoicesData?.data || [], [invoicesData?.data]);

    // Unique 15-day cycle options (Sorted newest-first so in RTL layout the latest cycle is on the right)
    const uniqueCycles: CycleOption[] = useMemo(() => {
      let list: CycleOption[] = [];
      if (Array.isArray(fetchedCycles) && fetchedCycles.length > 0) {
        const standardMonths = [
          'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
          'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
        ];
        list = fetchedCycles.map((c: any) => {
          const label = typeof c === 'string' ? c : c.label || c.code;
          let monthIndex = 1;
          let cycleNum = 1;
          let year = 2026;
          const match = label.match(/^([\u0600-\u06FF]+)\s+([12])(?:\s*-\s*(\d{4}))?/);
          if (match) {
            const mName = normalizeMonth(match[1]);
            const found = standardMonths.find(m => normalizeMonth(m) === mName);
            if (found) monthIndex = standardMonths.indexOf(found) + 1;
            cycleNum = parseInt(match[2], 10);
            if (match[3]) year = parseInt(match[3], 10);
          }
          return {
            code: label,
            label,
            count: typeof c === 'object' && typeof c.count === 'number' ? c.count : 0,
            year,
            monthIndex,
            cycleNum,
          };
        });
      } else {
        list = getUniqueCyclesFromInvoices(rawInvoices);
      }

      const currentYear = new Date().getFullYear();
      // Exclude empty future test cycles (e.g. 2027 with 0 invoices)
      const validCycles = list.filter(c => (c.year || 2026) <= currentYear || c.count > 0);
      const pool = validCycles.length > 0 ? validCycles : list;

      // Sort newest-first (sortB - sortA) so in RTL flexbox the newest cycle renders at the right-most tab
      return pool.sort((a, b) => {
        const sortA = ((a.year || 2026) * 24) + (((a.monthIndex || 1) - 1) * 2) + (a.cycleNum || 1);
        const sortB = ((b.year || 2026) * 24) + (((b.monthIndex || 1) - 1) * 2) + (b.cycleNum || 1);
        return sortB - sortA;
      });
    }, [fetchedCycles, rawInvoices]);

  // Auto-select latest active cycle on initial load
  useEffect(() => {
    if (!hasUserSelectedCycleRef.current && uniqueCycles.length > 0) {
      const latest = getLatestActiveCycle(uniqueCycles);
      if (latest && latest !== selectedCycleLabel) {
        setSelectedCycleLabel(latest);
      }
    }
  }, [uniqueCycles]);

  const latestActiveCycleLabel = useMemo(() => getLatestActiveCycle(uniqueCycles), [uniqueCycles]);
  const nextCycleCandidate = useMemo(() => getNextCycleLabel(latestActiveCycleLabel), [latestActiveCycleLabel]);

  const handleGenerateNextCycle = async () => {
    const targetBase = latestActiveCycleLabel || selectedCycleLabel;
    const confirm = window.confirm(
      `هل أنت متأكد من ترحيل القراءات والمتأخرات وتوليد كشف الدورة التالية (${nextCycleCandidate}) من دورة (${targetBase}) لجميع المشتركين؟`
    );
    if (!confirm) return;

    setIsGeneratingNextCycle(true);
    const loadingToast = toast.loading(`جاري توليد كشف دورة [${nextCycleCandidate}]...`);
    try {
      const res = await generateNextCycleApi(targetBase);
      toast.dismiss(loadingToast);
      if (res?.success) {
        toast.success(res.message || `تم توليد كشف دورة [${res.next_cycle}] بنجاح!`, { duration: 5000 });
        await queryClient.invalidateQueries({ queryKey: ['invoices'] });
        await queryClient.invalidateQueries({ queryKey: ['all-invoices-cycles'] });
        await queryClient.invalidateQueries({ queryKey: ['routes'] });
        hasUserSelectedCycleRef.current = true;
        if (res.next_cycle) {
          setSelectedCycleLabel(res.next_cycle);
        }
      } else {
        toast.error(res?.message || 'فشل توليد كشف الدورة التالية');
      }
    } catch (err: any) {
      toast.dismiss(loadingToast);
      toast.error(err?.response?.data?.message || err.message || 'حدث خطأ أثناء توليد الدورة التالية');
    } finally {
      setIsGeneratingNextCycle(false);
    }
  };

  const selectedCycleInvoices = useMemo(() => {
    const list = rawInvoices.filter((inv: Invoice) => {
      if (selectedCycleLabel === 'all') return true;
      return isSameCycle(inv.billing_cycle || inv.created_at, selectedCycleLabel);
    });

    // Deduplicate by customer_id: ensure each customer has exactly 1 invoice row per cycle
    const custMap = new Map<number, Invoice>();
    list.forEach((inv) => {
      const custId = Number(inv.customer_id || inv.customer?.id || inv.id);
      if (!custMap.has(custId)) {
        custMap.set(custId, inv);
      } else {
        const existing = custMap.get(custId)!;
        const existingPaid = Number(existing.paid_amount || 0);
        const currentPaid = Number(inv.paid_amount || 0);
        const existingReading = Number(existing.current_reading || 0);
        const currentReading = Number(inv.current_reading || 0);

        if (currentPaid > existingPaid || (currentPaid === existingPaid && currentReading > existingReading)) {
          custMap.set(custId, inv);
        }
      }
    });

    return Array.from(custMap.values());
  }, [rawInvoices, selectedCycleLabel]);

  const handleSelectCycle = (cycle: string) => {
    hasUserSelectedCycleRef.current = true;
    setSelectedCycleLabel(cycle);
    setSelectedStatus('all');
    setSelectedRoute('all');
    setSearchQuery('');
    setPage(1);
  };

  // Filter Cycle Invoices for Grid
  const filteredInvoices = useMemo(() => {
    return selectedCycleInvoices.filter((inv: Invoice) => {
      const matchesStatus = selectedStatus === 'all' || inv.status === selectedStatus;
      const matchesRoute =
        selectedRoute === 'all' || inv.customer?.route_number === selectedRoute;

      return matchesStatus && matchesRoute;
    });
  }, [selectedCycleInvoices, selectedStatus, selectedRoute]);

  // Map Invoices to GridRowData
  const invoiceGridRows: GridRowData[] = useMemo(() => {
    const sorted = [...filteredInvoices].sort((a, b) => {
      const orderA = a.customer?.sort_order ?? 999999;
      const orderB = b.customer?.sort_order ?? 999999;
      if (orderA !== orderB) return orderA - orderB;
      return (a.customer?.id || 0) - (b.customer?.id || 0);
    });
    return sorted.map((inv: Invoice) => {
      const planPrice = Number(
        inv.kwh_price_snapshot || inv.customer?.subscription_plan?.kwh_price || 1400
      );
      const planFee = Number(
        inv.fixed_fee_snapshot || inv.customer?.subscription_plan?.fixed_fee || 1000
      );
      const prevReading = Number(inv.previous_reading || 0);
      const currReading = Number(inv.current_reading || 0);
      const arrears = Number(inv.arrears || 0);
      const paidAmount = Number(inv.paid_amount || 0);

      return {
        id: inv.id,
        subNumber: inv.customer?.subscriber_number || String(inv.customer_id),
        route: inv.customer?.route_number || '',
        name: inv.customer?.full_name || 'مشترك',
        address: inv.customer?.address || '',
        meterNumber: inv.customer?.meter_number || '',
        phone: inv.customer?.phone_number || '',
        prevReading,
        currReading,
        unitPrice: planPrice,
        serviceFee: planFee,
        arrears,
        paidAmount,
        sent: Boolean((inv as any).whatsapp_sent_at || (inv as any).sent_at || (inv as any).sent || (inv.approval_status as string) === 'SENT' || sentInvoiceIds.has(inv.id)),
        isPrinted: Boolean((inv as any).is_printed || (inv as any).printed_at || (inv as any).printed || printedInvoiceIds.has(inv.id)),
        approvalStatus: inv.approval_status || 'PENDING',
        status: inv.status,
        rawItem: inv,
      };
    });
  }, [filteredInvoices, sentInvoiceIds, printedInvoiceIds]);

  // Filter Payments (Recent Collections)
  const filteredPayments = useMemo(() => {
    return (payments as Payment[]).filter((p: Payment) => {
      const matchesSearch =
        !searchQuery ||
        (p.customer?.full_name && p.customer.full_name.includes(searchQuery)) ||
        (p.customer?.subscriber_number && p.customer.subscriber_number.includes(searchQuery)) ||
        (p.receipt_number && p.receipt_number.includes(searchQuery));

      return matchesSearch;
    });
  }, [payments, searchQuery]);

  const sendInvoiceWhatsAppMutation = useMutation({
    mutationFn: sendInvoiceWhatsApp,
    onSuccess: (_, invoiceId) => {
      setSentInvoiceIds((prev) => new Set(prev).add(invoiceId));
      toast.success('تم إضافة الفاتورة إلى طابور رسائل الواتساب بنجاح!');
    },
    onError: (error: any) => {
      toast.error(`فشل الإرسال: ${error.response?.data?.message || error.message}`);
    },
  });

  const handleSendWarning = async (customer: Customer, amount: number) => {
    const rawPhone = customer.phone_number || '';
    const phone = rawPhone.replace(/[^0-9]/g, '');
    if (!phone || phone.length < 9) {
      toast.error('رقم هاتف المشترك غير صحيح أو غير متوفر');
      return;
    }

    const loadToast = toast.loading(`جاري إرسال إشعار الإنذار إلى المشترك: ${customer.full_name}...`);
    try {
      const res = await sendDisconnectionWarning(customer.id, amount);
      toast.success(res?.message || `تم إرسال إشعار الإنذار بنجاح إلى: ${customer.full_name}`, { id: loadToast });
    } catch (err: any) {
      const errorMsg = err.response?.data?.message || err.message || 'خدمة الواتساب غير متصلة بالهاتف حالياً. يرجى ربط الهاتف أولاً من صفحة الإعدادات.';
      toast.error(errorMsg, { id: loadToast, duration: 5000 });
    }
  };

  const sendReceiptWhatsAppMutation = useMutation({
    mutationFn: sendReceiptWhatsAppApi,
    onSuccess: () => {
      toast.success('تم إضافة سند القبض إلى طابور الواتساب بنجاح!');
    },
    onError: (error: any) => {
      toast.error(`فشل الإرسال: ${error.response?.data?.message || error.message}`);
    },
  });

  const reversePaymentMutation = useMutation({
    mutationFn: ({ paymentId, reason }: { paymentId: number; reason: string }) =>
      reversePaymentApi(paymentId, reason),
    onSuccess: () => {
      toast.success('تم إلغاء وعكس سند القبض وإعادة ضبط الحساب بنجاح!');
      setShowReversePaymentModal(false);
      setSelectedPaymentForReverse(null);
      setReverseReason('');
      invalidateFinancialTree(queryClient);
    },
    onError: (error: any) => {
      toast.error(`فشل إلغاء السند: ${error.response?.data?.message || error.message}`);
    },
  });

  const handleResetFilters = () => {
    setSearchQuery('');
    setSelectedRoute('all');
    setSelectedStatus('all');
    setPage(1);
  };

  // In-cell save handler for invoice grid with retroactive cascade
  const handleInvoiceCellSave = async (
    id: number,
    field: keyof GridRowData,
    value: any,
    updatedRow: ComputedGridRow
  ) => {
    try {
      const invoice = (updatedRow.rawItem as Invoice) || rawInvoices.find((i) => i.id === id);
      const targetId = invoice?.id || id;

      const cellPayload: any = {
        entity_type: 'INVOICE',
        customer_id: invoice?.customer_id
      };
      if (field === 'currReading') cellPayload.current_reading = Number(value || 0);
      else if (field === 'prevReading') cellPayload.previous_reading = Number(value || 0);
      else if (field === 'unitPrice') cellPayload.unit_price = Number(value || 0);
      else if (field === 'serviceFee') cellPayload.service_fee = Number(value || 0);
      else if (field === 'arrears') cellPayload.arrears = Number(value || 0);
      else if (field === 'paidAmount') cellPayload.paid_amount = Number(value || 0);
      else if (field === 'subNumber') cellPayload.subscriber_number = String(value).trim();
      else if (field === 'name') cellPayload.full_name = String(value).trim();
      else if (field === 'address') cellPayload.address = String(value).trim();
      else if (field === 'meterNumber') cellPayload.meter_number = String(value).trim();
      else if (field === 'phone') cellPayload.phone_number = String(value).trim();
      else if (field === 'route') cellPayload.route_number = String(value).trim();

      await api.put(`/readings/${targetId}/cell-update`, cellPayload);
      invalidateFinancialTree(queryClient);

      toast.success(
        `تم حفظ التعديل وإعادة الحساب التتابعي للسلسلة بنجاح — إجمالي المستحق: ${updatedRow.totalDue.toLocaleString('en-US')} ر.ي`
      );
    } catch (err: any) {
      toast.error(`فشل حفظ التعديل: ${err.response?.data?.message || err.message}`);
    }
  };

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 border-b border-slate-200 pb-4">
        <div>
          <h1 className="text-xl sm:text-2xl font-bold flex items-center gap-2 text-slate-900">
            <Landmark className="text-emerald-600" size={24} />
            مركز التحصيل والفوترة (Cashier Operations)
          </h1>
          <p className="text-slate-500 text-xs sm:text-sm mt-0.5 font-medium">
            لوحة تحكم الكاشير، كشف الفواتير التفاعلي بنمط Excel، سندات القبض، ودورات التحصيل.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsAddCustomerOpen(true)}
            className="h-9 sm:h-10 bg-blue-600 hover:bg-blue-700 text-white px-3.5 sm:px-4 rounded-xl font-bold transition-all text-xs flex items-center gap-1.5 shadow-md shadow-blue-500/20 cursor-pointer"
          >
            <UserPlus size={16} />
            إضافة مشترك جديد
          </button>

          <button
            onClick={async () => {
              try {
                const cycleLabel = selectedCycleLabel === 'all' ? 'كافة الدورات' : selectedCycleLabel;
                toast.loading(`جاري تصدير كشف دورة [${cycleLabel}]...`, { id: 'export-cycle' });
                await exportBillingCycle(selectedCycleLabel);
                toast.success(`تم تصدير كشف دورة [${cycleLabel}] بنجاح!`, { id: 'export-cycle' });
              } catch (err: any) {
                toast.error('تعذر تصدير كشف الدورة، يرجى المحاولة لاحقاً', { id: 'export-cycle' });
              }
            }}
            className="h-9 sm:h-10 bg-emerald-50 hover:bg-emerald-100 text-emerald-700 border border-emerald-200 px-3 sm:px-4 rounded-xl font-bold transition-all text-xs flex items-center gap-1.5 shadow-sm cursor-pointer"
          >
            <FileSpreadsheet size={15} />
            تصدير كشف الدورة
          </button>
        </div>
      </div>

      {/* Cashier Operation Mode Tabs */}
      <div className="flex border-b border-slate-200 gap-3 overflow-x-auto">
        <button
          onClick={() => setActiveTab('cycle')}
          className={`flex items-center gap-2 px-5 py-2.5 font-bold text-xs rounded-t-xl transition-all border-b-2 whitespace-nowrap ${
            activeTab === 'cycle'
              ? 'bg-white text-blue-700 border-blue-600 shadow-sm font-extrabold'
              : 'text-slate-500 border-transparent hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <Calendar size={16} />
          كشف الفواتير التفاعلي ({invoiceGridRows.length.toLocaleString('en-US')})
        </button>

        <button
          onClick={() => setActiveTab('collections')}
          className={`flex items-center gap-2 px-5 py-2.5 font-bold text-xs rounded-t-xl transition-all border-b-2 whitespace-nowrap ${
            activeTab === 'collections'
              ? 'bg-white text-emerald-700 border-emerald-600 shadow-sm font-extrabold'
              : 'text-slate-500 border-transparent hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <Receipt size={16} />
          سجل التحصيل والسندات ({filteredPayments.length.toLocaleString('en-US')})
        </button>

        <button
          onClick={() => setActiveTab('cyclePrint')}
          className={`flex items-center gap-2 px-5 py-2.5 font-bold text-xs rounded-t-xl transition-all border-b-2 whitespace-nowrap ${
            activeTab === 'cyclePrint'
              ? 'bg-white text-purple-700 border-purple-600 shadow-sm font-extrabold'
              : 'text-slate-500 border-transparent hover:text-slate-900 hover:bg-slate-100'
          }`}
        >
          <Printer size={16} />
          طباعة وتصدير دورات (15 يوماً)
        </button>
      </div>

      {/* TAB A: Interactive Excel Grid for Billing Cycle Invoices */}
      {activeTab === 'cycle' && (
        <ExcelGrid
          title="كشف فواتير الطاقة والتحصيل الميداني"
          subtitle="تعديل مباشر على القراءات، المتأخرات، والسدادات مع احتساب فوري وإرسال معتمد عبر الواتساب"
          period={selectedCycleLabel === 'all' ? 'اغسطس - 2026' : selectedCycleLabel}
          onPeriodChange={(p) => setSelectedCycleLabel(p)}
          rows={invoiceGridRows}
          isLoading={isLoadingInvoices}
          isHistorical={isHistoricalBillingCycle(selectedCycleLabel)}
          onCellSave={handleInvoiceCellSave}
          onApproveAndSend={(row) => sendInvoiceWhatsAppMutation.mutate(row.id)}
          hideDeleteColumn={true}
          hidePreviewColumn={true}
          hideActionsColumn={false}
          actionColumnPosition="none"
          exportFilenamePrefix="كشف_فواتير_الدورة"
          enableRowSelection={true}
          selectedRowIds={selectedRowIds}
          onSelectionChange={setSelectedRowIds}
          extraFilterControls={
            <div className="flex items-center gap-2 max-w-full overflow-x-auto select-none">
              {/* Draggable Modern Excel Sheet Tabs */}
              <ExcelSheetTabs
                cycles={uniqueCycles}
                selectedCycle={selectedCycleLabel}
                onSelectCycle={handleSelectCycle}
              />

              {/* Bulk WhatsApp Button */}
              {selectedRowIds.length > 0 && (
                <button
                  type="button"
                  onClick={() => setShowBulkWhatsAppModal(true)}
                  className="flex items-center gap-1.5 bg-purple-600 hover:bg-purple-700 text-white px-3 py-1.5 rounded-lg text-xs font-bold shadow-xs transition-all shrink-0 cursor-pointer"
                >
                  <Send className="w-3.5 h-3.5" />
                  إرسال محدد ({selectedRowIds.length})
                </button>
              )}

              {/* Fixed Always-Visible Generate Next Cycle Button */}
              <button
                type="button"
                onClick={handleGenerateNextCycle}
                disabled={isGeneratingNextCycle}
                className="flex items-center gap-1.5 bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700 text-white px-3 py-1.5 rounded-lg text-xs font-bold shadow-xs transition-all shrink-0 cursor-pointer disabled:opacity-50"
                title={`توليد وترحيل كشف الدورة التالية (${nextCycleCandidate}) من دورة (${latestActiveCycleLabel})`}
              >
                <Calendar className="w-3.5 h-3.5" />
                {isGeneratingNextCycle ? 'جاري التوليد...' : `➕ توليد كشف ${nextCycleCandidate}`}
              </button>

              {/* Route Filter Dropdown */}
              <select
                value={selectedRoute}
                onChange={(e) => {
                  setSelectedRoute(e.target.value);
                  setPage(1);
                }}
                className="bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-1.5 text-slate-800 text-xs focus:outline-none focus:border-blue-600 font-medium shrink-0 shadow-xs"
              >
                <option value="all">كل خطوط السير</option>
                {routes.map((r: string) => (
                  <option key={r} value={r}>
                    خط {r}
                  </option>
                ))}
              </select>

              {/* Status Filter Dropdown */}
              <select
                value={selectedStatus}
                onChange={(e) => setSelectedStatus(e.target.value)}
                className="bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-1.5 text-slate-800 text-xs focus:outline-none focus:border-blue-600 font-medium shrink-0 shadow-xs"
              >
                <option value="all">كل الحالات</option>
                <option value="Unpaid">غير مسددة</option>
                <option value="Partially_Paid">مسددة جزئياً</option>
                <option value="Paid">مسددة بالكامل</option>
              </select>
            </div>
          }
          extraRowActions={(row) => {
            const invoice = row.rawItem as Invoice;
            const rawCustomer = invoice?.customer as Customer | undefined;
            const customer: Customer | null = rawCustomer ? ({
              ...rawCustomer,
              units: row.units ?? invoice.consumption,
              consumption: row.units ?? invoice.consumption,
              currReading: row.currReading ?? invoice.current_reading,
              prevReading: row.prevReading ?? invoice.previous_reading,
              total_due: row.totalDue ?? invoice.total_due,
              totalDue: row.totalDue ?? invoice.total_due,
              paid_amount: row.paidAmount ?? invoice.paid_amount ?? 0,
              paidAmount: row.paidAmount ?? invoice.paid_amount ?? 0,
              remaining: row.remaining ?? invoice.remaining_amount ?? 0,
              remaining_amount: row.remaining ?? invoice.remaining_amount ?? 0,
              arrears: row.arrears ?? invoice.arrears ?? rawCustomer.arrears ?? 0,
              invoice_id: invoice?.id,
            } as any) : null;

            const dueAmount = Number(row.remaining !== undefined && row.remaining !== null ? row.remaining : (row.totalDue || invoice?.total_due || 0));

            return (
              <div className="flex items-center justify-center gap-1.5 whitespace-nowrap">
                {/* 1. زر السداد المالي (أخضر بارز) */}
                {customer && (
                  <button
                    onClick={() => {
                      setSelectedCustomerForAction(customer);
                      setShowPaymentModal(true);
                    }}
                    className="inline-flex items-center justify-center gap-1 py-1 px-2.5 rounded-lg text-xs font-bold transition-all shadow-xs bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer active:scale-95"
                    title="سداد مالي وتسجيل دفعة"
                  >
                    <DollarSign className="w-3.5 h-3.5" />
                    <span>سداد</span>
                  </button>
                )}

                {/* 2. أيقونة إرسال الفاتورة عبر الواتساب (أزرق) */}
                {invoice && (
                  <button
                    onClick={() => sendInvoiceWhatsAppMutation.mutate(invoice.id)}
                    disabled={sendInvoiceWhatsAppMutation.isPending}
                    className="p-1.5 text-blue-600 hover:bg-blue-50 border border-blue-200 rounded-lg transition-all cursor-pointer active:scale-95"
                    title="إرسال الفاتورة الرسمية عبر الواتساب"
                  >
                    <Send className="w-3.5 h-3.5" />
                  </button>
                )}

                {/* 3. أيقونة إرسال التحذير (مثلث أصفر / عنبري) */}
                {customer && (
                  <button
                    onClick={() => handleSendWarning(customer, dueAmount)}
                    className="p-1.5 text-amber-600 hover:bg-amber-50 border border-amber-200 rounded-lg transition-all cursor-pointer active:scale-95"
                    title="إرسال إشعار إنذار فصل التيار عبر الواتساب"
                  >
                    <AlertTriangle className="w-3.5 h-3.5 text-amber-500" />
                  </button>
                )}

                {/* 4. أيقونة معاينة الفاتورة والطباعة (رمادي / أزرق) */}
                {invoice && (
                  <button
                    onClick={() => {
                      setSelectedInvoiceForPreview(invoice);
                      setPrintedInvoiceIds((prev) => new Set(prev).add(invoice.id));
                      setShowPreviewModal(true);
                    }}
                    className="p-1.5 text-slate-600 hover:bg-slate-100 border border-slate-200 rounded-lg transition-all cursor-pointer active:scale-95"
                    title="معاينة نموذج الفاتورة المطبوع"
                  >
                    <Eye className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            );
          }}
        />
      )}

      {/* TAB B: Recent Collections / Paid Receipts */}
      {activeTab === 'collections' && (
        <div className="space-y-4">
          <div className="bg-white border border-slate-200 rounded-2xl p-2.5 shadow-sm flex flex-col md:flex-row gap-2 items-center justify-between">
            <div className="relative flex-1 w-full">
              <input
                type="text"
                placeholder="بحث برقم السند، اسم المشترك، الرقم..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-xl pr-10 pl-4 py-2.5 text-slate-900 text-xs placeholder-slate-400 focus:outline-none focus:border-blue-600 font-medium"
              />
              <Search className="absolute right-3 top-3 text-slate-400" size={16} />
            </div>

            {searchQuery && (
              <button
                onClick={handleResetFilters}
                className="bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 p-2.5 rounded-xl text-xs transition-colors"
                title="إعادة ضبط الفلاتر"
              >
                <RotateCcw size={16} />
              </button>
            )}
          </div>

          <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden shadow-sm">
            <div className="overflow-x-auto">
              <table className="w-full text-right border-collapse">
                <thead>
                  <tr className="bg-slate-50 border-b border-slate-200 text-slate-600 text-xs font-semibold uppercase">
                    <th className="px-5 py-3.5">سند القبض</th>
                    <th className="px-5 py-3.5">تاريخ ووقت التحصيل</th>
                    <th className="px-5 py-3.5">المشترك</th>
                    <th className="px-5 py-3.5">المنطقة</th>
                    <th className="px-5 py-3.5">المبلغ المدفوع</th>
                    <th className="px-5 py-3.5">طريقة الدفع</th>
                    <th className="px-5 py-3.5">المحصل / الكاشير</th>
                    <th className="px-5 py-3.5">الإجراءات</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 text-slate-800 text-sm">
                  {isLoadingPayments ? (
                    <tr>
                      <td colSpan={8} className="text-center py-12 text-slate-500 font-medium">
                        جاري تحميل سجل التحصيل...
                      </td>
                    </tr>
                  ) : filteredPayments.length === 0 ? (
                    <tr>
                      <td colSpan={8} className="text-center py-12 text-slate-500 font-medium">
                        لا توجد عمليات تحصيل مسجلة مطابقة للبحث.
                      </td>
                    </tr>
                  ) : (
                    filteredPayments.map((payment: Payment) => {
                      const isReversed = payment.approval_status === 'REVERSED';
                      return (
                        <tr key={payment.id} className={`hover:bg-slate-50/80 transition-colors ${isReversed ? 'bg-rose-50/30' : ''}`}>
                          <td className="px-5 py-3.5 font-mono text-xs font-bold text-emerald-700">
                            <div className="flex items-center gap-1.5">
                              <span>{payment.receipt_number || `REC-#${payment.id}`}</span>
                              {isReversed && (
                                <span className="bg-rose-100 text-rose-700 border border-rose-200 text-[10px] px-1.5 py-0.5 rounded font-bold font-sans">
                                  ملغي
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="px-5 py-3.5 text-slate-600 text-xs font-mono">
                            {payment.payment_date
                              ? new Date(payment.payment_date).toLocaleString('en-US')
                              : '-'}
                          </td>
                          <td className="px-5 py-3.5">
                            <div className="font-bold text-slate-900 text-sm">
                              {payment.customer?.full_name}
                            </div>
                            <div className="text-[11px] text-blue-600 font-mono font-bold">
                              #{payment.customer?.subscriber_number}
                            </div>
                          </td>
                          <td className="px-5 py-3.5 text-slate-700 text-xs font-medium">
                            <span className="bg-slate-100 px-2 py-0.5 rounded text-[11px] font-bold border border-slate-200">
                              {getNormalizedArea(payment.customer?.address)}
                            </span>
                          </td>
                          <td className="px-5 py-3.5 font-bold font-mono text-sm">
                            <span className={isReversed ? 'line-through text-slate-400' : 'text-emerald-700'}>
                              {Number(payment.amount_paid).toLocaleString('en-US')} ر.ي
                            </span>
                          </td>
                          <td className="px-5 py-3.5">
                            <span className="bg-slate-100 px-2.5 py-1 rounded-lg text-xs font-semibold text-slate-700 border border-slate-200">
                              {payment.payment_method === 'CASH' ? '💵 نقداً' : '🏦 تحويل'}
                            </span>
                          </td>
                          <td className="px-5 py-3.5 text-slate-700 text-xs font-medium">
                            {payment.accountant_name || 'أمين الصندوق'}
                          </td>
                          <td className="px-5 py-3.5">
                            <div className="flex items-center gap-1.5">
                              <button
                                onClick={() => {
                                  setSelectedPaymentForReceipt(payment);
                                  setShowPaymentReceiptModal(true);
                                }}
                                className="bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 text-xs px-2.5 py-1.5 rounded-xl font-bold transition-all inline-flex items-center gap-1 cursor-pointer"
                                title="طباعة سند القبض المالي"
                              >
                                <Printer size={13} />
                                طباعة
                              </button>
                              <button
                                onClick={() => sendReceiptWhatsAppMutation.mutate(payment.id)}
                                disabled={sendReceiptWhatsAppMutation.isPending || isReversed}
                                className="bg-emerald-50 text-emerald-700 border border-emerald-200 hover:bg-emerald-600 hover:text-white text-xs px-2.5 py-1.5 rounded-xl font-bold transition-all inline-flex items-center gap-1 disabled:opacity-50 cursor-pointer"
                                title="إعادة إرسال السند عبر الواتساب"
                              >
                                <Smartphone size={13} />
                                واتساب
                              </button>
                              {!isReversed ? (
                                <button
                                  onClick={() => {
                                    setSelectedPaymentForReverse(payment);
                                    setReverseReason('سداد بالخطأ');
                                    setShowReversePaymentModal(true);
                                  }}
                                  className="bg-rose-50 text-rose-700 border border-rose-200 hover:bg-rose-600 hover:text-white text-xs px-2.5 py-1.5 rounded-xl font-bold transition-all inline-flex items-center gap-1 cursor-pointer shadow-2xs"
                                  title="إلغاء سند القبض وعكس العملية"
                                >
                                  <Undo2 size={13} />
                                  إلغاء
                                </button>
                              ) : (
                                <span className="text-[11px] text-slate-400 italic px-2">
                                  تم العكس
                                </span>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* TAB C: Cycle Print & Export View (15-Day Billing Cycles) */}
      {activeTab === 'cyclePrint' && (
        <div className="space-y-4">
          <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-sm space-y-4">
            <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 border-b border-slate-100 pb-4">
              <div>
                <h3 className="text-lg font-bold text-slate-900 flex items-center gap-2">
                  <Printer className="text-purple-600" size={20} />
                  <span>مركز طباعة وتصدير دورات التحصيل (15 يوماً)</span>
                </h3>
                <p className="text-xs text-slate-500 font-medium mt-1">
                  اختر الدورة النصف شهرية لاستعراض الكشف التجميعي الشامل، وطباعة السجلات المجمعة
                  كـ PDF أو فواتير المشتركين المفردة.
                </p>
              </div>

              {/* Action Buttons */}
              <div className="flex flex-wrap items-center gap-2.5">
                <button
                  type="button"
                  onClick={() => {
                    setCyclePrintMode('summary');
                    setShowCyclePrintModal(true);
                  }}
                  className="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2.5 rounded-xl font-bold text-xs shadow-md shadow-purple-600/20 transition-all flex items-center gap-1.5"
                >
                  <FileSpreadsheet size={16} />
                  <span>طباعة كشف تجميعي للدورة (PDF)</span>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setCyclePrintMode('individual');
                    setShowCyclePrintModal(true);
                  }}
                  className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-xl font-bold text-xs shadow-md shadow-blue-600/20 transition-all flex items-center gap-1.5"
                >
                  <Receipt size={16} />
                  <span>طباعة فواتير المشتركين المفردة</span>
                </button>
              </div>
            </div>

            {/* Cycle Preview Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div className="bg-purple-50/60 border border-purple-200 p-3.5 rounded-xl">
                <div className="text-slate-500 text-[11px] font-semibold">الدورة المحددة حالياً</div>
                <div className="text-base font-extrabold text-purple-900 mt-0.5">
                  {selectedCycleLabel === 'all' ? 'جميع الدورات' : selectedCycleLabel}
                </div>
              </div>

              <div className="bg-slate-50 border border-slate-200 p-3.5 rounded-xl">
                <div className="text-slate-500 text-[11px] font-semibold">
                  إجمالي عدد المشتركين بالدورة
                </div>
                <div className="text-base font-mono font-extrabold text-slate-900 mt-0.5">
                  {selectedCycleInvoices.length.toLocaleString('en-US')} مشتركون
                </div>
              </div>

              <div className="bg-emerald-50/60 border border-emerald-200 p-3.5 rounded-xl">
                <div className="text-slate-500 text-[11px] font-semibold">إجمالي المبالغ بالدورة</div>
                <div className="text-base font-mono font-extrabold text-emerald-800 mt-0.5">
                  {selectedCycleInvoices
                    .reduce((sum, inv) => sum + Number(inv.total_due || 0), 0)
                    .toLocaleString('en-US')}{' '}
                  ر.ي
                </div>
              </div>
            </div>

            {/* Table Preview */}
            <div className="overflow-x-auto border border-slate-200 rounded-xl">
              <table className="w-full text-right border-collapse text-xs">
                <thead>
                  <tr className="bg-slate-50 text-slate-700 font-bold border-b border-slate-200">
                    <th className="p-3">#</th>
                    <th className="p-3">اسم المشترك</th>
                    <th className="p-3">الدورة</th>
                    <th className="p-3">الاستهلاك</th>
                    <th className="p-3">المبلغ المستحق</th>
                    <th className="p-3">المسدد</th>
                    <th className="p-3">المتبقي</th>
                    <th className="p-3">الحالة</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 font-medium">
                  {selectedCycleInvoices.length === 0 ? (
                    <tr>
                      <td colSpan={8} className="text-center py-8 text-slate-500">
                        لا توجد فواتير مطابقة للدورة المحددة.
                      </td>
                    </tr>
                  ) : (
                    selectedCycleInvoices.map((inv, idx) => (
                      <tr key={inv.id} className="hover:bg-slate-50">
                        <td className="p-3 font-mono font-bold">{idx + 1}</td>
                        <td className="p-3 font-bold text-slate-900">
                          {inv.customer?.full_name || 'مشترك'}
                        </td>
                        <td className="p-3 font-bold text-purple-700">
                          {formatCycleName(inv.billing_cycle || inv.created_at)}
                        </td>
                        <td className="p-3 font-mono font-bold text-blue-600">
                          {Number(inv.consumption || 0).toLocaleString('en-US')} kWh
                        </td>
                        <td className="p-3 font-mono font-bold text-slate-900">
                          {Number(inv.total_due || 0).toLocaleString('en-US')} ر.ي
                        </td>
                        <td className="p-3 font-mono font-bold text-emerald-700">
                          {Number(inv.paid_amount || 0).toLocaleString('en-US')} ر.ي
                        </td>
                        <td className="p-3 font-mono font-bold text-rose-700">
                          {Number(inv.remaining_amount || 0).toLocaleString('en-US')} ر.ي
                        </td>
                        <td className="p-3 font-bold">
                          <span
                            className={`px-2 py-0.5 rounded-md text-[10px] ${
                              inv.status === 'Paid'
                                ? 'bg-emerald-100 text-emerald-800'
                                : inv.status === 'Partially_Paid'
                                ? 'bg-amber-100 text-amber-800'
                                : 'bg-rose-100 text-rose-800'
                            }`}
                          >
                            {inv.status === 'Paid'
                              ? 'مكتمل'
                              : inv.status === 'Partially_Paid'
                              ? 'جزئي'
                              : 'معلق'}
                          </span>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      <InvoicePreviewModal
        isOpen={showPreviewModal}
        onClose={() => setShowPreviewModal(false)}
        invoice={selectedInvoiceForPreview}
      />

      <CyclePrintView
        isOpen={showCyclePrintModal}
        onClose={() => setShowCyclePrintModal(false)}
        cycleName={selectedCycleLabel === 'all' ? 'جميع الدورات' : selectedCycleLabel}
        invoices={selectedCycleInvoices}
        mode={cyclePrintMode}
        stationSettings={stationSettings}
      />

      <PaymentReceiptModal
        isOpen={showPaymentReceiptModal}
        onClose={() => setShowPaymentReceiptModal(false)}
        payment={selectedPaymentForReceipt}
      />

      {/* Modal: Confirm Reverse Payment */}
      {showReversePaymentModal && selectedPaymentForReverse && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-fade-in">
          <div className="bg-white w-full max-w-md rounded-2xl shadow-2xl border border-slate-100 overflow-hidden flex flex-col animate-scale-up">
            {/* Header */}
            <div className="px-5 py-4 bg-rose-600 text-white flex justify-between items-center">
              <div className="flex items-center gap-2">
                <div className="p-2 bg-white/20 rounded-xl">
                  <Undo2 size={18} />
                </div>
                <div>
                  <h3 className="font-bold text-sm">تأكيد إلغاء وعكس سند القبض</h3>
                  <p className="text-[11px] text-rose-100">إرجاع المبالغ لذمة المشترك وإعادة الفواتير غير مسددة</p>
                </div>
              </div>
              <button
                onClick={() => {
                  setShowReversePaymentModal(false);
                  setSelectedPaymentForReverse(null);
                }}
                className="p-1 text-white/80 hover:text-white rounded-lg hover:bg-white/10 transition-colors"
              >
                <X size={18} />
              </button>
            </div>

            {/* Content */}
            <div className="p-5 space-y-4 text-xs">
              <div className="bg-rose-50 border border-rose-200 rounded-xl p-3.5 space-y-2 text-rose-900">
                <div className="flex justify-between items-center border-b border-rose-200/60 pb-2">
                  <span className="text-slate-600 font-medium">رقم السند:</span>
                  <span className="font-mono font-bold text-rose-700 text-sm">
                    {selectedPaymentForReverse.receipt_number || `REC-#${selectedPaymentForReverse.id}`}
                  </span>
                </div>
                <div className="flex justify-between items-center border-b border-rose-200/60 pb-2">
                  <span className="text-slate-600 font-medium">المشترك:</span>
                  <span className="font-bold text-slate-900 text-sm">
                    {selectedPaymentForReverse.customer?.full_name}
                  </span>
                </div>
                <div className="flex justify-between items-center border-b border-rose-200/60 pb-2">
                  <span className="text-slate-600 font-medium">المبلغ المسدد المُراد إلغاؤه:</span>
                  <span className="font-mono font-black text-rose-700 text-base">
                    {Number(selectedPaymentForReverse.amount_paid).toLocaleString('en-US')} ر.ي
                  </span>
                </div>
                <div className="flex justify-between items-center text-[11px]">
                  <span className="text-slate-500">المحصل:</span>
                  <span className="text-slate-700 font-medium">
                    {selectedPaymentForReverse.accountant_name || 'أمين الصندوق'}
                  </span>
                </div>
              </div>

              <div>
                <label className="block text-slate-700 font-bold mb-1.5">سبب الإلغاء (اختياري):</label>
                <input
                  type="text"
                  value={reverseReason}
                  onChange={(e) => setReverseReason(e.target.value)}
                  placeholder="مثال: سداد بالخطأ، تعديل حساب المشترك..."
                  className="w-full bg-slate-50 border border-slate-200 rounded-xl px-3.5 py-2.5 text-xs text-slate-900 focus:outline-none focus:border-rose-500 font-medium"
                />
              </div>

              <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 text-[11px] text-amber-800 flex items-start gap-2">
                <AlertTriangle size={16} className="text-amber-600 shrink-0 mt-0.5" />
                <span>
                  تنبيه: سيتم عكس أثر هذا السند مالياً فورياً، وخصم المبلغ من صندوق الوردية المفتوحة وإرجاع حالة الفواتير غير مسددة.
                </span>
              </div>
            </div>

            {/* Actions */}
            <div className="px-5 py-3.5 bg-slate-50 border-t border-slate-100 flex items-center justify-end gap-2">
              <button
                type="button"
                onClick={() => {
                  setShowReversePaymentModal(false);
                  setSelectedPaymentForReverse(null);
                }}
                disabled={reversePaymentMutation.isPending}
                className="px-4 py-2 text-xs font-bold text-slate-600 hover:bg-slate-200 rounded-xl transition-colors cursor-pointer"
              >
                تراجع
              </button>
              <button
                type="button"
                onClick={() => {
                  if (selectedPaymentForReverse) {
                    reversePaymentMutation.mutate({
                      paymentId: selectedPaymentForReverse.id,
                      reason: reverseReason,
                    });
                  }
                }}
                disabled={reversePaymentMutation.isPending}
                className="px-5 py-2 text-xs font-bold text-white bg-rose-600 hover:bg-rose-700 rounded-xl shadow-md hover:shadow-lg transition-all flex items-center gap-1.5 cursor-pointer disabled:opacity-50"
              >
                {reversePaymentMutation.isPending ? 'جاري الإلغاء...' : 'تأكيد الإلغاء وعكس العملية'}
              </button>
            </div>
          </div>
        </div>
      )}

      <StatementModal
        isOpen={showStatementModal}
        onClose={() => setShowStatementModal(false)}
        customer={selectedCustomerForAction}
      />

      <ReadingModal
        isOpen={showReadingModal}
        onClose={() => setShowReadingModal(false)}
        customer={selectedCustomerForAction}
      />

      <PaymentModal
        isOpen={showPaymentModal}
        onClose={() => setShowPaymentModal(false)}
        customer={selectedCustomerForAction}
      />

      <BulkWhatsAppModal
        isOpen={showBulkWhatsAppModal}
        onClose={() => setShowBulkWhatsAppModal(false)}
        selectedIds={selectedRowIds}
        onStartBulkSend={handleStartBulkSend}
        isSending={isBulkSending}
        sentCount={bulkSentCount}
      />
      <AddCustomerModal
        isOpen={isAddCustomerOpen}
        currentCycle={selectedCycleLabel}
        onClose={() => setIsAddCustomerOpen(false)}
        onCustomerAdded={async () => {
          setSelectedCycleLabel('all');
          setSelectedStatus('all');
          setSelectedRoute('all');
          setSearchQuery('');
          setPage(1);
          invalidateFinancialTree(queryClient);
          await queryClient.invalidateQueries({ queryKey: QUERY_KEYS.routes });
          await queryClient.refetchQueries({ queryKey: QUERY_KEYS.invoices.all });
        }}
      />
    </div>
  );
};

export default Invoices;
