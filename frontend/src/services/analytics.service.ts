import api from '../lib/api';
import { formatCycleName } from '../utils/cycleUtils';

export interface MonthlyPerformanceItem {
  month: string;
  billing_cycle: string;
  totalBilled: number;
  totalCollected: number;
  totalRemaining: number;
  collectionRate: number;
  invoiceCount: number;
  sortIndex?: number;
}

export const getMonthlyPerformance = async (): Promise<MonthlyPerformanceItem[]> => {
  try {
    const res = await api.get('/analytics/monthly-performance');
    if (res.data?.success && Array.isArray(res.data.data)) {
      const mergedMap = new Map<string, MonthlyPerformanceItem>();

      res.data.data.forEach((item: any) => {
        const rawCycle = item.billing_cycle || item.month || '';
        const displayName = formatCycleName(rawCycle) || rawCycle;
        const totalBilled = Number(item.total_billed ?? item.totalBilled ?? item.billed ?? 0);
        const totalCollected = Number(item.total_collected ?? item.totalCollected ?? item.collected ?? 0);
        const totalRemaining = Number(item.total_remaining ?? item.totalRemaining ?? item.remaining ?? Math.max(0, totalBilled - totalCollected));
        const invoiceCount = Number(item.invoice_count ?? item.invoiceCount ?? 0);
        const sortIndex = Number(item.sort_index ?? 0);

        if (mergedMap.has(displayName)) {
          const existing = mergedMap.get(displayName)!;
          existing.totalBilled += totalBilled;
          existing.totalCollected += totalCollected;
          existing.totalRemaining += totalRemaining;
          existing.invoiceCount += invoiceCount;
          existing.collectionRate = existing.totalBilled > 0 
            ? Math.round((existing.totalCollected / existing.totalBilled) * 10000) / 100 
            : 0;
          if (sortIndex > 0 && !existing.sortIndex) existing.sortIndex = sortIndex;
        } else {
          const rate = totalBilled > 0 ? (totalCollected / totalBilled) * 100 : 0;
          mergedMap.set(displayName, {
            month: displayName,
            billing_cycle: rawCycle,
            totalBilled,
            totalCollected,
            totalRemaining,
            collectionRate: Math.round(rate * 100) / 100,
            invoiceCount,
            sortIndex,
          });
        }
      });

      return Array.from(mergedMap.values()).sort((a, b) => (a.sortIndex || 0) - (b.sortIndex || 0));
    }
  } catch (e) {
    console.warn('Failed to load monthly performance from API:', e);
  }
  return [];
};

export const getOverdueReport = async (category: string = 'all', route: string = 'all', region: string = 'all') => {
  try {
    const res = await api.get('/analytics/overdue-report', {
      params: { category, route, region }
    });
    if (res.data?.success && Array.isArray(res.data.data)) {
      let defaulters = res.data.data.map((record: any) => {
        const rawDaysOverdue = Number(record.days_overdue) || 0;
        const daysOverdue = Math.max(0, Math.floor(rawDaysOverdue));
        let overdueCategory = daysOverdue <= 0 ? 'not_due' : '1-30_days';
        if (daysOverdue > 60) overdueCategory = '60_plus_days';
        else if (daysOverdue > 30) overdueCategory = '31-60_days';

        const cust = record.customer || record.Customer || {};
        return {
          customer: {
            id: cust.id || record.customer_id,
            full_name: cust.full_name || record.full_name || 'مشترك',
            subscriber_number: cust.subscriber_number || record.subscriber_number || '',
            phone_number: cust.phone_number || record.phone_number || '',
            meter_number: cust.meter_number || record.meter_number || '',
            route_number: cust.route_number || record.route_number || '',
            address: cust.address || record.region || '',
            plan_name: cust.subscription_plan?.plan_name || record.plan_name || 'باقة سكنية',
            initial_reading: cust.initial_reading || record.previous_reading || 0,
            status: cust.status || 'ACTIVE',
            total_due: Number(record.remaining_amount || record.total_due || record.total_arrears || 0),
            remaining_amount: Number(record.remaining_amount || record.total_due || record.total_arrears || 0),
            arrears: Number(record.arrears || record.total_arrears || 0),
          },
          previous_reading: record.previous_reading !== null && record.previous_reading !== undefined ? Number(record.previous_reading) : '-',
          current_reading: record.current_reading !== null && record.current_reading !== undefined ? Number(record.current_reading) : '-',
          consumption: record.consumption !== null && record.consumption !== undefined ? Number(record.consumption) : 0,
          total_arrears: Number(record.remaining_amount || record.total_due || record.total_arrears || 0),
          days_overdue: daysOverdue,
          category: overdueCategory,
        };
      });

      if (category && category !== 'all') {
        if (category === '30') defaulters = defaulters.filter((d: any) => d.days_overdue <= 30);
        if (category === '60') defaulters = defaulters.filter((d: any) => d.days_overdue > 30 && d.days_overdue <= 60);
        if (category === '90') defaulters = defaulters.filter((d: any) => d.days_overdue > 60);
      }

      return defaulters.sort((a: any, b: any) => b.total_arrears - a.total_arrears);
    }
  } catch (e) {
    console.warn('Failed to load overdue report from API:', e);
  }
  return [];
};

