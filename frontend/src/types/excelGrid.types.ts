import { toEnglishDigits } from '../utils/formatters.ts';

export interface GridRowData {
  id: number;
  subNumber: string;
  route: string;
  name: string;
  address: string;
  meterNumber: string;
  phone: string;
  prevReading: number | string;
  currReading: number | string;
  unitPrice: number | string;
  serviceFee: number | string;
  arrears: number | string;
  paidAmount: number | string;
  sent?: boolean;
  isPrinted?: boolean;
  printed?: boolean;
  approvalStatus?: 'PENDING' | 'PENDING_REVIEW' | 'APPROVED' | 'REJECTED';
  status?: string;
  overdueDays?: number;
  rawItem?: any;
}

export interface ComputedGridRow extends GridRowData {
  units: number;
  consumptionCost: number;
  totalDue: number;
  remaining: number;
}

export interface GridFooterTotals {
  visibleCount: number;
  totalUnitsSum: number;
  totalArrearsSum: number;
  totalConsumptionCostSum: number;
  totalDueSum: number;
  totalPaidSum: number;
  totalRemainingSum: number;
}

/**
 * Pure calculation of financial values for a single row.
 * Units = Math.max(0, currReading - prevReading)
 * Consumption Cost = Units * Unit Price
 * Total Due = Consumption Cost + Service Fee + Arrears
 * Remaining = Total Due - Paid Amount
 */
export function computeRowFinancials(row: GridRowData): ComputedGridRow {
  const parseNum = (val: unknown): number => {
    if (val === null || val === undefined || val === '') return 0;
    const raw = toEnglishDigits(String(val)).trim();
    if (!raw) return 0;
    const isNeg = raw.startsWith('-');
    const clean = raw.replaceAll(',', '').replace(/[^0-9.]/g, '');
    const num = Number(clean);
    if (Number.isNaN(num)) return 0;
    return isNeg ? -num : num;
  };

  const prev = parseNum(row.prevReading);
  const curr = parseNum(row.currReading);
  const units = Math.max(0, curr - prev);
  const unitPrice = parseNum(row.unitPrice);

  const consumptionCost = units * unitPrice;
  const serviceFee = parseNum(row.serviceFee);
  const arrears = parseNum(row.arrears);

  const totalDue = consumptionCost + serviceFee + arrears;
  const paid = parseNum(row.paidAmount);
  let remaining = totalDue - paid;
  if (row.rawItem && typeof row.rawItem.remaining_amount === 'number') {
    if (totalDue < 0 && row.rawItem.remaining_amount > totalDue) {
      remaining = row.rawItem.remaining_amount;
    } else if (row.status === 'Paid' && remaining < 0) {
      remaining = 0;
    }
  }

  return {
    ...row,
    units,
    consumptionCost,
    totalDue,
    remaining,
  };
}

/**
 * Pure summation of columns for table sticky footer and top KPI cards
 */
export function computeGridTotals(rows: ComputedGridRow[]): GridFooterTotals {
  const parseNum = (val: unknown): number => {
    if (val === null || val === undefined || val === '') return 0;
    const raw = toEnglishDigits(String(val)).trim();
    if (!raw) return 0;
    const isNeg = raw.startsWith('-');
    const clean = raw.replaceAll(',', '').replace(/[^0-9.]/g, '');
    const num = Number(clean);
    if (Number.isNaN(num)) return 0;
    return isNeg ? -num : num;
  };

  return rows.reduce(
    (acc, row) => ({
      visibleCount: acc.visibleCount + 1,
      totalUnitsSum: acc.totalUnitsSum + parseNum(row.units),
      totalArrearsSum: acc.totalArrearsSum + parseNum(row.arrears),
      totalConsumptionCostSum: acc.totalConsumptionCostSum + parseNum(row.consumptionCost),
      totalDueSum: acc.totalDueSum + parseNum(row.totalDue),
      totalPaidSum: acc.totalPaidSum + parseNum(row.paidAmount),
      totalRemainingSum: acc.totalRemainingSum + parseNum(row.remaining),
    }),
    {
      visibleCount: 0,
      totalUnitsSum: 0,
      totalArrearsSum: 0,
      totalConsumptionCostSum: 0,
      totalDueSum: 0,
      totalPaidSum: 0,
      totalRemainingSum: 0,
    }
  );
}

/**
 * Clean and format Yemeni phone numbers to international wa.me standard (9677xxxxxxxx)
 */
export function formatYemeniPhone(rawPhone: string | number | null | undefined): string {
  let phone = toEnglishDigits(String(rawPhone || '')).replace(/\D/g, '').trim();
  if (phone.startsWith('00967')) phone = phone.substring(5);
  if (phone.startsWith('967')) phone = phone.substring(3);
  if (phone.startsWith('0')) phone = phone.substring(1);
  return phone ? `967${phone}` : '';
}

/**
 * Generates the official formatted WhatsApp message for a subscriber invoice matching code_artifact (8).html
 */
