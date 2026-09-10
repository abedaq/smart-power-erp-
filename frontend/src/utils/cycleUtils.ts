import type { Invoice } from '../types';

const ARABIC_MONTHS = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

/**
 * Returns a user-friendly Arabic cycle name (e.g. "أغسطس 1" or "أغسطس 2")
 * based on date string or billing cycle code.
 */
export function formatCycleName(dateOrCycleStr?: string | Date | null): string {
  if (!dateOrCycleStr) {
    const now = new Date();
    const monthName = ARABIC_MONTHS[now.getMonth()];
    const cycleNum = now.getDate() <= 15 ? 1 : 2;
    return `${monthName} ${cycleNum}`;
  }

  if (typeof dateOrCycleStr === 'string') {
    const trimmed = dateOrCycleStr.trim();
    
    // Check if format is like "أغسطس- 2 - 2026" or "أغسطس 1" or "سبتمبر - 2"
    const arabicMatch = trimmed.match(/^([\u0600-\u06FF]+)[-\s]+([12])(?:\b|[-\s]+\d{4})/);
    if (arabicMatch) {
      const monthName = arabicMatch[1].replace(/[-_]/g, '').trim();
      const cycleNum = arabicMatch[2];
      return `${monthName} ${cycleNum}`;
    }

    // Check if format is "YYYY-MM-1" / "YYYY-MM-15" or "YYYY-MM-A" / "YYYY-MM-B"
    const cycleMatch = trimmed.match(/^(\d{4})-(\d{2})(?:-([12]|A|B|15|30))?$/i);
    if (cycleMatch) {
      const monthIdx = parseInt(cycleMatch[2], 10) - 1;
      const monthName = ARABIC_MONTHS[monthIdx] || `شهر ${cycleMatch[2]}`;
      const suffix = cycleMatch[3];
      let cycleNum = 1;
      if (suffix === '2' || suffix?.toUpperCase() === 'B' || suffix === '30') {
        cycleNum = 2;
      }
      return `${monthName} ${cycleNum}`;
    }

    // Check ISO Date string e.g. 2026-08-20T...
    const parsedDate = new Date(trimmed);
    if (!isNaN(parsedDate.getTime())) {
      const monthName = ARABIC_MONTHS[parsedDate.getMonth()];
      const cycleNum = parsedDate.getDate() <= 15 ? 1 : 2;
      return `${monthName} ${cycleNum}`;
    }
  }

  if (dateOrCycleStr instanceof Date && !isNaN(dateOrCycleStr.getTime())) {
    const monthName = ARABIC_MONTHS[dateOrCycleStr.getMonth()];
    const cycleNum = dateOrCycleStr.getDate() <= 15 ? 1 : 2;
    return `${monthName} ${cycleNum}`;
  }

  return String(dateOrCycleStr);
}

export interface CycleOption {
  code: string; // Internal identifier
  label: string; // Human readable e.g. "أغسطس 1" or "يناير 1 - 2027"
  count: number;
  year?: number;
  monthIndex?: number;
  cycleNum?: number;
}

/**
 * Normalizes Arabic month name without diacritics / hamzas for accurate sorting and matching.
 */
export function normalizeMonth(str: string): string {
  if (!str) return '';
  return str
    .replace(/[أإآ]/g, 'ا')
    .replace(/[ة]/g, 'ه')
    .replace(/[ى]/g, 'ي')
    .replace(/^شهر\s*/, '')
    .trim();
}

/**
 * Checks if two cycle identifiers or date strings refer to the exact same billing cycle.
 */
export function isSameCycle(cycleA?: string | null, cycleB?: string | null): boolean {
  if (!cycleA || !cycleB) return false;
  if (cycleA === 'all' || cycleB === 'all') return true;

  const fmtA = formatCycleName(cycleA);
  const fmtB = formatCycleName(cycleB);

  const normA = normalizeMonth(fmtA).replace(/\s+/g, '');
  const normB = normalizeMonth(fmtB).replace(/\s+/g, '');

  if (normA === normB) return true;

  const rawA = normalizeMonth(String(cycleA)).replace(/[\s\-_]/g, '');
  const rawB = normalizeMonth(String(cycleB)).replace(/[\s\-_]/g, '');

  return rawA === rawB || rawA.includes(normB) || rawB.includes(normA);
}

/**
 * Extracts all 15-day semi-monthly billing cycles (past, current, and future)
 * and attaches live invoice counts while preserving strict chronological order across years.
 */
