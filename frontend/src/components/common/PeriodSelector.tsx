import React, { useEffect, useState, useMemo } from 'react';
import api from '../../lib/api';

export interface BillingCycleOption {
  cycle_name: string;
  invoices_count?: number;
  total_billed?: number;
  total_paid?: number;
  total_remaining?: number;
  total_consumption?: number;
  total_lost_units?: number;
  is_current?: boolean;
  created_at?: string;
}

export interface PeriodSelectorProps {
  currentPeriod: string;
  onPeriodChange: (period: string) => void;
  availablePeriods?: BillingCycleOption[];
  isLoading?: boolean;
  showStats?: boolean;
  compact?: boolean;
  className?: string;
  disabled?: boolean;
}

export const PeriodSelector: React.FC<PeriodSelectorProps> = ({
  currentPeriod,
  onPeriodChange,
  availablePeriods: propPeriods,
  isLoading: propLoading = false,
  showStats = true,
  compact = false,
  className = '',
  disabled = false
}) => {
  const [fetchedPeriods, setFetchedPeriods] = useState<BillingCycleOption[]>([]);
  const [isFetching, setIsFetching] = useState<boolean>(false);

  // Auto-fetch periods if not supplied by parent
  useEffect(() => {
    if (propPeriods && propPeriods.length > 0) return;

    let isMounted = true;
    const loadCycles = async () => {
      setIsFetching(true);
      try {
        const res = await api.get('/readings/cycles');
        if (isMounted && res.data?.success && Array.isArray(res.data.data)) {
          const limitedData = res.data.data.slice(0, 3);
          setFetchedPeriods(limitedData);
          // If currentPeriod not set or not in list, auto-select active cycle
          if (!currentPeriod && limitedData.length > 0) {
            const current = limitedData.find((c: BillingCycleOption) => c.is_current) || limitedData[0];
            onPeriodChange(current.cycle_name);
          }
        }
      } catch (err) {
        console.warn('[PeriodSelector] Failed to fetch cycles from API, using fallback:', err);
        if (isMounted && fetchedPeriods.length === 0) {
          const fallback = [
            { cycle_name: 'سبتمبر 1', is_current: true },
            { cycle_name: 'سبتمبر 2', is_current: false }
          ];
          setFetchedPeriods(fallback);
          if (!currentPeriod) {
            onPeriodChange(fallback[0].cycle_name);
          }
        }
      } finally {
        if (isMounted) setIsFetching(false);
      }
    };

    loadCycles();
    return () => {
      isMounted = false;
    };
  }, [propPeriods, currentPeriod, onPeriodChange]);

  const periods: BillingCycleOption[] = useMemo(() => {
    if (propPeriods && propPeriods.length > 0) {
      return propPeriods;
    }
    return fetchedPeriods;
  }, [propPeriods, fetchedPeriods]);

  const currentIndex = useMemo(() => {
    return periods.findIndex((p) => p.cycle_name === currentPeriod);
  }, [periods, currentPeriod]);

  const currentStats = useMemo(() => {
    if (currentIndex >= 0 && periods[currentIndex]) {
      return periods[currentIndex];
    }
    return null;
  }, [periods, currentIndex]);

  const canGoPrevious = currentIndex < periods.length - 1 && periods.length > 1; // older cycle
  const canGoNext = currentIndex > 0 && periods.length > 1; // newer cycle

  const handlePrevious = () => {
    if (canGoPrevious) {
      onPeriodChange(periods[currentIndex + 1].cycle_name);
    }
  };

  const handleNext = () => {
    if (canGoNext) {
      onPeriodChange(periods[currentIndex - 1].cycle_name);
    }
  };

  const handleJumpToCurrent = () => {
    const current = periods.find((p) => p.is_current) || periods[0];
    if (current && current.cycle_name !== currentPeriod) {
      onPeriodChange(current.cycle_name);
    }
  };

  const isLoading = propLoading || isFetching;

  if (compact) {
    return (
      <div className={`inline-flex items-center gap-1.5 bg-white border border-slate-300 rounded-lg p-1 shadow-sm text-sm ${className}`}>
        <button
          type="button"
          onClick={handleNext}
          disabled={disabled || !canGoNext || isLoading}
          title="الدورة التالية"
          className="p-1 text-slate-500 hover:text-emerald-700 hover:bg-emerald-50 rounded disabled:opacity-30 disabled:hover:bg-transparent"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>

        <select
          value={currentPeriod || ''}
          onChange={(e) => onPeriodChange(e.target.value)}
          disabled={disabled || isLoading}
          className="bg-transparent font-bold text-slate-800 focus:outline-none cursor-pointer text-xs py-0.5 px-1.5"
        >
          {periods.map((p) => (
            <option key={p.cycle_name} value={p.cycle_name}>
              {p.cycle_name} {p.is_current ? '★ (الحالية)' : ''}
            </option>
          ))}
        </select>

        <button
          type="button"
          onClick={handlePrevious}
          disabled={disabled || !canGoPrevious || isLoading}
          title="الدورة السابقة"
          className="p-1 text-slate-500 hover:text-emerald-700 hover:bg-emerald-50 rounded disabled:opacity-30 disabled:hover:bg-transparent"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>
    );
  }

  return (
    <div className={`flex flex-wrap items-center justify-between gap-3 bg-gradient-to-r from-slate-50 via-white to-slate-50 border border-slate-200/80 rounded-xl p-2.5 shadow-sm ${className}`}>
      {/* Right side: Period selector and quick buttons */}
      <div className="flex items-center gap-2">
        <div className="flex items-center justify-center w-8 h-8 rounded-lg bg-emerald-100/80 text-emerald-800 shadow-inner">
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
        </div>

        <div className="flex items-center gap-1 bg-white border border-slate-300 rounded-lg p-0.5 shadow-xs">
          {/* Next (Newer) Button */}
          <button
            type="button"
            onClick={handleNext}
            disabled={disabled || !canGoNext || isLoading}
            title="الدورة الأحدث (التالية)"
            className="p-1.5 text-slate-600 hover:text-emerald-700 hover:bg-emerald-50 rounded-md transition-colors disabled:opacity-30 disabled:hover:bg-transparent"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M15 19l-7-7 7-7" />
            </svg>
          </button>

          {/* Period Dropdown */}
          <div className="relative">
            <select
              value={currentPeriod || ''}
              onChange={(e) => onPeriodChange(e.target.value)}
              disabled={disabled || isLoading}
              className="appearance-none bg-transparent font-bold text-slate-800 text-sm py-1.5 pr-3 pl-8 rounded-md hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 cursor-pointer transition-all"
            >
              {periods.map((p) => (
                <option key={p.cycle_name} value={p.cycle_name} className="py-1">
                  {p.cycle_name} {p.is_current ? '✨ (الدورة الحالية)' : ''}
                </option>
              ))}
            </select>
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center px-2 text-slate-400">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </div>
          </div>

          {/* Previous (Older) Button */}
          <button
            type="button"
            onClick={handlePrevious}
            disabled={disabled || !canGoPrevious || isLoading}
            title="الدورة السابقة (الأقدم)"
            className="p-1.5 text-slate-600 hover:text-emerald-700 hover:bg-emerald-50 rounded-md transition-colors disabled:opacity-30 disabled:hover:bg-transparent"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M9 5l7 7-7 7" />
            </svg>
          </button>
        </div>

        {/* Quick button to current cycle if not currently viewing current */}
        {currentStats && !currentStats.is_current && (
          <button
            type="button"
            onClick={handleJumpToCurrent}
            disabled={disabled || isLoading}
            className="text-xs font-semibold text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 px-2.5 py-1.5 rounded-lg transition-colors flex items-center gap-1 shadow-xs"
          >
            <span>العودة للحالية</span>
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
          </button>
        )}

        {isLoading && (
          <span className="inline-flex items-center text-xs text-slate-400 animate-pulse">
            <svg className="animate-spin h-3.5 w-3.5 text-emerald-600 ml-1" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            جاري التحديث...
          </span>
        )}
      </div>

      {/* Left side: Quick cycle statistics badges (English Numerals) */}
      {showStats && currentStats && (
        <div className="flex items-center gap-2 text-xs flex-wrap">
          {currentStats.invoices_count !== undefined && (
            <div className="bg-slate-100/90 text-slate-700 px-2.5 py-1 rounded-md border border-slate-200/60 font-medium">
              الفواتير: <span className="font-bold text-slate-900">{Number(currentStats.invoices_count).toLocaleString('en-US')}</span>
            </div>
          )}

          {currentStats.total_billed !== undefined && (
            <div className="bg-emerald-50 text-emerald-800 px-2.5 py-1 rounded-md border border-emerald-200/70 font-medium">
              المفوتر: <span className="font-bold">{Number(currentStats.total_billed).toLocaleString('en-US')}</span> ر.ي
            </div>
          )}

          {currentStats.total_remaining !== undefined && (
            <div className="bg-rose-50 text-rose-800 px-2.5 py-1 rounded-md border border-rose-200/70 font-medium">
              المتبقي: <span className="font-bold">{Number(currentStats.total_remaining).toLocaleString('en-US')}</span> ر.ي
            </div>
          )}

          {currentStats.is_current ? (
            <span className="bg-emerald-600 text-white text-[10px] font-bold px-2 py-0.5 rounded-full shadow-xs">
              دورة جارية
            </span>
          ) : (
            <span className="bg-slate-200 text-slate-600 text-[10px] font-bold px-2 py-0.5 rounded-full">
              دورة سابقة
            </span>
          )}
        </div>
      )}
    </div>
  );
};

export default PeriodSelector;
