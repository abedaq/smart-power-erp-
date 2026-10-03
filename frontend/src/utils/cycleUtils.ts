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
    let trimmed = dateOrCycleStr.trim();
    trimmed = trimmed.replace(/^شهر\s+/, '');
    
    // Check if format is like "أغسطس- 2 - 2026" or "أغسطس 1" or "يناير 1 - 2027"
    const arabicMatch = trimmed.match(/^([\u0600-\u06FF]+)[-\s]+([12])(?:\b|[-\s]+(\d{4}))/);
    if (arabicMatch) {
      const monthName = arabicMatch[1].replace(/[-_]/g, '').trim();
      const cycleNum = arabicMatch[2];
      const year = arabicMatch[3];
      if (year) {
        return `${monthName} ${cycleNum} - ${year}`;
      }
      return `${monthName} ${cycleNum}`;
    }

    // Check if format is "YYYY-MM-1" / "YYYY-MM-15" or "YYYY-MM-A" / "YYYY-MM-B"
    const cycleMatch = trimmed.match(/^(\d{4})-(\d{2})(?:-([12]|A|B|15|30))?$/i);
    if (cycleMatch) {
      const year = cycleMatch[1];
      const monthIdx = parseInt(cycleMatch[2], 10) - 1;
      const monthName = ARABIC_MONTHS[monthIdx] || `شهر ${cycleMatch[2]}`;
      const suffix = cycleMatch[3];
      let cycleNum = 1;
      if (suffix === '2' || suffix?.toUpperCase() === 'B' || suffix === '30') {
        cycleNum = 2;
      }
      if (year && year !== '2026') {
        return `${monthName} ${cycleNum} - ${year}`;
      }
      return `${monthName} ${cycleNum}`;
    }

    // Check ISO Date string e.g. 2026-08-20T...
    const parsedDate = new Date(trimmed);
    if (!isNaN(parsedDate.getTime())) {
      const monthName = ARABIC_MONTHS[parsedDate.getMonth()];
      const cycleNum = parsedDate.getDate() <= 15 ? 1 : 2;
      const year = parsedDate.getFullYear();
      if (year !== 2026) {
        return `${monthName} ${cycleNum} - ${year}`;
      }
      return `${monthName} ${cycleNum}`;
    }
  }

  if (dateOrCycleStr instanceof Date && !isNaN(dateOrCycleStr.getTime())) {
    const monthName = ARABIC_MONTHS[dateOrCycleStr.getMonth()];
    const cycleNum = dateOrCycleStr.getDate() <= 15 ? 1 : 2;
    const year = dateOrCycleStr.getFullYear();
    if (year !== 2026) {
      return `${monthName} ${cycleNum} - ${year}`;
    }
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

  const yearA = fmtA.match(/\b(20\d{2})\b/)?.[1] || (String(cycleA).match(/\b(20\d{2})\b/)?.[1] ?? '2026');
  const yearB = fmtB.match(/\b(20\d{2})\b/)?.[1] || (String(cycleB).match(/\b(20\d{2})\b/)?.[1] ?? '2026');

  if (yearA !== yearB) {
    return false;
  }

  const normA = normalizeMonth(fmtA).replace(/\s+/g, '');
  const normB = normalizeMonth(fmtB).replace(/\s+/g, '');

  if (normA === normB) return true;

  const rawA = normalizeMonth(String(cycleA)).replace(/[\s\-_]/g, '');
  const rawB = normalizeMonth(String(cycleB)).replace(/[\s\-_]/g, '');

  return rawA === rawB;
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

  // Create CycleOption objects ONLY for cycles that actually exist in the invoices
  map.forEach((count, label) => {
    // Attempt to parse the month and year from the label to create the code and sort info
    let monthIndex = 1;
    let cycleNum = 1;
    let year = 2026;

    const cleanLabel = label.replace(/^شهر\s*/, '').trim();
    const match = cleanLabel.match(/^([\u0600-\u06FF]+)\s+([12])(?:\s*-\s*(\d{4}))?/);
    if (match) {
      const mName = normalizeMonth(match[1]);
      const found = standardMonths.find(m => normalizeMonth(m.name) === mName);
      if (found) monthIndex = found.idx;
      cycleNum = parseInt(match[2], 10);
      if (match[3]) year = parseInt(match[3], 10);
    }

    processedLabels.add(normalizeMonth(label));
    result.push({
      code: `${year}-${String(monthIndex).padStart(2, '0')}-${cycleNum}`,
      label,
      count,
      year,
      monthIndex,
      cycleNum,
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

/**
 * Returns the latest active billing cycle with invoices, or defaults to current date cycle.
 * Ignores empty future cycles (e.g. 2027) unless no other cycles exist.
 */
export function getLatestActiveCycle(cycles: CycleOption[]): string {
  if (!cycles || cycles.length === 0) return formatCycleName(new Date());

  const currentYear = new Date().getFullYear();
  // Filter out future test cycles (e.g. 2027) that have 0 invoices if valid current/past cycles exist
  const validCycles = cycles.filter(c => (c.year || 2026) <= currentYear || c.count > 0);
  const pool = validCycles.length > 0 ? validCycles : cycles;

  const withCount = pool.filter(c => c.count > 0);
  const candidates = withCount.length > 0 ? withCount : pool;

  const sorted = [...candidates].sort((a, b) => {
    const sortA = ((a.year || 2026) * 24) + (((a.monthIndex || 1) - 1) * 2) + (a.cycleNum || 1);
    const sortB = ((b.year || 2026) * 24) + (((b.monthIndex || 1) - 1) * 2) + (b.cycleNum || 1);
    return sortB - sortA;
  });

  return sorted[0]?.label || formatCycleName(new Date());
}

/**
 * Calculates the next consecutive billing cycle label.
 * e.g. "سبتمبر 1" -> "سبتمبر 2", "سبتمبر 2" -> "أكتوبر 1"
 */
export function getNextCycleLabel(currentCycle: string): string {
  const standardMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];
  
  const fmt = formatCycleName(currentCycle);
  const match = fmt.match(/^([\u0600-\u06FF]+)\s+([12])(?:\s*-\s*(\d{4}))?/);
  if (!match) return 'سبتمبر 2';

  const monthName = match[1].trim();
  const cycleNum = parseInt(match[2], 10);
  const year = match[3] ? parseInt(match[3], 10) : 2026;

  let nextMonthName = monthName;
  let nextCycleNum = cycleNum === 1 ? 2 : 1;
  let nextYear = year;

  if (cycleNum === 2) {
    const mIdx = standardMonths.findIndex(m => normalizeMonth(m) === normalizeMonth(monthName));
    if (mIdx === -1 || mIdx === 11) {
      nextMonthName = standardMonths[0]; // يناير
      nextYear = year + 1;
    } else {
      nextMonthName = standardMonths[mIdx + 1];
    }
  }

  if (nextYear !== 2026) {
    return `${nextMonthName} ${nextCycleNum} - ${nextYear}`;
  }
  return `${nextMonthName} ${nextCycleNum}`;
}



