import { describe, it, expect } from 'vitest';
import {
  formatCurrency,
  formatNumber,
  parseArabicNumber,
  toEnglishDigits,
  sanitizeDecimalInput,
} from '../formatters';

describe('formatCurrency', () => {
  it('formats whole numbers with comma separators in English digits', () => {
    expect(formatCurrency(28500)).toBe('28,500');
    expect(formatCurrency('50000')).toBe('50,000');
  });

  it('formats decimals up to 2 decimal places in English digits', () => {
    expect(formatCurrency(1234.56)).toBe('1,234.56');
    expect(formatCurrency(100.5)).toBe('100.5');
  });

  it('guarantees English numerals only and never outputs Eastern Arabic digits', () => {
    const result = formatCurrency(987654321);
    expect(result).toMatch(/^[0-9,.]+$/);
    expect(result).not.toMatch(/[\u0660-\u0669]/);
  });

  it('handles zero cleanly', () => {
    expect(formatCurrency(0)).toBe('0');
    expect(formatCurrency('0')).toBe('0');
  });
});

describe('formatNumber', () => {
  it('formats numbers with thousands separators', () => {
    expect(formatNumber(1000000)).toBe('1,000,000');
    expect(formatNumber(500)).toBe('500');
  });

  it('handles zero and negative numbers', () => {
    expect(formatNumber(0)).toBe('0');
    expect(formatNumber(-2500)).toBe('-2,500');
  });

  it('ensures output numerals are strictly ASCII Latin digits', () => {
    const result = formatNumber(1234567890);
    expect(result).toBe('1,234,567,890');
    expect(result).not.toMatch(/[\u0660-\u0669\u06F0-\u06F9]/);
  });
});

describe('parseArabicNumber', () => {
  it('converts Eastern Arabic numerals (٠-٩) to standard number', () => {
    expect(parseArabicNumber('١٢٣٤')).toBe(1234);
    expect(parseArabicNumber('٥٠٠٠')).toBe(5000);
    expect(parseArabicNumber('٠')).toBe(0);
  });

  it('converts Persian numerals (۰-۹) to standard number', () => {
    expect(parseArabicNumber('۱۲۳۴')).toBe(1234);
    expect(parseArabicNumber('۵۰۰۰')).toBe(5000);
  });

  it('handles decimal values with dots or Arabic decimal separators', () => {
    expect(parseArabicNumber('١٢٣٤.٥')).toBe(1234.5);
    expect(parseArabicNumber('١٢٣٤٫٥')).toBe(1234.5);
    expect(parseArabicNumber('1234.75')).toBe(1234.75);
  });

  it('handles thousands commas in both English and Arabic notation', () => {
    expect(parseArabicNumber('1,250.50')).toBe(1250.5);
    expect(parseArabicNumber('١٬٢٥٠.٥٠')).toBe(1250.5);
  });

  it('handles negative numbers correctly', () => {
    expect(parseArabicNumber('-٥٠٠')).toBe(-500);
    expect(parseArabicNumber('-1250.75')).toBe(-1250.75);
  });

  it('handles null, undefined, empty string, and whitespace by returning 0', () => {
    expect(parseArabicNumber(null)).toBe(0);
    expect(parseArabicNumber(undefined)).toBe(0);
    expect(parseArabicNumber('')).toBe(0);
    expect(parseArabicNumber('   ')).toBe(0);
  });
});

describe('toEnglishDigits & sanitizeDecimalInput', () => {
  it('converts mixed Eastern and Western digits to pure English digits', () => {
    expect(toEnglishDigits('٠١٢٣4567٨٩')).toBe('0123456789');
  });

  it('sanitizes decimal inputs while preserving negative signs', () => {
    expect(sanitizeDecimalInput('-١,٥٠٠.٧٥')).toBe('-1500.75');
    expect(sanitizeDecimalInput('   ٢٥٠٠   ')).toBe('2500');
  });
});