export function getUniqueCyclesFromInvoices(invoices: Invoice[]): CycleOption[] {
  const map = new Map<string, number>();

  invoices.forEach((inv) => {
    let rawCycle = inv.billing_cycle || inv.created_at || new Date().toISOString();
    const label = formatCycleName(rawCycle);
    map.set(label, (map.get(label) || 0) + 1);
  });

  const standardMonths = [
    { name: 'يناير', idx: 1 },
    { name: 'فبراير', idx: 2 },
    { name: 'مارس', idx: 3 },
    { name: 'أبريل', idx: 4 },
    { name: 'مايو', idx: 5 },
    { name: 'يونيو', idx: 6 },
    { name: 'يوليو', idx: 7 },
    { name: 'أغسطس', idx: 8 },
    { name: 'سبتمبر', idx: 9 },
    { name: 'أكتوبر', idx: 10 },
    { name: 'نوفمبر', idx: 11 },
    { name: 'ديسمبر', idx: 12 },
  ];

  const result: CycleOption[] = [];
  const processedLabels = new Set<string>();

  // 1. Build 2026 series (starting from August)
  standardMonths.forEach((m) => {
    if (m.idx >= 8) {
      [1, 2].forEach((cycleNum) => {
        const label = `${m.name} ${cycleNum}`;
        const count = map.get(label) || 0;
        processedLabels.add(normalizeMonth(label));
        result.push({
          code: `2026-${String(m.idx).padStart(2, '0')}-${cycleNum}`,
          label,
          count,
          year: 2026,
          monthIndex: m.idx,
          cycleNum,
        });
      });
    }
  });

  // 2. Build 2027 series (January through December)
  standardMonths.forEach((m) => {
    [1, 2].forEach((cycleNum) => {
      const label = `${m.name} ${cycleNum} - 2027`;
      const count = map.get(label) || map.get(`${m.name} ${cycleNum}`) || 0;
      processedLabels.add(normalizeMonth(label));
      result.push({
        code: `2027-${String(m.idx).padStart(2, '0')}-${cycleNum}`,
        label,
        count,
        year: 2027,
        monthIndex: m.idx,
        cycleNum,
      });
    });
  });

  // 3. Include any additional cycles found in database
  map.forEach((count, rawLabel) => {
    const norm = normalizeMonth(rawLabel);
    if (!processedLabels.has(norm)) {
      let monthIdx = 1;
      let cycleNum = 1;
      let year = 2026;

      const yearMatch = rawLabel.match(/\b(20\d{2})\b/);
      if (yearMatch) {
        year = parseInt(yearMatch[1], 10);
      }

      for (const m of standardMonths) {
        if (norm.includes(normalizeMonth(m.name))) {
          monthIdx = m.idx;
          break;
        }
      }
      const rawWithoutYear = rawLabel.replace(/\b(20\d{2})\b/g, '');
      if (rawWithoutYear.includes('2') || rawWithoutYear.includes('30') || rawWithoutYear.includes('B')) {
        cycleNum = 2;
      }

      processedLabels.add(norm);
      result.push({
        code: rawLabel,
        label: rawLabel,
        count,
        year,
        monthIndex: monthIdx,
        cycleNum,
      });
    }
  });

  // 4. Strict multi-year chronological sorting: (Year * 24) + ((Month - 1) * 2) + cycleNum
  return result.sort((a, b) => {
    const sortA = ((a.year || 2026) * 24) + (((a.monthIndex || 1) - 1) * 2) + (a.cycleNum || 1);
    const sortB = ((b.year || 2026) * 24) + (((b.monthIndex || 1) - 1) * 2) + (b.cycleNum || 1);
    return sortA - sortB;
  });
}

/**
 * Helper to determine if a cycle is a historical/closed cycle.
 * The active window includes the current cycle, next cycle, and directly previous cycle
 * (e.g. أغسطس 2, سبتمبر 1, سبتمبر 2).
 * Cycles older than that (e.g. أغسطس 1, يوليو 2, يوليو 1...) are historical and require warning.
 */
export function isHistoricalBillingCycle(
  cycleLabel?: string,
  allCycles?: CycleOption[] | string[]
): boolean {
  if (!cycleLabel || cycleLabel === 'all') return false;
  const clean = normalizeMonth(cycleLabel);

  if (allCycles && allCycles.length > 0) {
    const stringList = allCycles.map((c) => (typeof c === 'string' ? c : c.label));
    const idx = stringList.findIndex(
      (c) => normalizeMonth(c) === clean || clean.includes(normalizeMonth(c))
    );
    if (idx !== -1) {
      // If it is among the last 3 cycles in the chronological order, it's exempt from warning
      const isOneOfLastThree = idx >= stringList.length - 3;
      return !isOneOfLastThree;
    }
  }

  // Fallback explicit exemption for: سبتمبر 1, سبتمبر 2, اغسطس 2 (الدورة السابقة والحالية والتالية)
  if (
    clean.includes('سبتمبر 1') ||
    clean.includes('سبتمبر 2') ||
    clean.includes('اغسطس 2') ||
    clean.includes('أغسطس 2') ||
    clean.includes('اكتوبر') ||
    clean.includes('أكتوبر') ||
    clean.includes('نوفمبر') ||
    clean.includes('ديسمبر')
  ) {
    return false;
  }

  // Cycles from اغسطس 1 and older are historical
  return true;
}