export const getDashboardSummary = async () => {
  try {
    const res = await api.get('/analytics/dashboard-summary');
    if (res.data?.success && res.data.data) {
      const data = res.data.data;
      const kpis = Array.isArray(data.collectorKPIs) ? data.collectorKPIs : (Array.isArray(data) ? data : []);
      let colIndex = 1;
      const collectorCodeMap = new Map<string, string>();

      const collectorKPIs = kpis.map((c: any) => {
        const target = 50;
        const completionRate = c.readings > 0 ? Math.min(100, Math.round((c.readings / target) * 100)) : 0;
        if (!collectorCodeMap.has(c.collector_name || c.name)) {
          collectorCodeMap.set(c.collector_name || c.name, `COL-${String(colIndex++).padStart(2, '0')}`);
        }
        const code = collectorCodeMap.get(c.collector_name || c.name) || 'COL-01';
        return {
          code: `#${code}`,
          name: c.collector_name || c.name || 'محصل',
          readings: c.readings || 0,
          cash: c.cash || 0,
          customersPaidCount: c.customers_paid || c.customersPaidCount || 0,
          completionRate,
        };
      });

      return { collectorKPIs };
    }
  } catch (e) {
    console.warn('Failed to load dashboard summary from API:', e);
  }
  return { collectorKPIs: [] };
};

export const getRecentTransactions = async () => {
  try {
    const res = await api.get('/analytics/dashboard-summary');
    if (res.data?.success && Array.isArray(res.data?.data?.liveFeed)) {
      return res.data.data.liveFeed;
    }
  } catch {}
  return [];
};

export const getPendingTransactions = async () => {
  try {
    const res = await api.get('/analytics/dashboard-summary');
    if (res.data?.success && Array.isArray(res.data?.data?.liveFeed)) {
      return res.data.data.liveFeed.filter((item: any) =>
        item.approval_status === 'PENDING' || item.approval_status === 'PENDING_REVIEW'
      );
    }
  } catch {}
  return [];
};

export const getRoutesProgress = async () => {
  try {
    const res = await api.get('/analytics/routes-progress');
    if (res.data?.success && Array.isArray(res.data.data)) {
      return res.data.data.map((item: any) => ({
        route: item.route || item.route_number,
        total: item.total_customers || item.total_count || 0,
        read: item.read_customers || item.read_count || 0,
        percentage: item.percentage || item.progress_pct || 0,
      }));
    }
  } catch (e) {
    console.warn('Failed to load routes progress from API:', e);
  }
  return [];
};

// Mutations
export const approveReadingApi = async (id: number) => {
  try {
    const res = await api.post(`/readings/approve/${id}`);
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل اعتماد القراءة');
  }
};

export const rejectReadingApi = async (id: number, reason: string) => {
  try {
    const res = await api.post(`/readings/reject/${id}`, { reason });
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل رفض القراءة');
  }
};

export const approvePaymentApi = async (id: number) => {
  try {
    const res = await api.post(`/payments/approve/${id}`);
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل اعتماد السداد');
  }
};

export const rejectPaymentApi = async (id: number, reason: string) => {
  try {
    const res = await api.post(`/payments/reject/${id}`, { reason });
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل رفض السداد');
  }
};

export const approveAllPendingApi = async () => {
  try {
    const res = await api.post('/readings/approve-all');
    return res.data;
  } catch (err: any) {
    throw new Error(err.response?.data?.message || err.message || 'فشل الاعتماد الجماعي');
  }
};