export function buildWhatsAppText(row: ComputedGridRow, period: string = 'الشهر الحالي'): string {
  const formatNum = (val: unknown): string => {
    if (val === null || val === undefined || val === '') return '0';
    const raw = toEnglishDigits(String(val)).trim();
    if (!raw) return '0';
    const isNeg = raw.startsWith('-');
    const clean = raw.replaceAll(',', '').replace(/[^0-9.]/g, '');
    const num = Number(clean);
    if (Number.isNaN(num)) return '0';
    return (isNeg ? '-' : '') + num.toLocaleString('en-US');
  };

  const prevStr = formatNum(row.prevReading);
  const currStr = formatNum(row.currReading);
  const unitsStr = formatNum(row.units);
  const unitPriceStr = formatNum(row.unitPrice);
  const consumptionCostStr = formatNum(row.consumptionCost);
  const serviceFeeStr = formatNum(row.serviceFee);
  const arrearsStr = formatNum(row.arrears);
  const totalDueStr = formatNum(row.totalDue);
  const paidStr = formatNum(row.paidAmount);
  const remainingStr = formatNum(row.remaining);

  return `*فاتورة استهلاك الطاقة الكهربائية*
*الحالة:* معتمد وموثق
----------------------------------------
*المشترك:* ${row.name || '--'}
*رقم الاشتراك:* ${row.subNumber || '--'}
*رقم العداد:* ${row.meterNumber || '--'}
*العنوان:* ${row.address || '--'}
*الفترة:* ${period}
----------------------------------------
*القراءة السابقة:* ${prevStr}
*القراءة الحالية:* ${currStr}
*كمية الاستهلاك:* ${unitsStr} ك.و
*سعر الوحدة:* ${unitPriceStr} ريال
----------------------------------------
*قيمة الاستهلاك:* ${consumptionCostStr} ريال
*رسوم الخدمة:* ${serviceFeeStr} ريال
*المتأخرات السابقة:* ${arrearsStr} ريال
----------------------------------------
*إجمالي المستحق:* ${totalDueStr} ريال
*المبلغ المدفوع:* ${paidStr} ريال
*المبلغ المتبقي:* ${remainingStr} ريال
----------------------------------------
شكراً لتعاونكم وسرعة السداد.`;
}

/**
 * Builds the official warning notice message formatted for Yemeni subscribers
 */
export function buildWarningNoticeText(item: any): string {
  const name = item.customer?.full_name || '--';
  const subNum = item.customer?.subscriber_number || '--';
  const meterNum = item.customer?.meter_number || '--';
  const address = item.customer?.address || '--';
  const rawArrears = Number(toEnglishDigits(String(item.total_arrears || '0')).trim());
  const arrearsNum = (Number.isNaN(rawArrears) ? 0 : rawArrears).toLocaleString('en-US');
  const rawDays = Number(toEnglishDigits(String(item.days_overdue || '0')).trim());
  const days = Math.max(0, Number.isNaN(rawDays) ? 0 : rawDays).toLocaleString('en-US');

  return `*إشعار إنذار رسمي بالسداد وفصل الخدمة*
*الحالة:* إنذار عاجل نهائي
----------------------------------------
*المشترك:* ${name}
*رقم الاشتراك:* ${subNum}
*رقم العداد:* ${meterNum}
*العنوان:* ${address}
----------------------------------------
*مدة التأخير:* ${days} يوماً
*إجمالي المديونية المتأخرة:* ${arrearsNum} ريال يمني
----------------------------------------
*تنبيه عاجل:* نرجو منكم سرعة مراجعة مركز التحصيل لتسديد المتأخرات المترتبة عليكم خلال 48 ساعة لتجنب فصل التيار الكهربائي عن العداد وتحمل رسوم إعادة الإطلاق وتطبيق الغرامات المقررة.
----------------------------------------
شاكرين حسن تعاونكم وحرصكم على استمرار الخدمة.`;
}


/**
 * Export grid rows to UTF-8 BOM CSV for flawless Excel compatibility
 */
export function exportGridToCSV(
  rows: ComputedGridRow[],
  period: string = 'فواتير',
  filenamePrefix: string = 'كشف_فواتير'
): void {
  const headers = [
    'رقم المشترك',
    'خط السير',
    'اسم المشترك',
    'العنوان',
    'رقم العداد',
    'رقم الهاتف',
    'القراءة السابقة',
    'القراءة الحالية',
    'الوحدات المستهلكة',
    'سعر الوحدة',
    'قيمة الاستهلاك',
    'رسوم الخدمة',
    'المتأخرات',
    'إجمالي المستحق',
    'المدفوع',
    'المتبقي',
  ];

  const csvRows = rows.map((r) => [
    r.subNumber,
    r.route,
    `"${(r.name || '').replaceAll('"', '""')}"`,
    `"${(r.address || '').replaceAll('"', '""')}"`,
    r.meterNumber,
    r.phone,
    r.prevReading,
    r.currReading,
    r.units,
    r.unitPrice,
    r.consumptionCost,
    r.serviceFee,
    r.arrears,
    r.totalDue,
    r.paidAmount,
    r.remaining,
  ]);

  const csvContent =
    'data:text/csv;charset=utf-8,\uFEFF' +
    [headers.join(','), ...csvRows.map((e) => e.join(','))].join('\n');

  const encodedUri = encodeURI(csvContent);
  const link = document.createElement('a');
  link.setAttribute('href', encodedUri);
  const safePeriod = period.replace(/[/\\?%*:|"<>]/g, '_').replace(/\s+/g, '_');
  link.setAttribute('download', `${filenamePrefix}_${safePeriod}.csv`);
  document.body.appendChild(link);
  link.click();
  link.remove();
}
