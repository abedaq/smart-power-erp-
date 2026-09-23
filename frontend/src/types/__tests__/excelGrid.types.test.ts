import { describe, it, expect } from 'vitest';
import { computeRowFinancials, computeGridTotals } from '../excelGrid.types';

describe('ExcelGrid Calculations', () => {
  it('computes consumption, cost, total due, and remaining accurately', () => {
    const row = {
      id: 1,
      subNumber: '91001',
      route: '1',
      name: 'مشترك تجريبي',
      address: '',
      meterNumber: '',
      phone: '',
      prevReading: 100,
      currReading: 150,
      unitPrice: 1000,
      serviceFee: 1000,
      arrears: 5000,
      paidAmount: 2000,
    };
    const result = computeRowFinancials(row);
    expect(result.units).toBe(50); // 150 - 100
    expect(result.consumptionCost).toBe(50000); // 50 * 1000
    expect(result.totalDue).toBe(56000); // 50000 + 1000 + 5000
    expect(result.remaining).toBe(54000); // 56000 - 2000
  });

  it('aggregates footer totals cleanly', () => {
    const rows = [
      computeRowFinancials({
        id: 1,
        subNumber: '1',
        route: '1',
        name: '1',
        address: '',
        meterNumber: '',
        phone: '',
        prevReading: 0,
        currReading: 10,
        unitPrice: 1000,
        serviceFee: 500,
        arrears: 0,
        paidAmount: 10500,
      }),
      computeRowFinancials({
        id: 2,
        subNumber: '2',
        route: '1',
        name: '2',
        address: '',
        meterNumber: '',
        phone: '',
        prevReading: 0,
        currReading: 20,
        unitPrice: 1000,
        serviceFee: 500,
        arrears: 1000,
        paidAmount: 0,
      }),
    ];
    const totals = computeGridTotals(rows);
    expect(totals.totalUnitsSum).toBe(30);
    expect(totals.totalConsumptionCostSum).toBe(30000);
    expect(totals.totalPaidSum).toBe(10500);
    expect(totals.totalRemainingSum).toBe(21500);
  });
});
