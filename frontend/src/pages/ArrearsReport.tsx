import React, { useState, useMemo, useRef } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { getUniqueRoutes } from '../services/customer.service';
import {
  getInvoices,
  sendDisconnectionWarning,
  sendBulkDisconnectionWarnings,
} from '../services/invoice.service';
import { StatementModal } from '../components/StatementModal';
import { getNormalizedArea } from '../utils/areaGrouping';
import {
  formatCycleName,
  getUniqueCyclesFromInvoices,
  isHistoricalBillingCycle,
  isSameCycle,
} from '../utils/cycleUtils';
import { safeCopyToClipboard } from '../utils/formatters';
import { useDebouncedRealtime } from '../utils/debouncedRealtime';
import * as XLSX from 'xlsx';
import {
  ShieldAlert,
  AlertTriangle,
  AlertOctagon,
  Flame,
  FileSpreadsheet,
  Search,
  RotateCcw,
  Users,
  DollarSign,
  Clock,
  Send,
  X,
  Copy,
  Check,
  ChevronRight,
  ChevronLeft,
  Lock,
  FileText,
  CheckCircle2,
  Phone,
  Gauge,
  RefreshCw,
} from 'lucide-react';
import toast from 'react-hot-toast';
import type { Invoice, Customer } from '../types';

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
  const containerRef = useRef<HTMLDivElement>(null);
  const [isMouseDown, setIsMouseDown] = useState(false);
  const [startX, setStartX] = useState(0);
  const [scrollLeft, setScrollLeft] = useState(0);
  const [dragMoved, setDragMoved] = useState(false);

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
    <div className="flex items-center gap-1 bg-white p-1 rounded-xl shadow-xs border border-slate-200/90 max-w-full overflow-hidden select-none">
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
        className={`flex items-center gap-1.5 overflow-x-auto select-none [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none] ${
          isMouseDown ? 'cursor-grabbing' : 'cursor-grab'
        }`}
      >
        {/* Dynamic Month Cycles (15-day semi-monthly) */}
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
              className={`px-3 py-1.5 rounded-lg text-xs font-bold whitespace-nowrap transition-all flex items-center gap-1.5 shrink-0 border cursor-pointer ${
                isSelected
                  ? 'bg-rose-600 text-white shadow-sm font-extrabold ring-1 ring-rose-500 border-rose-600'
                  : 'bg-slate-50 text-slate-700 hover:bg-slate-100 hover:text-slate-900 border-slate-200'
              }`}
            >
              {isHist ? (
                <Lock className="w-3 h-3 text-amber-500" />
              ) : (
                <span className="w-2 h-2 rounded-full bg-rose-400 animate-pulse"></span>
              )}
              <span>{displayLabel}</span>
              <span
                className={`px-1.5 py-0.2 rounded text-[10px] font-mono font-bold ${
                  isSelected ? 'bg-rose-800 text-rose-100' : 'bg-slate-200 text-slate-700'
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

/**
 * Parses cycle string to obtain baseline reference date
 */
const getCycleBaselineDate = (cycleStr?: string): Date | null => {
  if (!cycleStr) return null;
  const match = cycleStr.match(/(يناير|فبراير|مارس|أبريل|ابريل|مايو|يونيو|يوليو|أغسطس|اغسطس|سبتمبر|أكتوبر|اكتوبر|نوفمبر|ديسمبر)[-\s]+([12])(?:[-\s]+(\d{4}))?/);
  if (!match) return null;
  const monthNames = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];
  let mName = match[1].replace('اغسطس', 'أغسطس').replace('ابريل', 'أبريل').replace('اكتوبر', 'أكتوبر');
  const mIdx = monthNames.indexOf(mName);
  if (mIdx === -1) return null;
  const cycleNum = parseInt(match[2], 10) || 1;
  const year = match[3] ? parseInt(match[3], 10) : 2026;
  const day = cycleNum === 1 ? 15 : 30;
  return new Date(year, mIdx, day);
};

/**
 * Calculates overdue days starting from the date the reading was entered in the cycle
 */
export const calculateOverdueDays = (inv: Invoice): number => {
  if (Number(inv.remaining_amount || 0) <= 0) return 0;

  let readingDate: Date | null = null;
  if (inv.meter_reading?.reading_date) {
    readingDate = new Date(inv.meter_reading.reading_date);
  } else if (inv.meter_reading?.created_at) {
    readingDate = new Date(inv.meter_reading.created_at);
  } else if (inv.created_at) {
    readingDate = new Date(inv.created_at);
  }

  const cycleDate = getCycleBaselineDate(inv.billing_cycle);
  if (cycleDate && (!readingDate || isNaN(readingDate.getTime()) || readingDate > new Date())) {
    readingDate = cycleDate;
  } else if (!readingDate || isNaN(readingDate.getTime())) {
    readingDate = cycleDate || new Date();
  }

  const now = new Date();
  const diffTime = now.getTime() - readingDate.getTime();
  const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));
  return Math.max(0, diffDays);
};

/**
 * Builds the official warning notice message formatted for Yemeni subscribers
 */
export function buildWarningNoticeText(inv: Invoice): string {
  const name = inv.customer?.full_name || '--';
  const subNum = inv.customer?.subscriber_number || '--';
  const meterNum = inv.customer?.meter_number || '--';
  const address = inv.customer?.address || '--';
  const cycle = inv.billing_cycle || formatCycleName(inv.created_at);
  const remainingNum = Number(inv.remaining_amount || 0).toLocaleString('en-US');
  const days = Math.max(0, calculateOverdueDays(inv)).toLocaleString('en-US');

  return `*إشعار إنذار رسمي بالسداد وفصل الخدمة*
*الدورة المحاسبية:* ${cycle}
*الحالة:* إنذار عاجل نهائي
----------------------------------------
*المشترك:* ${name}
*رقم الاشتراك:* ${subNum}
*رقم العداد:* ${meterNum}
*العنوان:* ${address}
----------------------------------------
*مدة التأخير من تاريخ القراءة:* ${days} يوماً
*إجمالي المديونية المتبقية:* ${remainingNum} ريال يمني
----------------------------------------
*تنبيه عاجل:* نرجو منكم سرعة مراجعة مركز التحصيل لتسديد المتأخرات المترتبة عليكم خلال 48 ساعة لتجنب فصل التيار الكهربائي عن العداد وتحمل رسوم إعادة الإطلاق وتطبيق الغرامات المقررة.
----------------------------------------
شاكرين حسن تعاونكم وحرصكم على استمرار الخدمة.`;
}

export const ArrearsReport: React.FC = () => {
  // Navigation & Cycle State
  const [selectedCycleLabel, setSelectedCycleLabel] = useState<string>('أغسطس 2');
  const [statusFilter, setStatusFilter] = useState<'all' | 'debtors_only' | 'critical' | 'warning' | 'paid'>('debtors_only');
  const [selectedRoute, setSelectedRoute] = useState<string>('all');
  const [selectedNormalizedRegion, setSelectedNormalizedRegion] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [sortBy, setSortBy] = useState<'arrears' | 'days' | 'route'>('arrears');

  // Modals State (Statement & Warning Notices only, no PaymentModal)
  const [selectedStatementCustomer, setSelectedStatementCustomer] = useState<Customer | null>(null);
  const [showStatementModal, setShowStatementModal] = useState<boolean>(false);
  const [selectedWarningInvoice, setSelectedWarningInvoice] = useState<Invoice | null>(null);
  const [copiedWarning, setCopiedWarning] = useState<boolean>(false);
  const [showBulkWarningModal, setShowBulkWarningModal] = useState<boolean>(false);

  // Realtime subscription (debounced 2s)
  const realtimeConfigs = useMemo(
    () => [
      {
        channelName: 'arrears_page:invoices',
        table: 'invoices',
        queryKeysToInvalidate: [['arrears-invoices'], ['invoices']],
        debounceMs: 2000,
      },
      {
        channelName: 'arrears_page:payments',
        table: 'payments',
        queryKeysToInvalidate: [['arrears-invoices'], ['payments'], ['invoices']],
        debounceMs: 2000,
      },
    ],
    []
  );
  useDebouncedRealtime(realtimeConfigs);

  // Queries
  const { data: routes = [] } = useQuery({
    queryKey: ['routes'],
    queryFn: getUniqueRoutes,
    staleTime: 5 * 60 * 1000,
  });

  const { data: allInvoicesData } = useQuery({
    queryKey: ['invoices-all-cycles-for-tabs'],
    queryFn: () => getInvoices(1, 1000, 'all', 'all', 'all'),
    staleTime: 60 * 1000,
  });

  const { data: invoicesData, isLoading: isLoadingInvoices, refetch: refetchInvoices } = useQuery({
    queryKey: ['arrears-invoices', selectedRoute, selectedCycleLabel],
    queryFn: () => getInvoices(1, 1000, selectedRoute, 'all', selectedCycleLabel),
    staleTime: 0,
    refetchOnWindowFocus: true,
  });

  // Extract all cycle tabs from data
  const rawAllInvoices: Invoice[] = useMemo(() => allInvoicesData?.data || [], [allInvoicesData?.data]);
  const uniqueCycles = useMemo(() => getUniqueCyclesFromInvoices(rawAllInvoices), [rawAllInvoices]);

  // Current Cycle Invoices with strict customer deduplication
  const cycleInvoices: Invoice[] = useMemo(() => {
    const raw = invoicesData?.data || [];
    const custMap = new Map<number, Invoice>();
    raw.forEach((inv: Invoice) => {
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
  }, [invoicesData?.data]);

  // Single Warning Notice Mutation
  const warningMutation = useMutation({
    mutationFn: ({ customerId, amount }: { customerId: number; amount: number }) =>
      sendDisconnectionWarning(customerId, amount),
    onSuccess: () => {
      toast.success('تم إدراج إنذار الفصل في طابور رسائل الواتساب بنجاح!');
      setSelectedWarningInvoice(null);
    },
    onError: (err: any) => {
      toast.error(`فشل إرسال الإنذار: ${err.response?.data?.message || err.message}`);
    },
  });

  // Bulk Warning Notice Mutation
  const bulkWarningMutation = useMutation({
    mutationFn: (items: Array<{ customer_id: number; amount: number }>) =>
      sendBulkDisconnectionWarnings(items),
    onSuccess: (res) => {
      toast.success(res?.message || 'تم إرسال الإنذارات الجماعية إلى طابور الواتساب بنجاح!');
      setShowBulkWarningModal(false);
    },
    onError: (err: any) => {
      toast.error(`فشل إرسال الإنذارات الجماعية: ${err.response?.data?.message || err.message}`);
    },
  });

  // Calculate region counts for Area Grouping Pills
  const regionCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    cycleInvoices.forEach((inv) => {
      const norm = getNormalizedArea(inv.customer?.address);
      counts[norm] = (counts[norm] || 0) + 1;
    });
    return Object.entries(counts).map(([area, count]) => ({ area, count }));
  }, [cycleInvoices]);

  // Filter invoices by search, area, and status
  const filteredInvoices: Invoice[] = useMemo(() => {
    return cycleInvoices.filter((inv) => {
      const query = searchQuery.trim().toLowerCase();
      const matchesSearch =
        !query ||
        (inv.customer?.full_name && inv.customer.full_name.toLowerCase().includes(query)) ||
        (inv.customer?.subscriber_number && inv.customer.subscriber_number.toLowerCase().includes(query)) ||
        (inv.customer?.meter_number && inv.customer.meter_number.toLowerCase().includes(query)) ||
        (inv.customer?.phone_number && inv.customer.phone_number.includes(query));

      const matchesRegion =
        selectedNormalizedRegion === 'all' ||
        getNormalizedArea(inv.customer?.address) === selectedNormalizedRegion;

      const overdueDays = calculateOverdueDays(inv);
      let matchesStatus = true;
      if (statusFilter === 'debtors_only') {
        matchesStatus = Number(inv.remaining_amount || 0) > 0;
      } else if (statusFilter === 'critical') {
        matchesStatus = Number(inv.remaining_amount || 0) > 0 && overdueDays > 60;
      } else if (statusFilter === 'warning') {
        matchesStatus = Number(inv.remaining_amount || 0) > 0 && overdueDays > 30 && overdueDays <= 60;
      } else if (statusFilter === 'paid') {
        matchesStatus = Number(inv.remaining_amount || 0) <= 0;
      }

      return matchesSearch && matchesRegion && matchesStatus;
    });
  }, [cycleInvoices, searchQuery, selectedNormalizedRegion, statusFilter]);

  // Sorting
  const sortedInvoices: Invoice[] = useMemo(() => {
    const list = [...filteredInvoices];
    if (sortBy === 'arrears') {
      list.sort((a, b) => Number(b.remaining_amount || 0) - Number(a.remaining_amount || 0));
    } else if (sortBy === 'days') {
      list.sort((a, b) => calculateOverdueDays(b) - calculateOverdueDays(a));
    } else {
      list.sort((a, b) => {
        const routeA = String(a.customer?.route_number || '');
        const routeB = String(b.customer?.route_number || '');
        if (routeA !== routeB) return routeA.localeCompare(routeB, 'ar-EG');
        return String(a.customer?.subscriber_number || '').localeCompare(String(b.customer?.subscriber_number || ''));
      });
    }
    return list;
  }, [filteredInvoices, sortBy]);

  // Financial KPI Metrics (Strict English Numerals)
  const totalDebt = useMemo(() => {
    return cycleInvoices.reduce((sum, inv) => {
      const rem = Number(inv.remaining_amount || 0);
      return rem > 0 ? sum + rem : sum;
    }, 0);
  }, [cycleInvoices]);

  const debtorsCount = useMemo(() => {
    return cycleInvoices.filter((inv) => Number(inv.remaining_amount || 0) > 0).length;
  }, [cycleInvoices]);

  const criticalDefaulters = useMemo(() => {
    return cycleInvoices.filter((inv) => Number(inv.remaining_amount || 0) > 0 && calculateOverdueDays(inv) > 60);
  }, [cycleInvoices]);

  const criticalDebt = useMemo(() => {
    return criticalDefaulters.reduce((sum, inv) => sum + Number(inv.remaining_amount || 0), 0);
  }, [criticalDefaulters]);

  const avgDays = useMemo(() => {
    const debtors = cycleInvoices.filter((inv) => Number(inv.remaining_amount || 0) > 0);
    if (debtors.length === 0) return 0;
    const totalDays = debtors.reduce((sum, inv) => sum + calculateOverdueDays(inv), 0);
    return Math.round(totalDays / debtors.length);
  }, [cycleInvoices]);

  const totalCyclePaid = useMemo(() => {
    return cycleInvoices.reduce((sum, inv) => sum + Number(inv.paid_amount || 0), 0);
  }, [cycleInvoices]);

  // Export to Excel (UTF-8 BOM)
  const handleExportExcel = () => {
    if (sortedInvoices.length === 0) {
      toast.error('لا توجد بيانات مديونيات للتصدير');
      return;
    }

    const excelData = sortedInvoices.map((inv, idx) => {
      const days = calculateOverdueDays(inv);
      const categoryLabel =
        inv.remaining_amount <= 0
          ? 'مسدد بالكامل'
          : days > 60
          ? 'حظر وفصل نهائي'
          : days > 30
          ? 'إنذار كارت'
          : 'تأخير عادي';

      return {
        'م': idx + 1,
        'الدورة المحاسبية': inv.billing_cycle || selectedCycleLabel,
        'رقم المشترك': inv.customer?.subscriber_number || '',
        'اسم المشترك': inv.customer?.full_name || '',
        'رقم الهاتف': inv.customer?.phone_number || '',
        'العنوان والمنطقة': getNormalizedArea(inv.customer?.address),
        'خط السير': inv.customer?.route_number || '1',
        'رقم العداد': inv.customer?.meter_number || '-',
        'الباقة': inv.customer?.subscription_plan?.plan_name || 'باقة سكنية',
        'القراءة السابقة': Number(inv.previous_reading || 0),
        'القراءة الحالية': Number(inv.current_reading || 0),
        'الاستهلاك (kWh)': Number(inv.consumption || 0),
        'قيمة الاستهلاك (ر.ي)': Number(inv.consumption_value || 0),
        'رسوم الاشتراك (ر.ي)': Number(inv.fixed_fee_snapshot || 0),
        'المتأخرات السابقة (ر.ي)': Number(inv.arrears || 0),
        'إجمالي المستحق (ر.ي)': Number(inv.total_due || 0),
        'المدفوع (ر.ي)': Number(inv.paid_amount || 0),
        'المتبقي / المديونية (ر.ي)': Number(inv.remaining_amount || 0),
        'أيام التأخير': days,
        'وضع الخدمة والتصنيف': categoryLabel,
      };
    });

    const worksheet = XLSX.utils.json_to_sheet(excelData);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, `مديونيات_${selectedCycleLabel}`);

    const cleanCycleName = selectedCycleLabel.replace(/[\s\-_]/g, '_');
    XLSX.writeFile(workbook, `تقرير_المديونيات_وحظر_الخدمة_${cleanCycleName}.xlsx`);
    toast.success(`تم تصدير كشف المديونيات لـ ${sortedInvoices.length} مشترك بنجاح!`);
  };

  const handleResetFilters = () => {
    setSearchQuery('');
    setStatusFilter('debtors_only');
    setSelectedRoute('all');
    setSelectedNormalizedRegion('all');
  };

  // Open Statement Modal
  const handleOpenStatement = (inv: Invoice) => {
    if (!inv.customer) return;
    setSelectedStatementCustomer(inv.customer);
    setShowStatementModal(true);
  };

  // Copy Warning Notice Text
  const handleCopyWarningText = async (inv: Invoice) => {
    try {
      const text = buildWarningNoticeText(inv);
      const ok = await safeCopyToClipboard(text);
      if (ok) {
        setCopiedWarning(true);
        toast.success('تم نسخ نص رسالة الإنذار إلى الحافظة بنجاح');
        setTimeout(() => setCopiedWarning(false), 2500);
      } else {
        toast.error('فشل نسخ نص الإنذار');
      }
    } catch (err) {
      toast.error('فشل نسخ نص الإنذار');
    }
  };

  return (
    <div className="space-y-5 pb-12 text-right select-text font-sans" dir="rtl">
      {/* 1. Top Header & Control Toolbar */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 border-b border-slate-200 pb-4">
        <div>
          <h1 className="text-xl sm:text-2xl font-bold flex items-center gap-2 text-slate-900">
            <ShieldAlert className="text-rose-600" size={24} />
            إدارة المديونيات وحظر الخدمة (Debts & Arrears Engine)
          </h1>
          <p className="text-slate-500 text-xs sm:text-sm mt-0.5 font-medium">
            متابعة المتأخرين عن السداد لكل دورة محاسبية، حساب أيام التأخير من تاريخ القراءة، إرسال الإنذارات الرسمية عبر الواتساب،
            ومتابعة السجلات المالية.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {/* Refresh Data */}
          <button
            onClick={() => refetchInvoices()}
            className="h-9 sm:h-10 bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold px-3 rounded-xl transition-all text-xs flex items-center gap-1.5 border border-slate-200"
            title="تحديث البيانات"
          >
            <RefreshCw size={15} />
            <span>تحديث</span>
          </button>

          {/* Bulk Warning Button */}
          {criticalDefaulters.length > 0 && (
            <button
              onClick={() => setShowBulkWarningModal(true)}
              className="h-9 sm:h-10 bg-rose-600 hover:bg-rose-700 text-white font-bold px-3.5 rounded-xl transition-all text-xs flex items-center gap-1.5 shadow-md shadow-rose-600/20"
              title="إرسال إنذار جماعي لجميع المتأخرين الحرجين (>60 يوماً)"
            >
              <Flame size={15} />
              <span>إنذار جماعي ({criticalDefaulters.length.toLocaleString('en-US')})</span>
            </button>
          )}

          {/* Export Excel Button */}
          <button
            onClick={handleExportExcel}
            className="h-9 sm:h-10 bg-emerald-600 hover:bg-emerald-700 text-white font-bold px-4 rounded-xl transition-all text-xs flex items-center gap-2 shadow-md shadow-emerald-500/20"
            title="تصدير كشف المديونيات كملف Excel"
          >
            <FileSpreadsheet size={16} />
            <span>تصدير إكسل ({sortedInvoices.length.toLocaleString('en-US')})</span>
          </button>
        </div>
      </div>

      {/* 2. Full Multi-Year Cycle Switcher (ExcelSheetTabs) */}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-xs font-bold text-slate-700">
          <span className="flex items-center gap-1.5">
            <Clock size={14} className="text-rose-600" />
            <span>اختر الدورة المحاسبية لعرض مديونياتها:</span>
          </span>
          <span className="text-slate-500 font-mono">
            الدورة النشطة: <span className="text-rose-700 font-black">{selectedCycleLabel}</span>
          </span>
        </div>
        <ExcelSheetTabs
          cycles={uniqueCycles}
          selectedCycle={selectedCycleLabel}
          onSelectCycle={(label) => setSelectedCycleLabel(label)}
        />
      </div>

      {/* 3. Top 5 KPI Cards (Matching Tailwind Palette & English Numerals) */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {/* Total Debtors Count */}
        <div className="bg-white border border-slate-200 rounded-xl p-3.5 flex items-center justify-between shadow-xs">
          <div>
            <p className="text-xs text-slate-500 font-semibold">إجمالي المشتركين المدينين</p>
            <h3 className="text-lg font-bold text-slate-800 font-mono mt-0.5">
              {debtorsCount.toLocaleString('en-US')} مشترك
            </h3>
          </div>
          <div className="p-2 bg-blue-50 text-blue-600 rounded-lg">
            <Users className="w-5 h-5" />
          </div>
        </div>

        {/* Total Arrears in YER */}
        <div className="bg-white border border-rose-200 bg-rose-50/40 rounded-xl p-3.5 flex items-center justify-between shadow-xs">
          <div>
            <p className="text-xs text-rose-800 font-semibold">إجمالي المديونية القائمة</p>
            <h3 className="text-lg font-bold text-rose-600 font-mono mt-0.5">
              {totalDebt.toLocaleString('en-US')} ريال
            </h3>
          </div>
          <div className="p-2 bg-rose-100 text-rose-700 rounded-lg">
            <AlertTriangle className="w-5 h-5" />
          </div>
        </div>

        {/* Critical >60 Days Debt */}
        <div className="bg-white border border-red-200 bg-red-50/50 rounded-xl p-3.5 flex items-center justify-between shadow-xs">
          <div>
            <p className="text-xs text-red-900 font-semibold">ديون حرجة (&gt;60 يوم)</p>
            <h3 className="text-lg font-bold text-red-700 font-mono mt-0.5">
              {criticalDebt.toLocaleString('en-US')} ريال
            </h3>
          </div>
          <div className="p-2 bg-red-100 text-red-700 rounded-lg">
            <AlertOctagon className="w-5 h-5" />
          </div>
        </div>

        {/* Average Overdue Days */}
        <div className="bg-white border border-slate-200 rounded-xl p-3.5 flex items-center justify-between shadow-xs">
          <div>
            <p className="text-xs text-slate-500 font-semibold">متوسط التأخير</p>
            <h3 className="text-lg font-bold text-amber-700 font-mono mt-0.5">
              {avgDays.toLocaleString('en-US')} يوم
            </h3>
          </div>
          <div className="p-2 bg-amber-50 text-amber-600 rounded-lg">
            <Clock className="w-5 h-5" />
          </div>
        </div>

        {/* Settled in Cycle */}
        <div className="bg-white border border-emerald-200 bg-emerald-50/40 rounded-xl p-3.5 flex items-center justify-between shadow-xs col-span-2 md:col-span-1">
          <div>
            <p className="text-xs text-emerald-800 font-semibold">المسدد في الدورة</p>
            <h3 className="text-lg font-bold text-emerald-700 font-mono mt-0.5">
              {totalCyclePaid.toLocaleString('en-US')} ريال
            </h3>
          </div>
          <div className="p-2 bg-emerald-100 text-emerald-700 rounded-lg">
            <DollarSign className="w-5 h-5" />
          </div>
        </div>
      </div>

      {/* 4. Status Filter Pills */}
      <div className="flex flex-wrap items-center gap-2 border-b border-slate-200 pb-2.5">
        <span className="text-xs font-bold text-slate-600 ml-1">تصفية الحالة:</span>
        <button
          onClick={() => setStatusFilter('debtors_only')}
          className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all border ${
            statusFilter === 'debtors_only'
              ? 'bg-rose-600 text-white border-rose-600 shadow-sm'
              : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-100'
          }`}
        >
          المدينون فقط ({debtorsCount.toLocaleString('en-US')})
        </button>

        <button
          onClick={() => setStatusFilter('critical')}
          className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all border flex items-center gap-1 ${
            statusFilter === 'critical'
              ? 'bg-red-700 text-white border-red-700 shadow-sm'
              : 'bg-white text-red-700 border-slate-200 hover:bg-red-50'
          }`}
        >
          <Flame size={13} />
          <span>حظر وفصل (&gt;60 يوم) ({criticalDefaulters.length.toLocaleString('en-US')})</span>
        </button>

        <button
          onClick={() => setStatusFilter('warning')}
          className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all border ${
            statusFilter === 'warning'
              ? 'bg-amber-600 text-white border-amber-600 shadow-sm'
              : 'bg-white text-amber-700 border-slate-200 hover:bg-amber-50'
          }`}
        >
          إنذار كارت (31-60 يوم)
        </button>

        <button
          onClick={() => setStatusFilter('paid')}
          className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all border ${
            statusFilter === 'paid'
              ? 'bg-emerald-600 text-white border-emerald-600 shadow-sm'
              : 'bg-white text-emerald-700 border-slate-200 hover:bg-emerald-50'
          }`}
        >
          مسدد بالكامل / رصيد دائن
        </button>

        <button
          onClick={() => setStatusFilter('all')}
          className={`px-3 py-1.5 rounded-xl text-xs font-bold transition-all border ${
            statusFilter === 'all'
              ? 'bg-slate-800 text-white border-slate-800 shadow-sm'
              : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-100'
          }`}
        >
          كافة مشتركي الدورة ({cycleInvoices.length.toLocaleString('en-US')})
        </button>
      </div>

      {/* 5. Area Grouping Filter Pills */}
      <div className="flex overflow-x-auto gap-2 pb-1 [&::-webkit-scrollbar]:hidden [-ms-overflow-style:none] [scrollbar-width:none]">
        <button
          onClick={() => setSelectedNormalizedRegion('all')}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-bold whitespace-nowrap transition-all border ${
            selectedNormalizedRegion === 'all'
              ? 'bg-blue-600 text-white border-blue-600 shadow-md shadow-blue-500/20'
              : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-100 hover:text-slate-900'
          }`}
        >
          كل المناطق ({cycleInvoices.length.toLocaleString('en-US')})
        </button>

        {regionCounts.map(({ area, count }) => (
          <button
            key={area}
            onClick={() => setSelectedNormalizedRegion(area)}
            className={`px-3.5 py-1.5 rounded-xl text-xs font-bold whitespace-nowrap transition-all border flex items-center gap-1.5 ${
              selectedNormalizedRegion === area
                ? 'bg-blue-600 text-white border-blue-600 shadow-md shadow-blue-500/20'
                : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-100 hover:text-slate-900'
            }`}
          >
            <span>{area}</span>
            <span className="bg-slate-100 px-1.5 py-0.5 rounded-md text-[10px] text-slate-700 font-mono font-bold">
              {count.toLocaleString('en-US')}
            </span>
          </button>
        ))}
      </div>

      {/* 6. Filter Toolbar & Search */}
      <div className="bg-white border border-slate-200 rounded-2xl p-2.5 shadow-xs flex flex-col md:flex-row gap-2 items-center justify-between">
        <div className="relative flex-1 w-full">
          <input
            type="text"
            placeholder="بحث باسم المشترك، رقم المشترك، رقم العداد، أو الهاتف..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 rounded-xl pr-10 pl-4 py-2 text-slate-900 text-xs placeholder-slate-400 focus:outline-none focus:border-blue-600 font-medium"
          />
          <Search className="absolute right-3 top-2.5 text-slate-400" size={16} />
        </div>

        <div className="flex flex-wrap items-center gap-2 w-full md:w-auto">
          {/* Route Filter */}
          <select
            value={selectedRoute}
            onChange={(e) => setSelectedRoute(e.target.value)}
            className="w-full md:w-36 bg-slate-50 border border-slate-200 rounded-xl px-3 py-2 text-slate-800 text-xs focus:outline-none focus:border-blue-600 font-bold"
          >
            <option value="all">جميع خطوط السير</option>
            {routes.map((r: string) => (
              <option key={r} value={r}>
                خط {r}
              </option>
            ))}
          </select>

          {/* Sort Switcher */}
          <div className="flex items-center gap-1 bg-slate-100 p-1 rounded-xl border border-slate-200 text-xs">
            <button
              onClick={() => setSortBy('arrears')}
              className={`px-2.5 py-1 rounded-lg font-bold transition-all ${
                sortBy === 'arrears' ? 'bg-white text-rose-700 shadow-xs' : 'text-slate-600'
              }`}
            >
              الأعلى ديناً
            </button>
            <button
              onClick={() => setSortBy('days')}
              className={`px-2.5 py-1 rounded-lg font-bold transition-all ${
                sortBy === 'days' ? 'bg-white text-amber-700 shadow-xs' : 'text-slate-600'
              }`}
            >
              الأطول تأخيراً
            </button>
            <button
              onClick={() => setSortBy('route')}
              className={`px-2.5 py-1 rounded-lg font-bold transition-all ${
                sortBy === 'route' ? 'bg-white text-blue-700 shadow-xs' : 'text-slate-600'
              }`}
            >
              خط السير
            </button>
          </div>

          {(searchQuery ||
            statusFilter !== 'debtors_only' ||
            selectedRoute !== 'all' ||
            selectedNormalizedRegion !== 'all') && (
            <button
              onClick={handleResetFilters}
              className="bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 p-2 rounded-xl text-xs transition-colors"
              title="إعادة ضبط الفلاتر"
            >
              <RotateCcw size={16} />
            </button>
          )}
        </div>
      </div>

      {/* 7. Arrears & Defaulters Data Table */}
      <div className="bg-white border border-slate-200 rounded-2xl shadow-xs overflow-hidden">
        {isLoadingInvoices ? (
          <div className="p-12 text-center text-slate-500 font-medium">
            <RefreshCw className="w-8 h-8 mx-auto mb-2 animate-spin text-rose-600" />
            جاري تحميل كشف مديونيات دورة [{selectedCycleLabel}]...
          </div>
        ) : sortedInvoices.length === 0 ? (
          <div className="p-12 text-center text-slate-500">
            <CheckCircle2 className="w-12 h-12 mx-auto mb-3 text-emerald-500" />
            <h3 className="text-base font-bold text-slate-800">لا توجد مديونيات مطابقة للفلاتر المحددة</h3>
            <p className="text-xs text-slate-400 mt-1">كافة المشتركين مسددين أو لا توجد نتائج مطابقة لبحثك في دورة [{selectedCycleLabel}].</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right border-collapse text-xs">
              <thead>
                <tr className="bg-slate-900 text-white font-bold text-[11px] border-b border-slate-800 select-none">
                  <th className="p-3 text-center w-10">م</th>
                  <th className="p-3">المشترك</th>
                  <th className="p-3">رقم الاشتراك / العداد</th>
                  <th className="p-3">خط السير / الحي</th>
                  <th className="p-3 text-center">القراءة (س / ح)</th>
                  <th className="p-3 text-center">الاستهلاك (kWh)</th>
                  <th className="p-3 text-left font-mono">المتأخرات السابقة</th>
                  <th className="p-3 text-left font-mono">إجمالي المستحق</th>
                  <th className="p-3 text-left font-mono">المدفوع</th>
                  <th className="p-3 text-left font-mono text-rose-400">المتبقي (المديونية)</th>
                  <th className="p-3 text-center">أيام التأخير / الوضع</th>
                  <th className="p-3 text-center w-40">الإجراءات</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {sortedInvoices.map((inv, idx) => {
                  const days = calculateOverdueDays(inv);
                  const rem = Number(inv.remaining_amount || 0);
                  const isPaid = rem <= 0;
                  const isCritical = rem > 0 && days > 60;
                  const isWarning = rem > 0 && days > 30 && days <= 60;

                  return (
                    <tr
                      key={inv.id}
                      className={`transition-colors hover:bg-slate-50/80 ${
                        isCritical
                          ? 'bg-rose-50/30'
                          : isWarning
                          ? 'bg-amber-50/20'
                          : isPaid
                          ? 'bg-emerald-50/20'
                          : ''
                      }`}
                    >
                      {/* Index */}
                      <td className="p-3 text-center font-mono text-slate-500 font-bold">
                        {idx + 1}
                      </td>

                      {/* Customer Info */}
                      <td className="p-3">
                        <div className="font-bold text-slate-900 text-xs">
                          {inv.customer?.full_name || '--'}
                        </div>
                        <div className="text-[11px] text-slate-500 font-mono font-medium flex items-center gap-1 mt-0.5">
                          <Phone size={11} className="text-slate-400" />
                          <span dir="ltr">{inv.customer?.phone_number || '--'}</span>
                        </div>
                      </td>

                      {/* Subscriber & Meter Number */}
                      <td className="p-3">
                        <div className="font-mono font-bold text-blue-700 text-xs">
                          {inv.customer?.subscriber_number || '--'}
                        </div>
                        <div className="text-[11px] text-slate-500 font-mono flex items-center gap-1 mt-0.5">
                          <Gauge size={11} className="text-slate-400" />
                          <span>{inv.customer?.meter_number || '--'}</span>
                        </div>
                      </td>

                      {/* Route & Area */}
                      <td className="p-3">
                        <span className="inline-block px-2 py-0.5 rounded-md bg-slate-100 text-slate-700 font-mono font-bold text-[10px] mb-0.5">
                          خط {inv.customer?.route_number || '1'}
                        </span>
                        <div className="text-[11px] text-slate-600 font-medium truncate max-w-[140px]" title={inv.customer?.address}>
                          {getNormalizedArea(inv.customer?.address)}
                        </div>
                      </td>

                      {/* Previous & Current Reading */}
                      <td className="p-3 text-center font-mono">
                        <div className="text-slate-700 font-bold">
                          {Number(inv.previous_reading || 0).toLocaleString('en-US')}
                          <span className="text-slate-400 mx-1">/</span>
                          {Number(inv.current_reading || 0).toLocaleString('en-US')}
                        </div>
                      </td>

                      {/* Consumption */}
                      <td className="p-3 text-center font-mono">
                        <div className="font-bold text-slate-800">
                          {Number(inv.consumption || 0).toLocaleString('en-US')}
                        </div>
                        <div className="text-[10px] text-slate-500 font-medium">
                          {Number(inv.consumption_value || 0).toLocaleString('en-US')} ر.ي
                        </div>
                      </td>

                      {/* Arrears */}
                      <td className="p-3 text-left font-mono font-bold text-amber-800" dir="ltr">
                        {Number(inv.arrears || 0).toLocaleString('en-US')}
                      </td>

                      {/* Total Due */}
                      <td className="p-3 text-left font-mono font-bold text-slate-900" dir="ltr">
                        {Number(inv.total_due || 0).toLocaleString('en-US')}
                      </td>

                      {/* Paid Amount */}
                      <td className="p-3 text-left font-mono font-bold text-emerald-700" dir="ltr">
                        {Number(inv.paid_amount || 0).toLocaleString('en-US')}
                      </td>

                      {/* Remaining Debt */}
                      <td className="p-3 text-left font-mono" dir="ltr">
                        <span
                          className={`font-black text-xs px-2 py-0.5 rounded-lg inline-block ${
                            rem <= 0
                              ? 'bg-emerald-100 text-emerald-800'
                              : isCritical
                              ? 'bg-rose-100 text-rose-800'
                              : 'bg-red-50 text-red-700'
                          }`}
                        >
                          {rem.toLocaleString('en-US')}
                        </span>
                      </td>

                      {/* Overdue Days & Status Badge */}
                      <td className="p-3 text-center">
                        {isPaid ? (
                          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-800">
                            <Check size={11} />
                            مسدد بالكامل
                          </span>
                        ) : isCritical ? (
                          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-black bg-rose-100 text-rose-800 border border-rose-300 animate-pulse">
                            <Flame size={11} />
                            فصل وحظر ({days} يوم)
                          </span>
                        ) : isWarning ? (
                          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-800 border border-amber-200">
                            <AlertTriangle size={11} />
                            إنذار كارت ({days} يوم)
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-medium bg-blue-50 text-blue-700 border border-blue-200">
                            <Clock size={11} />
                            تأخير عادي ({days} يوم)
                          </span>
                        )}
                      </td>

                      {/* Actions (WhatsApp Warning, Copy Notice, Statement Details) */}
                      <td className="p-3 text-center">
                        <div className="flex items-center justify-center gap-1.5">
                          {/* WhatsApp Warning Button */}
                          {rem > 0 && (
                            <button
                              type="button"
                              onClick={() => setSelectedWarningInvoice(inv)}
                              className="p-1.5 rounded-lg bg-rose-600 hover:bg-rose-700 text-white transition-colors shadow-xs"
                              title="إرسال إنذار رسمي عبر الواتساب"
                            >
                              <Send size={14} />
                            </button>
                          )}

                          {/* Copy Notice Text */}
                          <button
                            type="button"
                            onClick={() => handleCopyWarningText(inv)}
                            className="p-1.5 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 transition-colors"
                            title="نسخ نص الإنذار للحافظة"
                          >
                            <Copy size={14} />
                          </button>

                          {/* Statement Details Button */}
                          <button
                            type="button"
                            onClick={() => handleOpenStatement(inv)}
                            className="p-1.5 rounded-lg bg-slate-100 hover:bg-slate-200 text-blue-700 border border-slate-200 transition-colors"
                            title="عرض كشف الحساب والسجل المالي"
                          >
                            <FileText size={14} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* 8. Single Warning Notice Confirmation Modal (Clean Light Theme) */}
      {selectedWarningInvoice && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-xs p-4 overflow-y-auto">
          <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-lg overflow-hidden animate-in fade-in zoom-in-95 duration-200">
            {/* Modal Header */}
            <div className="bg-white p-4 sm:p-5 flex items-center justify-between border-b border-slate-200">
              <div className="flex items-center gap-2.5">
                <div className="w-10 h-10 rounded-xl bg-rose-50 border border-rose-200 flex items-center justify-center text-rose-600">
                  <ShieldAlert size={20} />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-900">معاينة وإرسال إنذار الفصل الرسمي</h3>
                  <p className="text-xs text-slate-500">
                    إرسال إشعار السداد وفصل التيار إلى هاتف المشترك عبر طابور الواتساب
                  </p>
                </div>
              </div>
              <button
                onClick={() => setSelectedWarningInvoice(null)}
                className="p-1.5 text-slate-400 hover:text-slate-700 rounded-lg hover:bg-slate-100 transition-colors"
              >
                <X size={20} />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-5 space-y-4">
              <div className="bg-slate-50 border border-slate-200 rounded-xl p-3.5 text-xs space-y-2">
                <div className="flex justify-between items-center">
                  <span className="text-slate-500 font-semibold">المشترك:</span>
                  <span className="font-bold text-slate-900 text-sm">{selectedWarningInvoice.customer?.full_name}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-slate-500 font-semibold">رقم الاشتراك:</span>
                  <span className="font-mono font-bold text-blue-700">{selectedWarningInvoice.customer?.subscriber_number}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-slate-500 font-semibold">رقم الهاتف:</span>
                  <span className="font-mono font-bold text-slate-800" dir="ltr">{selectedWarningInvoice.customer?.phone_number}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-slate-500 font-semibold">الدورة المحاسبية:</span>
                  <span className="font-bold text-purple-700">{selectedWarningInvoice.billing_cycle || selectedCycleLabel}</span>
                </div>
                <div className="flex justify-between items-center pt-1 border-t border-slate-200">
                  <span className="text-slate-600 font-bold">المديونية المتبقية:</span>
                  <span className="font-mono font-black text-rose-600 text-base">
                    {Number(selectedWarningInvoice.remaining_amount || 0).toLocaleString('en-US')} ر.ي
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-slate-600 font-bold">أيام التأخير من تاريخ القراءة:</span>
                  <span className="font-mono font-bold text-amber-700 bg-amber-50 px-2 py-0.5 rounded-md border border-amber-200">
                    {calculateOverdueDays(selectedWarningInvoice).toLocaleString('en-US')} يوماً
                  </span>
                </div>
              </div>

              {/* Notice Preview Text Box */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  نص رسالة الإنذار التي ستصل للمشترك:
                </label>
                <div className="bg-slate-50 border border-slate-300 text-slate-800 rounded-xl p-3.5 text-xs font-mono whitespace-pre-wrap leading-relaxed max-h-52 overflow-y-auto">
                  {buildWarningNoticeText(selectedWarningInvoice)}
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-slate-200">
                <button
                  type="button"
                  onClick={() => handleCopyWarningText(selectedWarningInvoice)}
                  className="px-4 py-2.5 rounded-xl border border-slate-300 text-slate-700 text-xs font-bold hover:bg-slate-100 transition-colors flex items-center gap-1.5"
                >
                  <Copy size={15} />
                  <span>{copiedWarning ? 'تم النسخ' : 'نسخ النص'}</span>
                </button>

                <button
                  type="button"
                  disabled={warningMutation.isPending}
                  onClick={() => {
                    if (selectedWarningInvoice.customer?.id) {
                      warningMutation.mutate({
                        customerId: selectedWarningInvoice.customer.id,
                        amount: Number(selectedWarningInvoice.remaining_amount || 0),
                      });
                    }
                  }}
                  className="px-5 py-2.5 rounded-xl bg-rose-600 hover:bg-rose-700 text-white text-xs font-black transition-all flex items-center gap-1.5 shadow-md shadow-rose-600/20 disabled:opacity-50"
                >
                  <Send size={15} />
                  <span>{warningMutation.isPending ? 'جاري الإرسال...' : 'تأكيد وإرسال إلى الواتساب'}</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* 9. Bulk Warning Modal (Clean Light Theme) */}
      {showBulkWarningModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 backdrop-blur-xs p-4 overflow-y-auto">
          <div className="bg-white rounded-2xl shadow-2xl border border-slate-200 w-full max-w-lg overflow-hidden animate-in fade-in zoom-in-95 duration-200">
            {/* Modal Header */}
            <div className="bg-white p-4 sm:p-5 flex items-center justify-between border-b border-slate-200">
              <div className="flex items-center gap-2.5">
                <div className="w-10 h-10 rounded-xl bg-rose-50 border border-rose-200 flex items-center justify-center text-rose-600">
                  <Flame size={20} />
                </div>
                <div>
                  <h3 className="text-base font-bold text-slate-900">إرسال إنذارات فصل جماعية</h3>
                  <p className="text-xs text-slate-500">
                    دورة [{selectedCycleLabel}] - عدد المشتركين الحرجين: {criticalDefaulters.length.toLocaleString('en-US')}
                  </p>
                </div>
              </div>
              <button
                onClick={() => setShowBulkWarningModal(false)}
                className="p-1.5 text-slate-400 hover:text-slate-700 rounded-lg hover:bg-slate-100 transition-colors"
              >
                <X size={20} />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-5 space-y-4 text-xs">
              <div className="bg-rose-50 border border-rose-200 rounded-xl p-3.5 text-rose-900">
                <p className="font-bold flex items-center gap-1.5 text-sm">
                  <AlertTriangle size={16} className="text-rose-600" />
                  <span>تنبيه وإشعار بالعملية:</span>
                </p>
                <p className="text-xs mt-1 text-rose-800 leading-relaxed">
                  سيتم إنشاء رسائل إنذار رسمية مخصصة وإدراجها فوراً في طابور رسائل الواتساب لـ{' '}
                  <span className="font-bold font-mono">{criticalDefaulters.length.toLocaleString('en-US')}</span> مشترك متأخر عن السداد لأكثر من 60 يوماً بإجمالي مديونية قدرها{' '}
                  <span className="font-bold font-mono">{criticalDebt.toLocaleString('en-US')}</span> ريال يمني.
                </p>
              </div>

              {/* Defaulters List Preview */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1.5">
                  قائمة المشتركين المشمولين بالإنذار:
                </label>
                <div className="bg-slate-50 border border-slate-200 rounded-xl p-2.5 max-h-48 overflow-y-auto divide-y divide-slate-100">
                  {criticalDefaulters.map((inv, i) => (
                    <div key={inv.id} className="py-1.5 flex items-center justify-between text-xs">
                      <span className="font-bold text-slate-800">
                        {i + 1}. {inv.customer?.full_name}
                      </span>
                      <span className="font-mono font-bold text-rose-700">
                        {Number(inv.remaining_amount || 0).toLocaleString('en-US')} ر.ي
                      </span>
                    </div>
                  ))}
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center justify-end gap-2.5 pt-3 border-t border-slate-200">
                <button
                  type="button"
                  onClick={() => setShowBulkWarningModal(false)}
                  className="px-4 py-2.5 rounded-xl border border-slate-300 text-slate-700 text-xs font-bold hover:bg-slate-100 transition-colors"
                >
                  إلغاء
                </button>

                <button
                  type="button"
                  disabled={bulkWarningMutation.isPending}
                  onClick={() => {
                    const items = criticalDefaulters
                      .filter((inv) => inv.customer?.id)
                      .map((inv) => ({
                        customer_id: inv.customer!.id,
                        amount: Number(inv.remaining_amount || 0),
                      }));
                    bulkWarningMutation.mutate(items);
                  }}
                  className="px-5 py-2.5 rounded-xl bg-rose-600 hover:bg-rose-700 text-white text-xs font-black transition-all flex items-center gap-1.5 shadow-md shadow-rose-600/20 disabled:opacity-50"
                >
                  <Send size={15} />
                  <span>{bulkWarningMutation.isPending ? 'جاري الإرسال الجماعي...' : 'تأكيد وإرسال لكافة المتأخرين'}</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* 10. Statement Details Modal */}
      <StatementModal
        isOpen={showStatementModal}
        onClose={() => setShowStatementModal(false)}
        customer={selectedStatementCustomer}
      />
    </div>
  );
};

export default ArrearsReport;
