import { toEnglishDigits } from './formatters.ts';

export interface ValidationResult {
  isValid: boolean;
  formatted: string;
  error?: string;
}

export function validateYemeniPhone(phone: string): ValidationResult {
  if (!phone || !phone.trim()) {
    return { isValid: false, formatted: '', error: 'رقم الهاتف مطلوب ولا يمكن تركه فارغاً' };
  }

  // Convert any Eastern/Persian numerals to standard English digits first
  const normalized = toEnglishDigits(phone.trim());

  // Strip all spaces, dashes, parentheses, pluses, and non-digits
  let cleaned = normalized.replace(/[\s()+-]/g, '').replace(/[^0-9]/g, '');

  // Strip international prefixes and leading zeros
  while (cleaned.startsWith('00967')) {
    cleaned = cleaned.substring(5);
  }
  while (cleaned.startsWith('967')) {
    cleaned = cleaned.substring(3);
  }
  while (cleaned.startsWith('0')) {
    cleaned = cleaned.substring(1);
  }

  // Must be exactly 9 digits now
  if (!/^\d{9}$/.test(cleaned)) {
    return {
      isValid: false,
      formatted: phone,
      error: 'رقم الهاتف يجب أن يتكون من 9 أرقام (مثال: 771234567)'
    };
  }

  // Check valid Yemeni operator prefixes: 77, 73, 71, 70, 78
  const prefix = cleaned.substring(0, 2);
  const validPrefixes = ['77', '73', '71', '70', '78'];

  if (!validPrefixes.includes(prefix)) {
    return {
      isValid: false,
      formatted: phone,
      error: `رمز المشغل غير صحيح (${prefix}). يجب أن يبدأ بـ (77، 73، 71، 70، 78)`
    };
  }

  return {
    isValid: true,
    formatted: cleaned, // 9 digits without +967 (e.g. 734019059 or 773245776)
  };
}
