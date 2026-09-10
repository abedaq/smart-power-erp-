/**
 * Centralized formatting utilities.
 * All functions guarantee English (Latin) numerals (0-9) — no Eastern Arabic digits (٠-٩).
 */

/**
 * Format a date/time string with English numerals.
 * Output example: "08/20/2026, 01:18 PM"
 */
export function formatDate(date: Date | string): string {
  return new Date(date).toLocaleString('en-US', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: true,
  });
}

/**
 * Format a date-only string with English numerals.
 * Output example: "08/20/2026"
 */
export function formatDateOnly(date: Date | string): string {
  return new Date(date).toLocaleDateString('en-US', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
}

/**
 * Arabic month names (manually defined to avoid locale-generated Eastern Arabic digits).
 */
const ARABIC_MONTHS = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/**
 * Format month + year with Arabic month name and English year numeral.
 * Output example: "أغسطس 2026"
 */
export function formatMonth(date: Date | string): string {
  const d = new Date(date);
  return `${ARABIC_MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/**
 * Format a number with English thousand-separators.
 * Output example: "28,500"
 */
export function formatNumber(value: number | string): string {
  return Number(value).toLocaleString('en-US');
}

/**
 * Format a currency amount (YER) with English numerals.
 * Output example: "28,500.00"
 */
export function formatCurrency(value: number | string): string {
  return Number(value).toLocaleString('en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  });
}

/**
 * Convert Eastern Arabic numerals (٠-٩) and Persian numerals (۰-۹) to standard Western English digits (0-9).
 */
export function toEnglishDigits(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  return String(val)
    .replace(/[\u0660-\u0669]/g, (d) => (d.charCodeAt(0) - 1632).toString())
    .replace(/[\u06F0-\u06F9]/g, (d) => (d.charCodeAt(0) - 1776).toString());
}

/**
 * Backward compatibility alias for toEnglishDigits.
 */
export function normalizeNumerals(str: string | number | null | undefined): string {
  return toEnglishDigits(str);
}

/**
 * Sanitize decimal input for amounts, readings, rates, fees, arrears:
 * Converts Eastern digits -> English digits -> preserves leading negative '-' -> allows only (0-9 and single decimal dot).
 */
export function sanitizeDecimalInput(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  const eng = toEnglishDigits(val).trim();
  const isNegative = eng.startsWith('-');
  // Strip thousands separators (English comma and Arabic thousands separator \u066C)
  const noSeparators = eng.replace(/[\u066C,]/g, '');
  // Arabic decimal separator \u066B or Arabic comma \u060C mapped to decimal dot
  const withDots = noSeparators.replace(/[\u066B\u060C]/g, '.').replace(/[^0-9.]/g, '');
  const parts = withDots.split('.');
  let result = withDots;
  if (parts.length > 2) {
    result = parts[0] + '.' + parts.slice(1).join('');
  }
  return isNegative && result !== '' ? '-' + result : result;
}

/**
 * Sanitize integer / digit-only input (subscriber numbers, phone numbers, meter numbers):
 * Converts Eastern digits -> English digits -> allows only (0-9).
 */
export function sanitizeIntegerInput(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  return toEnglishDigits(val).replace(/[^0-9]/g, '');
}

/**
 * Formats a money value or string with thousands commas (e.g. 34,434,344 or -20,000).
 * Always outputs English digits with standard comma grouping. Returns '' if 0 or empty.
 */
export function formatMoneyWithCommas(val: unknown): string {
  if (val === null || val === undefined || val === '') return '';
  const str = String(val).trim();
  const isNegative = str.startsWith('-');
  const clean = sanitizeDecimalInput(str).replaceAll(',', '').replace(/^-/, '');
  const num = Number(clean);
  if (Number.isNaN(num) || num === 0) return '';
  return (isNegative ? '-' : '') + num.toLocaleString('en-US');
}

/**
 * Formats a dynamic input field value with commas while the user types,
 * preserving decimals, negative signs, and incomplete typing states.
 */
export function formatInputAsCurrency(val: string | number | null | undefined): string {
  if (val === null || val === undefined || val === '') return '';
  const raw = sanitizeDecimalInput(val);
  const isNegative = raw.startsWith('-');
  const cleanRaw = isNegative ? raw.slice(1) : raw;
  const parts = cleanRaw.split('.');
  const integerPart = parts[0];
  const decimalPart = parts.length > 1 ? '.' + parts[1] : '';
  if (integerPart === '') return decimalPart ? (isNegative ? '-0' : '0') + decimalPart : (isNegative ? '-' : '');
  const num = Number(integerPart);
  if (Number.isNaN(num)) return raw;
  return (isNegative ? '-' : '') + num.toLocaleString('en-US') + decimalPart;
}

/**
 * Formats a dynamic input field value with commas while typing,
 * but returns an empty string "" if the value is 0, '0', null, or undefined,
 * allowing placeholder="0" to show cleanly without forcing '0' into user inputs.
 * Preserves negative values (e.g. -20,000).
 */
export function formatInputNumberBlankZero(val: string | number | null | undefined): string {
  if (val === null || val === undefined || val === '' || val === 0 || val === '0' || Number(val) === 0) return '';
  return formatInputAsCurrency(val);
}

/**
 * Format a number with English thousand-separators, returning empty string "" if 0, null, or undefined.
 * Preserves negative numbers (e.g. -20,000).
 */
export function formatBlankZeroNumber(value: number | string | null | undefined): string {
  if (value === null || value === undefined || value === '' || value === 0 || value === '0') return '';
  const num = typeof value === 'number' ? value : Number(toEnglishDigits(String(value)).replaceAll(',', '').trim());
  if (Number.isNaN(num) || num === 0) return '';
  return num < 0 ? `-${Math.abs(num).toLocaleString('en-US')}` : num.toLocaleString('en-US');
}

/**
 * Returns empty string "" if the raw numeric/string value is 0, '0', null, or undefined,
 * otherwise returns the clean decimal string value. Preserves negative values (e.g. -20000).
 */
export function formatRawBlankZero(val: string | number | null | undefined): string {
  if (val === null || val === undefined || val === '' || val === 0 || val === '0' || Number(val) === 0) return '';
  return String(val);
}

/**
 * Parses a comma-separated formatted number string back to a pure numeric value,
 * preserving negative signs (e.g. "-20,000" -> -20000).
 */
export function parseFormattedNumber(val: unknown): number {
  if (val === null || val === undefined || val === '') return 0;
  const str = String(val).trim();
  const isNegative = str.startsWith('-');
  const clean = str.replaceAll(',', '').replace(/[^0-9.]/g, '');
  const num = Number(clean);
  if (Number.isNaN(num)) return 0;
  return isNegative ? -num : num;
}

/**
 * Universal UUID v4 generator with RFC4122 fallback for insecure HTTP contexts (e.g. mobile LAN IP).
 */
export function generateUUID(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    try {
      return crypto.randomUUID();
    } catch {
      // Fallback if crypto.randomUUID fails in non-secure context
    }
  }

  // RFC4122 v4 compliant fallback generator
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Universal clipboard copy helper with execCommand fallback for insecure HTTP contexts on mobile.
 */
export async function safeCopyToClipboard(text: string): Promise<boolean> {
  if (typeof navigator !== 'undefined' && navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // Fallback to execCommand if clipboard API fails
    }
  }

  if (typeof document !== 'undefined') {
    try {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.left = '-999999px';
      textArea.style.top = '-999999px';
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();
      const successful = document.execCommand('copy');
      document.body.removeChild(textArea);
      return successful;
    } catch (e) {
      console.error('safeCopyToClipboard fallback failed', e);
      return false;
    }
  }
  return false;
}

/**
 * Format station phone numbers to guarantee "783270260 _ 736955883" header presentation.
 */
export function formatStationPhones(phone1?: string, phone2?: string): string {
  const clean = (p?: string) => {
    if (!p) return '';
    return toEnglishDigits(p)
      .replace(/\+967|00967|^0+/g, '')
      .replace(/[\s\-_]+/g, '')
      .trim();
  };

  const p1 = clean(phone1);
  const p2 = clean(phone2);

  if (phone1 && phone1.includes('_')) {
    const parts = phone1.split('_').map((p) => clean(p)).filter(Boolean);
    if (parts.length === 2) {
      return `${parts[0]} _ ${parts[1]}`;
    }
  }

  if (p1 && p2 && p1 !== p2) {
    return `${p1} _ ${p2}`;
  }
  if (p1 === '783270260' || (p1.includes('783270260') && p1.includes('736955883'))) {
    return '783270260 _ 736955883';
  }
  if (p1) return p1;
  if (p2) return p2;
  return '783270260 _ 736955883';
}

/**
 * Clean bank account string to pure account number if prefix is present.
 */
export function formatBankAccount(bankStr?: string): string {
  if (!bankStr || !bankStr.trim()) return '3052001225';
  const cleanStr = toEnglishDigits(bankStr).trim();
  const lastColon = cleanStr.lastIndexOf(':');
  if (lastColon !== -1) {
    const num = cleanStr.slice(lastColon + 1).trim();
    if (num) return num;
  }
  return cleanStr;
}
