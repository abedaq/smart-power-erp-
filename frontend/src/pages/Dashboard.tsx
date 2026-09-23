import React, { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useDebouncedRealtime } from '../utils/debouncedRealtime';
import { 
  getMonthlyPerformance, 
  type MonthlyPerformanceItem 
} from '../services/analytics.service';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { useAuth } from '../context/AuthContext';
import { Navigate, Link } from 'react-router-dom';
import { 
  TrendingUp, 
  Banknote, 
  CheckCircle2, 
  Clock, 
  BarChart3, 
  Layers, 
  Calendar,
  ArrowUpRight
} from 'lucide-react';

const Dashboard: React.FC = () => {
  const { user } = useAuth();
  const [viewMode, setViewMode] = useState<'due_only' | 'all'>('due_only');

  const { data: performance = [], isLoading: isLoadingPerf } = useQuery<MonthlyPerformanceItem[]>({
    queryKey: ['monthly-performance'],
    queryFn: getMonthlyPerformance,
    staleTime: 5 * 60 * 1000,
  });

  // Strict 2-second debounced realtime subscription
  const realtimeConfigs = useMemo(
    () => [
      {
        channelName: 'dashboard_page:readings',
        table: 'meter_readings',
        queryKeysToInvalidate: [['monthly-performance']],
        debounceMs: 2000,
      },
      {
        channelName: 'dashboard_page:payments',
        table: 'payments',
        queryKeysToInvalidate: [['monthly-performance']],
        debounceMs: 2000,
      },
      {
        channelName: 'dashboard_page:invoices',
        table: 'invoices',
        queryKeysToInvalidate: [['monthly-performance']],
        debounceMs: 2000,
      },
    ],
    []
  );

  useDebouncedRealtime(realtimeConfigs);

  // Compute current cycle sort index based on real-world system date
  const currentCycleSortIndex = useMemo(() => {
    const now = new Date();
    const year = now.getFullYear();
    const monthIdx = now.getMonth(); // 0-indexed (8 = September)
    const cycleNum = now.getDate() <= 15 ? 1 : 2;
    return (year * 24) + (monthIdx * 2) + cycleNum;
  }, []);

  // Filter for past & current active cycles strictly
  const activePerformance = useMemo(() => {
    return performance.filter((p) => (p.sortIndex || 0) <= currentCycleSortIndex);
  }, [performance, currentCycleSortIndex]);

  // Future cycles
  const futurePerformance = useMemo(() => {
    return performance.filter((p) => (p.sortIndex || 0) > currentCycleSortIndex);
  }, [performance, currentCycleSortIndex]);

  // Performance items displayed in chart and table
  const displayedPerformance = viewMode === 'due_only' ? activePerformance : performance;

  // Aggregate financial metrics STRICTLY for current and past cycles (excluding future cycles)
  const financialTotals = useMemo(() => {
    let totalBilled = 0;
    let totalCollected = 0;
    let totalRemaining = 0;
    let totalInvoices = 0;

    activePerformance.forEach((p) => {
      totalBilled += p.totalBilled || 0;
      totalCollected += p.totalCollected || 0;
      totalRemaining += p.totalRemaining || 0;
      totalInvoices += p.invoiceCount || 0;
    });

    const overallRate = totalBilled > 0 ? (totalCollected / totalBilled) * 100 : 0;

    return {
      totalBilled,
      totalCollected,
      totalRemaining,
      totalInvoices,
      overallRate: Math.round(overallRate * 10) / 10,
      activeCyclesCount: activePerformance.length,
      futureCyclesCount: futurePerformance.length,
    };
  }, [activePerformance, futurePerformance]);

  if (user?.role === 'COLLECTOR') {
    return <Navigate to="/invoices" replace />;
  }

  if (user?.role === 'ACCOUNTANT') {
    return <Navigate to="/invoices" replace />;
  }

  return (
    <div className="space-y-6 pb-12">
      {/* Header */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 bg-white p-6 rounded-2xl border border-slate-200 shadow-sm">
        <div>
          <div className="flex items-center gap-2">
            <span className="p-2 rounded-xl bg-blue-50 text-blue-600 border border-blue-100">
              <BarChart3 size={24} />
            </span>
            <div>
              <h1 className="text-2xl font-bold text-slate-900 tracking-tight">
                شاشة التحصيل الشهري والمتابعة المالية
              </h1>
              <p className="text-slate-500 text-xs sm:text-sm font-medium mt-0.5">
                متابعة حركة المديونيات والمبالغ المحصلة ونسب التحصيل لجميع الدورات المحاسبية
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <Link
            to="/invoices"
            className="flex items-center gap-2 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2.5 rounded-xl text-sm font-bold shadow-md shadow-blue-500/20 transition-all hover:scale-[1.02]"
          >
            <span>جدول الفواتير والتحصيل</span>
            <ArrowUpRight size={16} />
          </Link>
          <Link
            to="/arrears"
            className="flex items-center gap-2 bg-slate-100 hover:bg-slate-200 text-slate-700 px-4 py-2.5 rounded-xl text-sm font-bold border border-slate-200 transition-all"
          >
            <span>تقرير المتأخرات</span>
          </Link>
        </div>
      </div>

      {/* 4 Financial KPI Summary Cards */}
      <div>
        <div className="flex justify-between items-center mb-3">
          <div className="flex items-center gap-2">
            <span className="text-xs font-bold text-slate-700 bg-blue-50 border border-blue-200 text-blue-800 px-3 py-1 rounded-xl">
              المؤشرات المالية الإجمالية (حتى الدورة الحالية والدورات السابقة - {financialTotals.activeCyclesCount} دورة)
            </span>
            {financialTotals.futureCyclesCount > 0 && (
              <span className="text-[11px] text-slate-400 font-medium">
                (تم استبعاد {financialTotals.futureCyclesCount} دورة قادمة تلقائياً)
              </span>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* Total Billed / Dues */}
          <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm relative overflow-hidden group hover:border-blue-300 transition-all">
            <div className="flex justify-between items-start">
              <div>
                <span className="text-xs font-bold text-slate-500 block mb-1">إجمالي المستحق والمديونية</span>
                <div className="text-2xl font-black text-slate-900 font-mono tracking-tight">
                  {financialTotals.totalBilled.toLocaleString('en-US')} <span className="text-xs font-normal text-slate-500">ر.ي</span>
                </div>
              </div>
              <div className="p-3 bg-blue-50 text-blue-600 rounded-xl border border-blue-100 group-hover:scale-110 transition-transform">
                <Banknote size={22} />
              </div>
            </div>
            <div className="mt-3 flex items-center justify-between text-xs text-slate-500 border-t border-slate-100 pt-2.5 font-medium">
              <span>الفواتير الصادرة المستحقة</span>
              <span className="font-mono font-bold text-slate-700">{financialTotals.totalInvoices.toLocaleString('en-US')} فاتورة</span>
            </div>
          </div>

          {/* Total Collected */}
          <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm relative overflow-hidden group hover:border-emerald-300 transition-all">
            <div className="flex justify-between items-start">
              <div>
                <span className="text-xs font-bold text-slate-500 block mb-1">إجمالي المبالغ المحصلة</span>
                <div className="text-2xl font-black text-emerald-600 font-mono tracking-tight">
                  {financialTotals.totalCollected.toLocaleString('en-US')} <span className="text-xs font-normal text-slate-500">ر.ي</span>
                </div>
              </div>
              <div className="p-3 bg-emerald-50 text-emerald-600 rounded-xl border border-emerald-100 group-hover:scale-110 transition-transform">
                <CheckCircle2 size={22} />
              </div>
            </div>
            <div className="mt-3 flex items-center justify-between text-xs text-slate-500 border-t border-slate-100 pt-2.5 font-medium">
              <span>المحصل النقدي الفعلي</span>
              <span className="font-mono font-bold text-emerald-700">سندات مقبوضة</span>
            </div>
          </div>

          {/* Total Remaining / Arrears */}
          <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm relative overflow-hidden group hover:border-amber-300 transition-all">
            <div className="flex justify-between items-start">
              <div>
                <span className="text-xs font-bold text-slate-500 block mb-1">المتبقي غير المحصل</span>
                <div className="text-2xl font-black text-amber-600 font-mono tracking-tight">
                  {financialTotals.totalRemaining.toLocaleString('en-US')} <span className="text-xs font-normal text-slate-500">ر.ي</span>
                </div>
              </div>
              <div className="p-3 bg-amber-50 text-amber-600 rounded-xl border border-amber-100 group-hover:scale-110 transition-transform">
                <Clock size={22} />
              </div>
            </div>
            <div className="mt-3 flex items-center justify-between text-xs text-slate-500 border-t border-slate-100 pt-2.5 font-medium">
              <span>المتبقي بالذمة حتى اليوم</span>
              <span className="font-mono font-bold text-amber-700">
                {financialTotals.totalBilled > 0 
                  ? `${Math.round((financialTotals.totalRemaining / financialTotals.totalBilled) * 100)}% من المستحق` 
                  : '0%'}
              </span>
            </div>
          </div>

          {/* Overall Collection Rate */}
          <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm relative overflow-hidden group hover:border-purple-300 transition-all">
            <div className="flex justify-between items-start">
              <div>
                <span className="text-xs font-bold text-slate-500 block mb-1">نسبة التحصيل العامة</span>
                <div className="text-2xl font-black text-purple-700 font-mono tracking-tight">
                  {financialTotals.overallRate}%
                </div>
              </div>
              <div className="p-3 bg-purple-50 text-purple-600 rounded-xl border border-purple-100 group-hover:scale-110 transition-transform">
                <TrendingUp size={22} />
              </div>
            </div>
            {/* Progress bar */}
            <div className="mt-3.5 w-full bg-slate-100 rounded-full h-2 overflow-hidden border border-slate-200">
              <div 
                className={`h-full transition-all duration-700 rounded-full ${
                  financialTotals.overallRate >= 80 ? 'bg-emerald-600' :
                  financialTotals.overallRate >= 50 ? 'bg-blue-600' : 'bg-amber-500'
                }`}
                style={{ width: `${Math.min(100, Math.max(0, financialTotals.overallRate))}%` }}
              ></div>
            </div>
          </div>
        </div>
      </div>

      {/* Main Full-Width Monthly Performance Chart Section */}
      <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-sm">
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-6 pb-4 border-b border-slate-100">
          <div>
            <h2 className="text-lg font-black text-slate-900 flex items-center gap-2">
              <BarChart3 className="text-blue-600" size={20} />
              مخطط التحصيل والمطالبات حسب الدورات المحاسبية
            </h2>
            <p className="text-xs text-slate-500 mt-0.5">
              مقارنة بيانية مباشرة بين إجمالي المستحق والمبالغ المحصلة فعلياً لكل دورة
            </p>
          </div>

          {/* Filter tabs */}
          <div className="flex items-center gap-2 bg-slate-100 p-1 rounded-xl border border-slate-200 text-xs font-bold">
            <button
              onClick={() => setViewMode('due_only')}
              className={`px-3 py-1.5 rounded-lg transition-all ${
                viewMode === 'due_only'
                  ? 'bg-white text-blue-700 shadow-sm font-black'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              الدورات المستحقة فقط ({activePerformance.length})
            </button>
            <button
              onClick={() => setViewMode('all')}
              className={`px-3 py-1.5 rounded-lg transition-all ${
                viewMode === 'all'
                  ? 'bg-white text-blue-700 shadow-sm font-black'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              كافة الدورات ({performance.length})
            </button>
          </div>
        </div>

        {/* Bar Chart Container */}
        <div className="h-72 sm:h-80 w-full" dir="ltr">
          {isLoadingPerf ? (
            <div className="h-full w-full flex items-center justify-center text-slate-400 text-sm">
              جاري تحميل بيانات المخطط...
            </div>
          ) : displayedPerformance.length === 0 ? (
            <div className="h-full w-full flex items-center justify-center text-slate-400 text-sm">
              لا توجد بيانات دورات محاسبية مستحقة حالياً
            </div>
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={displayedPerformance} margin={{ top: 15, right: 20, left: 20, bottom: 10 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#F1F5F9" vertical={false} />
                <XAxis 
                  dataKey="month" 
                  stroke="#64748B" 
                  tick={{ fill: '#475569', fontSize: 12, fontWeight: 'bold' }} 
                />
                <YAxis 
                  stroke="#64748B" 
                  tick={{ fill: '#64748B', fontSize: 11 }}
                  tickFormatter={(v) => `${Number(v).toLocaleString('en-US')}`}
                />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: '#0F172A', 
                    borderColor: '#1E293B', 
                    borderRadius: '0.75rem', 
                    color: '#FFF',
                    fontSize: '12px',
                    direction: 'rtl',
                    textAlign: 'right'
                  }} 
                  formatter={(value: any, name: any) => {
                    const num = Number(value || 0).toLocaleString('en-US');
                    const label = name === 'totalBilled' ? 'إجمالي المستحق' : 'المحصل الفعلي';
                    return [`${num} ر.ي`, label];
                  }}
                  labelFormatter={(label) => `الدورة: ${label}`}
                />
                <Bar dataKey="totalBilled" name="totalBilled" fill="#2563EB" radius={[6, 6, 0, 0]} maxBarSize={45} />
                <Bar dataKey="totalCollected" name="totalCollected" fill="#059669" radius={[6, 6, 0, 0]} maxBarSize={45} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>

      {/* Detailed Cycle-by-Cycle Breakdown Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
        <div className="p-5 border-b border-slate-200 bg-slate-50/50 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
          <div>
            <h2 className="text-lg font-black text-slate-900 flex items-center gap-2">
              <Layers className="text-blue-600" size={20} />
              تفاصيل حركة التحصيل والمديونيات لكل دورة
            </h2>
            <p className="text-xs text-slate-500 mt-0.5">
              جدول إحصائي تفصيلي يوضح المبالغ المطلوبة والمحصلة ونسب التحصيل الفعلية لكل دورة
            </p>
          </div>
          <span className="text-xs font-mono font-bold bg-white text-slate-700 px-3 py-1.5 rounded-xl border border-slate-200">
            {displayedPerformance.length} دورة معروضة
          </span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-right text-xs sm:text-sm">
            <thead>
              <tr className="bg-slate-100/80 text-slate-700 font-bold border-b border-slate-200">
                <th className="p-4">الدورة المحاسبية</th>
                <th className="p-4 text-center">نوع الدورة</th>
                <th className="p-4 text-center">عدد الفواتير</th>
                <th className="p-4">إجمالي المستحق (المديونية)</th>
                <th className="p-4">المبلغ المحصل</th>
                <th className="p-4">المبلغ المتبقي</th>
                <th className="p-4 text-center">نسبة التحصيل</th>
                <th className="p-4 text-center">حالة التحصيل</th>
                <th className="p-4 text-center">الإجراء</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {displayedPerformance.map((item, idx) => {
                const isFuture = (item.sortIndex || 0) > currentCycleSortIndex;
                const isComplete = item.collectionRate >= 100;
                const isHigh = item.collectionRate >= 80;
                const isMedium = item.collectionRate >= 50;

                return (
                  <tr key={idx} className={`transition-colors font-medium ${isFuture ? 'bg-slate-50/60 opacity-80' : 'hover:bg-blue-50/40'}`}>
                    <td className="p-4 font-bold text-slate-900 flex items-center gap-2">
                      <Calendar size={16} className={isFuture ? 'text-slate-400' : 'text-blue-600'} />
                      <span>{item.month}</span>
                    </td>
                    <td className="p-4 text-center">
                      <span className={`px-2 py-0.5 rounded-md text-[11px] font-bold ${
                        isFuture 
                          ? 'bg-slate-100 text-slate-500 border border-slate-200' 
                          : 'bg-blue-50 text-blue-700 border border-blue-200'
                      }`}>
                        {isFuture ? 'دورة قادمة' : 'مستحقة / حالية'}
                      </span>
                    </td>
                    <td className="p-4 text-center font-mono font-bold text-slate-700">
                      {item.invoiceCount > 0 ? item.invoiceCount.toLocaleString('en-US') : '-'}
                    </td>
                    <td className="p-4 font-mono font-bold text-slate-900">
                      {item.totalBilled.toLocaleString('en-US')} <span className="text-[11px] font-normal text-slate-500">ر.ي</span>
                    </td>
                    <td className="p-4 font-mono font-bold text-emerald-700">
                      {item.totalCollected.toLocaleString('en-US')} <span className="text-[11px] font-normal text-slate-500">ر.ي</span>
                    </td>
                    <td className="p-4 font-mono font-bold text-amber-700">
                      {item.totalRemaining.toLocaleString('en-US')} <span className="text-[11px] font-normal text-slate-500">ر.ي</span>
                    </td>
                    <td className="p-4 text-center font-mono">
                      <div className="flex items-center justify-center gap-2">
                        <span className="font-bold text-slate-800">{item.collectionRate}%</span>
                        <div className="w-16 bg-slate-200 rounded-full h-2 overflow-hidden hidden sm:block">
                          <div 
                            className={`h-full rounded-full ${
                              isComplete ? 'bg-emerald-600' :
                              isHigh ? 'bg-emerald-500' :
                              isMedium ? 'bg-blue-600' : 'bg-amber-500'
                            }`}
                            style={{ width: `${Math.min(100, Math.max(0, item.collectionRate))}%` }}
                          ></div>
                        </div>
                      </div>
                    </td>
                    <td className="p-4 text-center">
                      <span className={`inline-block px-3 py-1 rounded-full text-xs font-bold ${
                        isFuture ? 'bg-slate-100 text-slate-600 border border-slate-300' :
                        isComplete ? 'bg-emerald-100 text-emerald-800 border border-emerald-300' :
                        isHigh ? 'bg-blue-100 text-blue-800 border border-blue-300' :
                        isMedium ? 'bg-amber-100 text-amber-800 border border-amber-300' :
                        'bg-slate-100 text-slate-700 border border-slate-300'
                      }`}>
                        {isFuture ? 'غير مستحقة بعد' :
                         isComplete ? 'مكتمل 100%' :
                         isHigh ? 'تحصيل ممتاز' :
                         isMedium ? 'جاري التحصيل' : 'قيد المتابعة'}
                      </span>
                    </td>
                    <td className="p-4 text-center">
                      <Link
                        to={`/invoices`}
                        className="inline-flex items-center gap-1 text-xs font-bold text-blue-600 hover:text-blue-800 hover:underline bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-xl border border-blue-200 transition-colors"
                      >
                        <span>عرض الفواتير</span>
                        <ArrowUpRight size={14} />
                      </Link>
                    </td>
                  </tr>
                );
              })}

              {displayedPerformance.length === 0 && !isLoadingPerf && (
                <tr>
                  <td colSpan={9} className="p-8 text-center text-slate-400">
                    لا توجد بيانات دورات محاسبية للعرض.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
