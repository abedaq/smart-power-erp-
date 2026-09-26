import React, { useState, useMemo, useEffect } from 'react';
import {
  Search,
  X,
  Send,
  Eye,
  Trash2,
  Users,
  Zap,
  AlertCircle,
  DollarSign,
  CheckCircle2,
  RotateCcw,
  AlertTriangle,
  ShieldAlert,
  Check,
  FileText,
} from 'lucide-react';
import type { GridRowData, ComputedGridRow, GridFooterTotals } from '../../types/excelGrid.types';
import {
  computeRowFinancials,
  computeGridTotals,
} from '../../types/excelGrid.types';
import { InvoiceModal } from './InvoiceModal';
import { toEnglishDigits, sanitizeDecimalInput, formatInputNumberBlankZero, formatRawBlankZero, parseFormattedNumber } from '../../utils/formatters';
import toast from 'react-hot-toast';

export interface ExcelGridProps {
  title?: string;
  subtitle?: string;
  period?: string;
  onPeriodChange?: (newPeriod: string) => void;
  rows: GridRowData[];
  isLoading?: boolean;
  isHistorical?: boolean;
  activeCycles?: string[];
  onCellSave?: (
    id: number,
    field: keyof GridRowData,
    value: any,
    updatedRow: ComputedGridRow
  ) => Promise<void> | void;
  onApproveAndSend?: (row: ComputedGridRow) => Promise<void> | void;
  onAddNewRow?: () => void;
  onDeleteRow?: (id: number) => Promise<void> | void;
  onApplyGlobalRates?: (kwhPrice: number, serviceFee: number) => Promise<void> | void;
  extraHeaderActions?: React.ReactNode;
  extraFilterControls?: React.ReactNode;
  extraRowActions?: (row: ComputedGridRow) => React.ReactNode;
  actionColumnPosition?: 'start' | 'end' | 'none';
  hidePaidColumn?: boolean;
  hideRemainingColumn?: boolean;
  hidePreviewColumn?: boolean;
  hideDeleteColumn?: boolean;
  hideActionsColumn?: boolean;
  onPreviewInvoice?: (row: ComputedGridRow) => void;
  exportFilenamePrefix?: string;
  emptyMessage?: string;
  enableRowSelection?: boolean;
  selectedRowIds?: number[];
  onSelectionChange?: (selectedIds: number[]) => void;
}

