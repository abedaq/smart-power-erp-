export const getNormalizedArea = (address: string | null | undefined): string => {
  if (!address || !address.trim()) return 'بدون منطقة';
  const clean = address.trim();

  if (clean.includes('الجحملية') || clean.includes('جحملية')) return 'الجحملية';
  if (clean.includes('الخزانات') || clean.includes('خزانات')) return 'الخزانات';
  if (clean.includes('صالة') || clean.includes('الصالة')) return 'صالة';
  if (clean.includes('قريش')) return 'حارة قريش';
  if (clean.includes('الزرعي') || clean.includes('زرعي')) return 'الزرعي';
  if (clean.includes('عقبة') || clean.includes('العقبة')) return 'عقبة';
  if (clean.includes('حوض') || clean.includes('الحوض')) return 'حوض الأشراف';
  if (clean.includes('المسبح') || clean.includes('مسبح')) return 'المسبح';
  if (clean.includes('الروضة') || clean.includes('روضة')) return 'الروضة';

  // Fallback: extract first word or return cleaned address
  const firstWord = clean.split(/[\s,-]+/)[0];
  return firstWord || clean || 'أخرى';
};

export interface AreaGroup<T> {
  area: string;
  count: number;
  items: T[];
}

export function groupItemsByNormalizedArea<T>(
  items: T[],
  getAddress: (item: T) => string | null | undefined
): AreaGroup<T>[] {
  const map = new Map<string, T[]>();

  items.forEach((item) => {
    const rawAddress = getAddress(item);
    const normalized = getNormalizedArea(rawAddress);
    if (!map.has(normalized)) {
      map.set(normalized, []);
    }
    map.get(normalized)!.push(item);
  });

  return Array.from(map.entries()).map(([area, areaItems]) => ({
    area,
    count: areaItems.length,
    items: areaItems,
  })).sort((a, b) => b.count - a.count);
}