export const ExcelGrid: React.FC<ExcelGridProps> = ({
  period = 'اغسطس - 2026',
  rows: initialRows,
  isLoading = false,
  isHistorical,
  onCellSave,
  onApproveAndSend,
  onDeleteRow,
  extraFilterControls,
  extraRowActions,
  actionColumnPosition = 'start',
  hidePaidColumn = false,
  hideRemainingColumn = false,
  hidePreviewColumn = false,
  hideDeleteColumn = false,
  hideActionsColumn = false,
  onPreviewInvoice,
  emptyMessage = 'لا توجد سجلات مطابقة للبحث أو الفلترة المحددة.',
  enableRowSelection = false,
  selectedRowIds = [],
  onSelectionChange,
}) => {
  // Local state for optimistic live editing
  const [localRows, setLocalRows] = useState<GridRowData[]>(initialRows);
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);
  const searchInputRef = React.useRef<HTMLInputElement>(null);

  // Unlocked historical cycles in this session
  const [unlockedPeriods, setUnlockedPeriods] = useState<Set<string>>(new Set());
  const [showHistoricalWarningModal, setShowHistoricalWarningModal] = useState<boolean>(false);
  const [historicalConfirmInput, setHistoricalConfirmInput] = useState<string>('');

  // Check if current viewed cycle is a historical/closed cycle
  // Strictly activate lock ONLY if isHistorical === true is explicitly passed by parent component
  const isHistoricalPeriod = Boolean(isHistorical);
  const isPeriodLocked = isHistoricalPeriod && !unlockedPeriods.has(period || '');

  // Selected row for Invoice Modal
  const [selectedInvoiceRow, setSelectedInvoiceRow] = useState<ComputedGridRow | null>(null);

  // Delete modal state
  const [pendingDeleteRow, setPendingDeleteRow] = useState<ComputedGridRow | null>(null);

  // Sync props when initialRows changes externally while preserving active local edits
  useEffect(() => {
    setLocalRows((prev) => {
      if (prev.length === 0) return initialRows;
      return initialRows.map((initRow) => {
        const local = prev.find((p) => p.id === initRow.id);
        if (!local) return initRow;
        return {
          ...initRow,
          subNumber: dirtyCells.has(`${initRow.id}:subNumber`) ? local.subNumber : initRow.subNumber,
          route: dirtyCells.has(`${initRow.id}:route`) ? local.route : initRow.route,
          name: dirtyCells.has(`${initRow.id}:name`) ? local.name : initRow.name,
          address: dirtyCells.has(`${initRow.id}:address`) ? local.address : initRow.address,
          meterNumber: dirtyCells.has(`${initRow.id}:meterNumber`) ? local.meterNumber : initRow.meterNumber,
          phone: dirtyCells.has(`${initRow.id}:phone`) ? local.phone : initRow.phone,
          currReading: dirtyCells.has(`${initRow.id}:currReading`) ? local.currReading : initRow.currReading,
          prevReading: dirtyCells.has(`${initRow.id}:prevReading`) ? local.prevReading : initRow.prevReading,
          unitPrice: dirtyCells.has(`${initRow.id}:unitPrice`) ? local.unitPrice : initRow.unitPrice,
          serviceFee: dirtyCells.has(`${initRow.id}:serviceFee`) ? local.serviceFee : initRow.serviceFee,
          arrears: dirtyCells.has(`${initRow.id}:arrears`) ? local.arrears : initRow.arrears,
          paidAmount: dirtyCells.has(`${initRow.id}:paidAmount`) ? local.paidAmount : initRow.paidAmount,
        };
      });
    });
  }, [initialRows]);

  // Original snapshot map to track modified cells
  const initialRowsMap = useMemo(() => {
    const map = new Map<number, GridRowData>();
    initialRows.forEach((r) => map.set(r.id, r));
    return map;
  }, [initialRows]);

  // Track modified cell keys (id:field) in live session memory ONLY (No localStorage persistence)
  const [dirtyCells, setDirtyCells] = useState<Set<string>>(new Set());

  const markCellDirty = (id: number, field: keyof GridRowData) => {
    const key = `${id}:${field}`;
    setDirtyCells((prev) => {
      if (prev.has(key)) return prev;
      const next = new Set(prev);
      next.add(key);
      return next;
    });
  };

  const unmarkCellDirty = (id: number, field: keyof GridRowData) => {
    const key = `${id}:${field}`;
    setDirtyCells((prev) => {
      if (!prev.has(key)) return prev;
      const next = new Set(prev);
      next.delete(key);
      return next;
    });
  };

  // Helper to detect if a specific cell has been modified from its initial state
  const isCellModified = (id: number, field: keyof GridRowData, currentValue: any): boolean => {
    const key = `${id}:${field}`;
    if (dirtyCells.has(key)) return true;
    const orig = initialRowsMap.get(id);
    if (!orig) return false;
    const origVal = orig[field];
    if (typeof origVal === 'number' || typeof currentValue === 'number') {
      return Number(origVal || 0) !== Number(currentValue || 0);
    }
    return String(origVal ?? '').trim() !== String(currentValue ?? '').trim();
  };

  // Compute financial state for all rows
  const computedRows: ComputedGridRow[] = useMemo(() => {
    return localRows.map(computeRowFinancials);
  }, [localRows]);

  // Filter rows based on search query
  const filteredRows: ComputedGridRow[] = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) return computedRows;

    return computedRows.filter((row) => {
      return (
        (row.name && row.name.toLowerCase().includes(query)) ||
        (row.subNumber && row.subNumber.toLowerCase().includes(query)) ||
        (row.meterNumber && row.meterNumber.toLowerCase().includes(query)) ||
        (row.address && row.address.toLowerCase().includes(query)) ||
        (row.phone && row.phone.toLowerCase().includes(query)) ||
        (row.route && row.route.toLowerCase().includes(query))
      );
    });
  }, [computedRows, searchQuery]);

  // Aggregate totals for KPI cards and sticky footer
  const totals: GridFooterTotals = useMemo(() => {
    return computeGridTotals(filteredRows);
  }, [filteredRows]);

  const handleSelectAll = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!onSelectionChange) return;
    if (e.target.checked) {
      onSelectionChange(filteredRows.map(r => r.id));
    } else {
      onSelectionChange([]);
    }
  };

  const handleSelectRow = (id: number, checked: boolean) => {
    if (!onSelectionChange) return;
    if (checked) {
      onSelectionChange([...selectedRowIds, id]);
    } else {
      onSelectionChange(selectedRowIds.filter(rowId => rowId !== id));
    }
  };

  // Helper to compare values strictly
  const areValuesEqual = (val1: any, val2: any): boolean => {
    if (val1 === val2) return true;
    if (typeof val1 === 'number' || typeof val2 === 'number') {
      return Number(val1 || 0) === Number(val2 || 0);
    }
    return String(val1 ?? '').trim() === String(val2 ?? '').trim();
  };

  // Handle cell value change (optimistic local update)
  const handleCellChange = (id: number, field: keyof GridRowData, rawValue: any) => {
    if (isPeriodLocked) {
      setShowHistoricalWarningModal(true);
      return;
    }
    const orig = initialRowsMap.get(id);
    const origVal = orig ? orig[field] : undefined;
    if (!areValuesEqual(origVal, rawValue)) {
      markCellDirty(id, field);
    }
    setLocalRows((prev) =>
      prev.map((r) => {
        if (r.id === id) {
          return { ...r, [field]: rawValue };
        }
        return r;
      })
    );
  };

  // Handle cell blur / enter save
  const handleCellBlur = (id: number, field: keyof GridRowData, rawValue: any) => {
    const targetRow = localRows.find((r) => r.id === id);
    if (!targetRow) return;

    const orig = initialRowsMap.get(id);
    const origVal = orig ? orig[field] : undefined;

    // Strict Change Guard: If value is identical to original, DO NOT save, DO NOT call API!
    if (areValuesEqual(origVal, rawValue)) {
      return;
    }

    if (field === 'currReading') {
      const curr = Number(rawValue || 0);
      const prev = Number(targetRow.prevReading || 0);
      if (curr > 0 && prev > 0 && curr < prev) {
        toast.error(`خطأ: القراءة الحالية (${curr}) أقل من القراءة السابقة (${prev}). يرجى التحقق من رقم العداد.`);
        return;
      }
    }

    markCellDirty(id, field);
    const updatedRow = { ...targetRow, [field]: rawValue };
    const computed = computeRowFinancials(updatedRow);

    // Update snapshot map to prevent revert on re-render
    initialRowsMap.set(id, updatedRow);

    // Persist normalized value in localRows immediately
    setLocalRows((prev) =>
      prev.map((r) => (r.id === id ? { ...r, [field]: rawValue } : r))
    );

    if (onCellSave) {
      Promise.resolve(onCellSave(id, field, rawValue, computed))
        .then(() => {
          unmarkCellDirty(id, field);
        })
        .catch(() => {
          // Keep dirty indicator on error
        });
    }
  };

  const handleInputFocus = (e: React.FocusEvent<HTMLInputElement>) => {
    if (isPeriodLocked) {
      e.target.blur();
      setShowHistoricalWarningModal(true);
      return;
    }
    e.target.select();
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      (e.target as HTMLInputElement).blur();
    }
  };

  // Handle Direct WhatsApp sending & row approval
  const handleDirectWhatsApp = (row: ComputedGridRow) => {
    if (onPreviewInvoice) {
      onPreviewInvoice(row);
      return;
    }
    if (onApproveAndSend) {
      onApproveAndSend(row);
      return;
    }
    setSelectedInvoiceRow(row);
  };

  // Handle Delete Confirmation
  const handleConfirmDelete = async () => {
    if (!pendingDeleteRow) return;
    const deleteId = pendingDeleteRow.id;
    setLocalRows((prev) => prev.filter((r) => r.id !== deleteId));
    setPendingDeleteRow(null);

    if (onDeleteRow) {
      await onDeleteRow(deleteId);
    }
    toast.success('تم حذف المشترك من الكشف بنجاح');
  };

  return (
    <div className="space-y-4 text-right select-text font-sans">
      {/* 1. Top 5 KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {/* Total Subscribers */}
        <div className="bg-white border border-slate-200 rounded-xl p-3 flex items-center justify-between shadow-sm">
          <div>
            <p className="text-xs text-slate-500 font-semibold">إجمالي المشتركين</p>
            <h3 className="text-lg font-bold text-slate-800 font-mono mt-0.5">
              {totals.visibleCount.toLocaleString('en-US')} مشترك
            </h3>
          </div>
          <div className="p-2 bg-blue-50 text-blue-600 rounded-lg">
            <Users className="w-5 h-5" />
          </div>
        </div>

        {/* Energy Consumption */}
        <div className="bg-white border border-slate-200 rounded-xl p-3 flex items-center justify-between shadow-sm">
          <div>
            <p className="text-xs text-slate-500 font-semibold">استهلاك الطاقة</p>
            <h3 className="text-lg font-bold text-amber-700 font-mono mt-0.5">
              {totals.totalUnitsSum.toLocaleString('en-US')} ك.و
            </h3>
          </div>
          <div className="p-2 bg-amber-50 text-amber-600 rounded-lg">
            <Zap className="w-5 h-5" />
          </div>
        </div>

        {/* Total Arrears */}
        <div className="bg-white border border-rose-200 bg-rose-50/30 rounded-xl p-3 flex items-center justify-between shadow-sm">
          <div>
            <p className="text-xs text-rose-800 font-semibold">إجمالي المتأخرات</p>
            <h3 className="text-lg font-bold text-rose-600 font-mono mt-0.5">
              {totals.totalArrearsSum.toLocaleString('en-US')} ريال
            </h3>
          </div>
          <div className="p-2 bg-rose-100 text-rose-700 rounded-lg">
            <AlertCircle className="w-5 h-5" />
          </div>
        </div>

        {/* Total Due */}
        <div className="bg-white border border-slate-200 rounded-xl p-3 flex items-center justify-between shadow-sm">
          <div>
            <p className="text-xs text-slate-500 font-semibold">إجمالي المستحق العام</p>
            <h3 className="text-lg font-bold text-emerald-700 font-mono mt-0.5">
              {totals.totalDueSum.toLocaleString('en-US')} ريال
            </h3>
          </div>
          <div className="p-2 bg-emerald-50 text-emerald-600 rounded-lg">
            <DollarSign className="w-5 h-5" />
          </div>
        </div>

        {/* Remaining Balance */}
        <div className="bg-white border border-slate-200 rounded-xl p-3 flex items-center justify-between shadow-sm col-span-2 md:col-span-1">
          <div>
            <p className="text-xs text-slate-500 font-semibold">{totals.totalRemainingSum < 0 ? 'الرصيد الفائض (دائن)' : 'المتبقي قيد التحصيل'}</p>
            <h3 className={`text-lg font-bold font-mono mt-0.5 ${totals.totalRemainingSum < 0 ? 'text-emerald-700' : 'text-slate-900'}`}>
              {totals.totalRemainingSum !== 0 
                ? (totals.totalRemainingSum > 0 ? `${totals.totalRemainingSum.toLocaleString('en-US')} ريال` : `-${Math.abs(totals.totalRemainingSum).toLocaleString('en-US')} ريال`)
                : '0 ريال'}
            </h3>
          </div>
          <div className={`p-2 rounded-lg ${totals.totalRemainingSum < 0 ? 'bg-emerald-50 text-emerald-600' : 'bg-slate-100 text-slate-700'}`}>
            <CheckCircle2 className="w-5 h-5" />
          </div>
        </div>
      </div>

      {/* 3. Search Bar & Cycle Tabs Toolbar */}
      <div className="flex flex-col lg:flex-row items-center justify-between gap-3 bg-white p-2.5 rounded-xl border border-slate-200 shadow-sm">
        {/* Icon-Only Click-to-Expand Enterprise Search Bar */}
        {!isSearchOpen && !searchQuery ? (
          <button
            type="button"
            onClick={() => {
              setIsSearchOpen(true);
              setTimeout(() => searchInputRef.current?.focus(), 50);
            }}
            className="p-2 px-3 bg-slate-100 hover:bg-purple-50 text-slate-700 hover:text-purple-700 rounded-xl transition-all duration-300 cursor-pointer border border-slate-200/90 shadow-2xs flex items-center gap-1.5 shrink-0"
            title="انقر لفتح البحث..."
          >
            <Search className="w-4 h-4 text-purple-600" />
            <span className="text-xs font-bold">بحث...</span>
          </button>
        ) : (
          <div className="relative flex items-center w-full lg:w-96 transition-all duration-300 ease-in-out">
            <Search className="w-4 h-4 text-purple-600 absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none" />
            <input
              ref={searchInputRef}
              type="text"
              placeholder="بحث باسم المشترك، رقم الاشتراك، رقم العداد أو الهاتف..."
              value={searchQuery}
              onBlur={() => {
                if (!searchQuery.trim()) {
                  setIsSearchOpen(false);
                }
              }}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full bg-white border-2 border-purple-500 rounded-xl pr-9 pl-8 py-1.5 text-xs text-slate-800 placeholder-slate-400 focus:outline-none shadow-md font-medium"
              autoFocus
            />
            <button
              type="button"
              onClick={() => {
                setSearchQuery('');
                setIsSearchOpen(false);
              }}
              className="absolute left-2.5 top-1/2 -translate-y-1/2 p-1 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition-colors cursor-pointer"
              title="إغلاق البحث"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        )}

        <div className="flex items-center gap-2 w-full lg:w-auto overflow-x-auto justify-start lg:justify-end">
          {extraFilterControls}

          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              className="p-1.5 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg text-xs shrink-0"
              title="مسح البحث"
            >
              <RotateCcw className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* 4. Interactive Excel Data Grid */}
      <div className="bg-white border-2 border-slate-300 rounded-2xl shadow-md overflow-hidden">
        <div className="overflow-x-auto max-h-[640px] [&::-webkit-scrollbar]:w-2 [&::-webkit-scrollbar]:h-2 [&::-webkit-scrollbar-thumb]:bg-slate-400 [&::-webkit-scrollbar-track]:bg-slate-100">
          <table className="w-full text-right border-collapse text-xs">
            {/* Sticky Table Header */}
            <thead className="bg-slate-200/95 backdrop-blur-xs text-slate-900 sticky top-0 z-20 border-b-2 border-slate-400 shadow-sm font-black select-none">
              <tr className="divide-x divide-x-reverse divide-slate-300">
                <th className="py-3 px-2 w-12 min-w-[48px] text-center bg-slate-300/90 text-slate-950 font-black">#</th>
                {actionColumnPosition === 'start' && (
                  <th className="py-3 px-2.5 min-w-[100px] text-emerald-900 text-center bg-emerald-100/90 border-b-2 border-emerald-400 font-black">
                    الإرسال المعتمد
                  </th>
                )}
                <th className="py-3 px-2 min-w-[95px] font-black">رقم المشترك</th>
                <th className="py-3 px-2 w-16 text-center font-black">خط السير</th>
                <th className="py-3 px-3.5 min-w-[220px] font-black text-slate-950">اسم المشترك</th>
                <th className="py-3 px-3 min-w-[160px] font-black">العنوان</th>
                <th className="py-3 px-2 min-w-[105px] font-black">رقم العداد</th>
                <th className="py-3 px-2 min-w-[105px] font-black">الهاتف</th>
                <th className="py-3 px-2 min-w-[85px] bg-amber-100/70 text-amber-950 font-black">السابقة</th>
                <th className="py-3 px-2 min-w-[85px] bg-blue-100/70 text-blue-950 font-black">الحالية</th>
                <th className="py-3 px-2 min-w-[85px] bg-amber-200/70 text-amber-950 text-center font-black">
                  الاستهلاك
                </th>

                <th className="py-3 px-2 min-w-[75px] font-black">سعر الوحدة</th>
                <th className="py-3 px-2.5 min-w-[95px] text-slate-950 font-black">قيمة الاستهلاك</th>
                <th className="py-3 px-2 min-w-[75px] font-black">رسوم خدمة</th>

                {/* Highlighted Arrears Column */}
                <th className="py-3 px-2.5 min-w-[110px] bg-rose-100/90 text-rose-950 border-x-2 border-rose-400 text-center font-black">
                  المتأخرات (تعديل مباشر)
                </th>

                <th className="py-3 px-3 min-w-[110px] bg-emerald-100/90 text-emerald-950 font-black">
                  إجمالي المستحق
                </th>
                {!hidePaidColumn && <th className="py-3 px-2.5 min-w-[95px] text-blue-900 font-black">المدفوع</th>}
                {!hideRemainingColumn && <th className="py-3 px-2.5 min-w-[105px] text-slate-950 font-black">المتبقي</th>}
                {!hidePreviewColumn && <th className="py-3 px-1 text-center w-14 font-black">معاينة</th>}
                {!hideActionsColumn && extraRowActions && <th className="py-3 px-2 text-center font-black">إجراءات</th>}
                {!hideDeleteColumn && <th className="py-3 px-1 text-center w-12 font-black">حذف</th>}
                {actionColumnPosition === 'end' && (
                  <th className="py-3 px-3 min-w-[125px] text-emerald-900 text-center bg-emerald-100/90 border-b-2 border-emerald-400 font-black">
                    الإرسال والاعتماد
                  </th>
                )}
                  {enableRowSelection && (
                    <th className="py-3 px-2 w-10 text-center bg-purple-100 text-purple-950 font-black border-b-2 border-purple-400 sticky left-0 z-20">
                      <input 
                        type="checkbox" 
                        className="w-4 h-4 cursor-pointer accent-purple-600 rounded"
                        checked={filteredRows.length > 0 && selectedRowIds.length === filteredRows.length}
                        onChange={handleSelectAll}
                        title="تحديد الكل"
                      />
                    </th>
                  )}
              </tr>
            </thead>

            {/* Table Body */}
            <tbody className="divide-y divide-slate-200 text-slate-700">
              {isLoading ? (
                <tr>
                  <td colSpan={24} className="py-12 text-center text-slate-500 font-semibold">
                    جاري تحميل سجل العمليات والبيانات...
                  </td>
                </tr>
              ) : filteredRows.length === 0 ? (
                <tr>
                  <td colSpan={24} className="py-12 text-center text-slate-500 font-semibold">
                    {emptyMessage}
                  </td>
                </tr>
              ) : (
                filteredRows.map((row, index) => {
                  const paidNum = Number(row.paidAmount || 0);
                  const remainingNum = Number(row.remaining !== undefined && row.remaining !== null ? row.remaining : (row.totalDue || 0));
                  const isPaidInFull = row.status === 'Paid' || (paidNum > 0 && remainingNum <= 0);
                  const isPartiallyPaid = !isPaidInFull && paidNum > 0 && remainingNum > 0;
                  const isInvoiceSentOrPrinted = !isPaidInFull && !isPartiallyPaid && (Boolean(row.sent) || Boolean(row.isPrinted) || Boolean(row.printed) || row.status === 'Sent' || row.status === 'Invoiced');

                  let rowBgClass = 'bg-white hover:bg-slate-50 text-slate-900 border-b border-slate-200';
                  if (isPaidInFull) {
                    rowBgClass = 'bg-emerald-100/80 hover:bg-emerald-200/90 text-emerald-950 font-bold border-b border-emerald-300';
                  } else if (isInvoiceSentOrPrinted) {
                    rowBgClass = 'bg-blue-100/80 hover:bg-blue-200/90 text-blue-950 font-bold border-b border-blue-300';
                  } else if (isPartiallyPaid) {
                    rowBgClass = 'bg-emerald-50/70 hover:bg-emerald-100/80 text-slate-900 border-b border-emerald-200';
                  }

                  return (
                    <tr
                      key={row.id}
                      className={`transition-colors duration-150 ${rowBgClass}`}
                    >
                      {/* # Serial Index */}
                      <td className="py-2 px-1 text-center text-slate-400 font-mono text-[11px] border-l border-slate-200">
                        {index + 1}
                      </td>

                      {/* Send / Approve WhatsApp (Start Position) */}
                      {actionColumnPosition === 'start' && (
                        <td className="py-1 px-1.5 text-center border-l border-slate-200 bg-emerald-50/30">
                          <button
                            onClick={() => handleDirectWhatsApp(row)}
                            className={`w-full inline-flex items-center justify-center gap-1 py-1 px-2 rounded-md text-xs font-bold transition-all shadow-sm ${
                              row.sent || row.approvalStatus === 'APPROVED'
                                ? 'bg-emerald-700 hover:bg-emerald-800 text-white'
                                : 'bg-emerald-600 hover:bg-emerald-700 text-white'
                            }`}
                            title="إرسال فاتورة معتمدة عبر الواتساب"
                          >
                            <Send className="w-3 h-3 transform -rotate-45" />
                            <span>معتمد</span>
                          </button>
                        </td>
                      )}

                      {/* Sub Number */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'subNumber', row.subNumber) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="numeric"
                          value={row.subNumber || ''}
                          onFocus={handleInputFocus}
                          onChange={(e) => handleCellChange(row.id, 'subNumber', toEnglishDigits(e.target.value))}
                          onBlur={(e) => handleCellBlur(row.id, 'subNumber', toEnglishDigits(e.target.value))}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'subNumber', row.subNumber)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-xs shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-900 font-bold text-xs'
                          }
                        />
                      </td>

                      {/* Route */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 text-center font-mono ${isCellModified(row.id, 'route', row.route) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          value={row.route || ''}
                          onFocus={handleInputFocus}
                          onChange={(e) => handleCellChange(row.id, 'route', toEnglishDigits(e.target.value))}
                          onBlur={(e) => handleCellBlur(row.id, 'route', toEnglishDigits(e.target.value))}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'route', row.route)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1 py-1 focus:outline-none text-center text-xs shadow-xs'
                              : 'w-full bg-transparent px-1 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-center text-slate-900 font-bold text-xs'
                          }
                        />
                      </td>

                      {/* Name */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 ${isCellModified(row.id, 'name', row.name) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          value={row.name || ''}
                          onFocus={handleInputFocus}
                          onChange={(e) => handleCellChange(row.id, 'name', e.target.value)}
                          onBlur={(e) => handleCellBlur(row.id, 'name', e.target.value)}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'name', row.name)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-[13px] shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-950 font-bold text-[13px]'
                          }
                        />
                      </td>

                      {/* Address */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 ${isCellModified(row.id, 'address', row.address) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          value={row.address || ''}
                          onFocus={handleInputFocus}
                          onChange={(e) => handleCellChange(row.id, 'address', e.target.value)}
                          onBlur={(e) => handleCellBlur(row.id, 'address', e.target.value)}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'address', row.address)
                              ? 'w-full bg-amber-100 text-amber-950 font-bold border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-xs shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-800 text-xs'
                          }
                        />
                      </td>

                      {/* Meter Number */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'meterNumber', row.meterNumber) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="numeric"
                          value={row.meterNumber || ''}
                          onFocus={handleInputFocus}
                          onChange={(e) => handleCellChange(row.id, 'meterNumber', toEnglishDigits(e.target.value))}
                          onBlur={(e) => handleCellBlur(row.id, 'meterNumber', toEnglishDigits(e.target.value))}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'meterNumber', row.meterNumber)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-xs shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-900 font-bold text-xs'
                          }
                        />
                      </td>

                      {/* Phone */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'phone', row.phone) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="numeric"
                          value={row.phone || ''}
                          onFocus={handleInputFocus}
                          onChange={(e) => handleCellChange(row.id, 'phone', toEnglishDigits(e.target.value))}
                          onBlur={(e) => handleCellBlur(row.id, 'phone', toEnglishDigits(e.target.value))}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'phone', row.phone)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-xs shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-900 font-bold text-xs'
                          }
                        />
                      </td>

                      {/* Prev Reading */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'prevReading', row.prevReading) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="decimal"
                          value={formatRawBlankZero(row.prevReading)}
                          onFocus={handleInputFocus}
                          onChange={(e) => {
                            const clean = sanitizeDecimalInput(e.target.value);
                            handleCellChange(row.id, 'prevReading', clean);
                          }}
                          onBlur={(e) => {
                            const clean = sanitizeDecimalInput(e.target.value);
                            const num = clean === '' || Number.isNaN(Number(clean)) ? 0 : Number(clean);
                            handleCellBlur(row.id, 'prevReading', num);
                          }}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'prevReading', row.prevReading)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-amber-950 text-left font-black text-[13px] shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-amber-500 text-amber-950 text-left font-black text-[13px]'
                          }
                        />
                      </td>

                      {/* Curr Reading */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'currReading', row.currReading) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="decimal"
                          value={formatRawBlankZero(row.currReading)}
                          onFocus={handleInputFocus}
                          onChange={(e) => {
                            const clean = sanitizeDecimalInput(e.target.value);
                            handleCellChange(row.id, 'currReading', clean);
                          }}
                          onBlur={(e) => {
                            const clean = sanitizeDecimalInput(e.target.value);
                            const num = clean === '' || Number.isNaN(Number(clean)) ? 0 : Number(clean);
                            handleCellBlur(row.id, 'currReading', num);
                          }}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'currReading', row.currReading)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-amber-950 text-left font-black text-[13px] shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-blue-500 text-blue-950 text-left font-black text-[13px]'
                          }
                        />
                      </td>

                      {/* Units */}
                      <td className="py-1.5 px-2 border-l border-slate-200 text-center font-mono font-black text-[13px] bg-amber-100/50 text-amber-950">
                        {row.units > 0 ? row.units.toLocaleString('en-US') : ''}
                      </td>

                      {/* Unit Price */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'unitPrice', row.unitPrice) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="decimal"
                          value={formatInputNumberBlankZero(row.unitPrice)}
                          onFocus={handleInputFocus}
                          onChange={(e) => {
                            const clean = parseFormattedNumber(e.target.value);
                            handleCellChange(row.id, 'unitPrice', clean);
                          }}
                          onBlur={(e) => {
                            const clean = parseFormattedNumber(e.target.value);
                            handleCellBlur(row.id, 'unitPrice', clean);
                          }}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'unitPrice', row.unitPrice)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-amber-950 text-left font-bold text-xs shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-900 font-bold text-left text-xs'
                          }
                        />
                      </td>

                      {/* Consumption Cost */}
                      <td className="py-1.5 px-2.5 border-l border-slate-200 text-left font-mono font-black text-[13px] text-slate-950">
                        {row.consumptionCost > 0 ? row.consumptionCost.toLocaleString('en-US') : ''}
                      </td>

                      {/* Service Fee */}
                      <td className={`py-0.5 px-1 border-l border-slate-200 font-mono ${isCellModified(row.id, 'serviceFee', row.serviceFee) ? 'bg-amber-50' : ''}`}>
                        <input
                          type="text"
                          inputMode="decimal"
                          value={formatInputNumberBlankZero(row.serviceFee)}
                          onFocus={handleInputFocus}
                          onChange={(e) => {
                            const clean = parseFormattedNumber(e.target.value);
                            handleCellChange(row.id, 'serviceFee', clean);
                          }}
                          onBlur={(e) => {
                            const clean = parseFormattedNumber(e.target.value);
                            handleCellBlur(row.id, 'serviceFee', clean);
                          }}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'serviceFee', row.serviceFee)
                              ? 'w-full bg-amber-100 text-amber-950 font-black border border-amber-400 ring-1 ring-amber-400/60 rounded px-1.5 py-1 focus:outline-none text-amber-950 text-left font-bold text-xs shadow-xs'
                              : 'w-full bg-transparent px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-emerald-500 text-slate-900 font-bold text-left text-xs'
                          }
                        />
                      </td>

                      {/* Arrears */}
                      <td className={`py-0.5 px-1 border-x-2 border-rose-300 font-mono ${isCellModified(row.id, 'arrears', row.arrears) ? 'bg-amber-100' : 'bg-rose-50/40'}`}>
                        <input
                          type="text"
                          inputMode="decimal"
                          value={formatInputNumberBlankZero(row.arrears)}
                          onFocus={handleInputFocus}
                          onChange={(e) => {
                            const clean = parseFormattedNumber(e.target.value);
                            handleCellChange(row.id, 'arrears', clean);
                          }}
                          onBlur={(e) => {
                            const clean = parseFormattedNumber(e.target.value);
                            handleCellBlur(row.id, 'arrears', clean);
                          }}
                          onKeyDown={handleKeyDown}
                          className={
                            isCellModified(row.id, 'arrears', row.arrears)
                              ? 'w-full bg-amber-200 text-amber-950 font-black border border-amber-500 ring-2 ring-amber-400 rounded px-1.5 py-1 focus:outline-none text-amber-950 text-left font-black text-[13px] shadow-xs'
                              : 'w-full bg-rose-50/60 text-rose-950 border border-rose-300 px-1.5 py-1 rounded focus:bg-white focus:outline-none focus:ring-1 focus:ring-rose-500 text-left font-black text-[13px]'
                          }
                        />
                      </td>

                      {/* Total Due */}
                      <td className="py-1.5 px-3 border-l border-slate-200 text-left font-mono font-black text-[13px] bg-emerald-100/70 text-emerald-950">
                        {row.totalDue !== 0 ? (row.totalDue > 0 ? row.totalDue.toLocaleString('en-US') : `-${Math.abs(row.totalDue).toLocaleString('en-US')}`) : ''}
                      </td>

                      {/* Paid Amount (Read-Only Display) */}
                      {!hidePaidColumn && (
                        <td className="py-1.5 px-2.5 border-l border-slate-200 text-left font-mono font-black text-[13px] text-blue-950">
                          {Number(row.paidAmount || 0) > 0 ? Number(row.paidAmount).toLocaleString('en-US') : ''}
                        </td>
                      )}

                      {/* Remaining Balance */}
                      {!hideRemainingColumn && (
                        <td
                          className={`py-1.5 px-2.5 border-l border-slate-200 text-left font-mono font-black text-[13px] ${
                            row.remaining > 0 ? 'text-rose-950' : (row.remaining < 0 ? 'text-emerald-800 font-black' : 'text-slate-500')
                          }`}
                        >
                          {row.remaining !== 0 ? (row.remaining > 0 ? row.remaining.toLocaleString('en-US') : `-${Math.abs(row.remaining).toLocaleString('en-US')}`) : ''}
                        </td>
                      )}

                      {/* Eye Preview Button */}
                      {!hidePreviewColumn && (
                        <td className="py-1 px-1 text-center border-l border-slate-200">
                          <button
                            onClick={() => setSelectedInvoiceRow(row)}
                            className="p-1 text-slate-400 hover:text-slate-700 hover:bg-slate-200 rounded transition-colors"
                            title="معاينة تفاصيل الفاتورة"
                          >
                            <Eye className="w-4 h-4" />
                          </button>
                        </td>
                      )}

                      {/* Extra Actions if any */}
                      {!hideActionsColumn && extraRowActions && (
                        <td className="py-1 px-1 text-center border-l border-slate-200">
                          {extraRowActions(row)}
                        </td>
                      )}

                      {/* Delete Button */}
                      {!hideDeleteColumn && (
                        <td className="py-1 px-1 text-center">
                          <button
                            onClick={() => setPendingDeleteRow(row)}
                            className="p-1 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded transition-colors"
                            title="حذف المشترك"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </td>
                      )}

                      {/* Send / Approve WhatsApp (End Position) */}
                      {actionColumnPosition === 'end' && (
                        <td className="py-1 px-1.5 text-center border-l border-slate-200 bg-emerald-50/40 whitespace-nowrap">
                          <div className="flex items-center justify-center gap-1.5">
                            {/* 1. Direct "اعتمادية" button */}
                            <button
                              onClick={() => {
                                setLocalRows((prev) => prev.filter((r) => r.id !== row.id));
                                onApproveAndSend?.(row);
                              }}
                              className="inline-flex items-center justify-center gap-1 py-1 px-2.5 rounded-lg text-xs font-bold transition-all shadow-xs bg-emerald-600 hover:bg-emerald-700 text-white"
                              title="اعتمادية الفاتورة والترحيل المباشر إلى كشف فواتير الطاقة والتحصيل"
                            >
                              <Check className="w-3.5 h-3.5" />
                              <span>اعتمادية</span>
                            </button>

                            {/* 2. "الفاتورة" button to open modal (preview, print, WhatsApp) */}
                            <button
                              onClick={() => {
                                if (onPreviewInvoice) onPreviewInvoice(row);
                                else setSelectedInvoiceRow(row);
                              }}
                              className="inline-flex items-center justify-center gap-1 py-1 px-2.5 rounded-lg text-xs font-bold transition-all shadow-xs bg-blue-600 hover:bg-blue-700 text-white"
                              title="معاينة الفاتورة وإرسالها واتساب أو طباعتها"
                            >
                              <FileText className="w-3.5 h-3.5" />
                              <span>الفاتورة</span>
                            </button>
                          </div>
                        </td>
                      )}
                        {/* Row Selection Checkbox (End Position - Far Left in RTL) */}
                        {enableRowSelection && (
                          <td className="py-2 px-1 text-center bg-purple-50/50 sticky left-0 z-10 border-l border-slate-200">
                            <input 
                              type="checkbox" 
                              className="w-4 h-4 cursor-pointer accent-purple-600 rounded"
                              checked={selectedRowIds.includes(row.id)}
                              onChange={(e) => handleSelectRow(row.id, e.target.checked)}
                            />
                          </td>
                        )}
                    </tr>
                  );
                })
              )}
            </tbody>

            {/* Sticky Table Footer */}
            <tfoot className="bg-slate-200 text-slate-900 font-bold border-t-2 border-b-2 border-slate-400 sticky bottom-0 z-10 select-none">
              <tr className="divide-x divide-x-reverse divide-slate-300">
                <td colSpan={actionColumnPosition === 'start' ? 10 : 9} className="py-2.5 px-3 text-center text-xs font-black text-slate-900">
                  الإجمالي العام لعدد ({totals.visibleCount.toLocaleString('en-US')}) مشترك
                </td>
                <td className="py-2.5 px-2 text-center text-amber-950 font-mono font-black text-[13px] bg-amber-100/50">
                  {totals.totalUnitsSum > 0 ? totals.totalUnitsSum.toLocaleString('en-US') : ''}
                </td>

                <td colSpan={2} className="py-2.5 px-2 text-left text-slate-800 font-sans font-bold text-xs">
                  مجموع الاستحقاق العام:
                </td>
                <td></td>
                <td className="py-2.5 px-2 text-rose-950 font-mono font-black text-[13px] bg-rose-100/40 text-left">
                  {totals.totalArrearsSum !== 0 ? (totals.totalArrearsSum > 0 ? totals.totalArrearsSum.toLocaleString('en-US') : `-${Math.abs(totals.totalArrearsSum).toLocaleString('en-US')}`) : ''}
                </td>
                <td className="py-2.5 px-2.5 text-emerald-950 font-mono font-black text-[13px] bg-emerald-100/70 text-left">
                  {totals.totalDueSum !== 0 ? (totals.totalDueSum > 0 ? totals.totalDueSum.toLocaleString('en-US') : `-${Math.abs(totals.totalDueSum).toLocaleString('en-US')}`) : ''}
                </td>
                {!hidePaidColumn && (
                  <td className="py-2.5 px-2.5 text-blue-950 font-mono font-black text-[13px] text-left">
                    {totals.totalPaidSum > 0 ? totals.totalPaidSum.toLocaleString('en-US') : ''}
                  </td>
                )}
                {!hideRemainingColumn && (
                  <td className={`py-2.5 px-2.5 font-mono font-black text-[13px] text-left ${totals.totalRemainingSum < 0 ? 'text-emerald-800' : 'text-rose-950'}`}>
                    {totals.totalRemainingSum !== 0 
                      ? (totals.totalRemainingSum > 0 ? totals.totalRemainingSum.toLocaleString('en-US') : `-${Math.abs(totals.totalRemainingSum).toLocaleString('en-US')}`) 
                      : ''}
                  </td>
                )}
                {(() => {
                  let trailingCols = 0;
                  if (!hidePreviewColumn) trailingCols++;
                  if (!hideActionsColumn && extraRowActions) trailingCols++;
                  if (!hideDeleteColumn) trailingCols++;
                  if (actionColumnPosition === 'end') trailingCols++;
                    if (enableRowSelection) trailingCols++;
                  return trailingCols > 0 ? <td colSpan={trailingCols}></td> : null;
                })()}
              </tr>
            </tfoot>
          </table>
        </div>
      </div>

      {/* 5. Built-in Invoice Preview Modal */}
      <InvoiceModal
        isOpen={Boolean(selectedInvoiceRow)}
        onClose={() => setSelectedInvoiceRow(null)}
        row={selectedInvoiceRow}
        period={period}
        onSendSuccess={(id: number) => {
          setLocalRows((prev) =>
            prev.map((r) => (r.id === id ? { ...r, sent: true, approvalStatus: 'APPROVED' } : r))
          );
        }}
      />

      {/* 6. Built-in Delete Confirmation Modal */}
      {pendingDeleteRow && (
        <div className="fixed inset-0 bg-slate-900/50 z-50 flex items-center justify-center p-4 backdrop-blur-xs">
          <div className="bg-white border border-slate-200 max-w-xs w-full p-4 rounded-xl shadow-xl text-center">
            <AlertCircle className="w-10 h-10 text-rose-500 mx-auto mb-2" />
            <h3 className="font-bold text-slate-800 text-sm">تأكيد حذف المشترك</h3>
            <p className="text-xs text-slate-500 mt-1">
              هل أنت متأكد من رغبتك في حذف ({pendingDeleteRow.name}) نهائياً من كشف الفواتير؟
            </p>
            <div className="flex gap-2 mt-4">
              <button
                onClick={handleConfirmDelete}
                className="flex-1 py-1.5 bg-rose-600 hover:bg-rose-700 text-white text-xs font-bold rounded-lg transition-colors"
              >
                نعم، احذف
              </button>
              <button
                onClick={() => setPendingDeleteRow(null)}
                className="flex-1 py-1.5 bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-medium rounded-lg transition-colors"
              >
                إلغاء
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 7. Centered Historical Billing Cycle Warning Modal */}
      {showHistoricalWarningModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-950/75 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white rounded-2xl shadow-2xl border border-amber-200 max-w-lg w-full p-6 text-right space-y-4 animate-in zoom-in-95 duration-150">
            {/* Header & Icon */}
            <div className="flex items-start gap-3.5">
              <div className="p-3 bg-amber-100 text-amber-900 rounded-2xl border border-amber-300 shadow-sm shrink-0">
                <AlertTriangle className="w-8 h-8 text-amber-600" />
              </div>
              <div>
                <h3 className="text-base sm:text-lg font-extrabold text-slate-900">
                  تنبيه إداري ومحاسبي: تعديل دورة سابقة مغلقة
                </h3>
                <div className="inline-flex items-center gap-1.5 mt-1 px-3 py-0.5 rounded-full bg-purple-100 text-purple-900 border border-purple-200 text-xs font-bold">
                  <span>الدورة المحددة:</span>
                  <span className="font-extrabold font-mono">{period}</span>
                </div>
              </div>
            </div>

            {/* Warning Explanation Body */}
            <div className="bg-amber-50/90 border border-amber-200/90 rounded-xl p-4 text-xs text-amber-950 space-y-2.5 leading-relaxed">
              <div className="flex items-center gap-2 font-bold text-amber-900 text-xs sm:text-sm">
                <ShieldAlert className="w-4 h-4 text-amber-600 shrink-0" />
                <span>أنت على وشك تعديل بيانات في دورة سابقة مغلقة ومرحلة.</span>
              </div>
              <p>
                يرجى العلم بأن تعديل أي قيمة (سواء <strong>المتأخرات</strong>، <strong>القراءات</strong>، أو <strong>المبالغ المسددة</strong>) سيؤدي تلقائياً إلى <strong>إعادة احتساب رجعي متسلسل (Retroactive Cascade)</strong> لجميع الفواتير والأرصدة اللاحقة لهذا المشترك حتى الدورة الحالية، وذلك لضمان تطابق السلسلة المحاسبية وتفادي ازدواجية المطالبات.
              </p>
              <p className="text-slate-600 font-semibold bg-white/70 p-2 rounded-lg border border-amber-100">
                لكتابة تأكيد فك القفل، يرجى كتابة العبارة التالية أدناه: <strong className="text-amber-800 font-extrabold select-all">تأكيد التعديل</strong>
              </p>
            </div>

            {/* Confirmation Text Input */}
            <div className="pt-1">
              <input
                type="text"
                value={historicalConfirmInput}
                onChange={(e) => setHistoricalConfirmInput(e.target.value)}
                placeholder="اكتب هنا: تأكيد التعديل"
                className="w-full px-3 py-2 border border-slate-300 rounded-xl text-xs font-bold text-slate-900 focus:ring-2 focus:ring-amber-500 focus:outline-none"
              />
            </div>

            {/* Modal Actions */}
            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => {
                  setShowHistoricalWarningModal(false);
                  setHistoricalConfirmInput('');
                }}
                className="px-4 py-2.5 rounded-xl border border-slate-300 text-slate-700 hover:bg-slate-100 font-bold text-xs transition-colors"
              >
                إلغاء الأمر
              </button>
              <button
                type="button"
                disabled={historicalConfirmInput.trim() !== 'تأكيد التعديل'}
                onClick={() => {
                  if (period) {
                    setUnlockedPeriods((prev) => new Set(prev).add(period));
                  }
                  setShowHistoricalWarningModal(false);
                  setHistoricalConfirmInput('');
                  toast.success(`تم فك قفل التعديل لدورة (${period}) بنجاح. يمكنك التعديل الآن وسيتولى النظام التحديث التتابعي.`);
                }}
                className={`px-5 py-2.5 rounded-xl text-white font-bold text-xs transition-all flex items-center gap-1.5 ${
                  historicalConfirmInput.trim() === 'تأكيد التعديل'
                    ? 'bg-amber-600 hover:bg-amber-700 shadow-md shadow-amber-500/20 cursor-pointer'
                    : 'bg-slate-300 text-slate-500 cursor-not-allowed opacity-70'
                }`}
              >
                <CheckCircle2 className="w-4 h-4" />
                <span>موافق - فك القفل والمتابعة</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
