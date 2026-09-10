export const TYPES_VERSION = '1.0';

export interface User {
  id: number;
  username: string;
  full_name: string;
  role: 'ADMIN' | 'CASHIER' | 'COLLECTOR';
  is_active: boolean;
}

export interface SubscriptionPlan {
  id: number;
  plan_name: string;
  kwh_price: number;
  fixed_fee: number;
  grace_period_days: number;
}

export interface Customer {
  id: number;
  subscriber_number: string;
  full_name: string;
  phone_number: string;
  address?: string;
  meter_number?: string;
  route_number?: string;
  subscription_plan_id?: number;
  subscription_plan?: SubscriptionPlan;
  initial_reading: number;
  start_cycle?: string;
  last_reading?: number;
  previous_reading?: number;
  total_due?: number;
  arrears?: number;
  remaining_amount?: number;
  balance?: number;
  meter_readings?: any[];
  payments?: any[];
  invoices?: any[];
  status: string;
  is_deleted?: boolean;
  created_at?: string;
}

export interface Invoice {
  id: number;
  customer_id: number;
  customer?: Customer;
  reading_id?: number | null;
  meter_reading?: any;
  lost_units?: number;
  previous_reading: number;
  current_reading: number;
  consumption: number;
  consumption_value: number;
  kwh_price_snapshot: number;
  fixed_fee_snapshot: number;
  arrears: number;
  total_due: number;
  paid_amount: number;
  remaining_amount: number;
  billing_cycle: string;
  due_date: string;
  approval_status?: 'PENDING' | 'PENDING_REVIEW' | 'APPROVED' | 'REJECTED';
  status: 'Unpaid' | 'Partially_Paid' | 'Paid' | 'Pending_Approval' | 'Void';
  created_at: string;
}

export interface Payment {
  id: number;
  customer_id?: number;
  customer?: Customer;
  invoice_id?: number;
  receipt_number?: string;
  payment_method: 'CASH' | 'TRANSFER';
  amount_paid: number;
  payment_date: string;
  accountant_name: string;
  approval_status?: 'PENDING' | 'PENDING_REVIEW' | 'APPROVED' | 'REJECTED';
  rejection_reason?: string;
  notes?: string;
}

export interface SystemSettings {
  id: number;
  station_name: string;
  station_logo_url?: string;
  whatsapp_status: string;
  receipt_footer?: string;
  arrears_threshold: number;
  default_kwh_price: number;
  default_fixed_fee: number;
}

export interface OverdueDefaulter {
  customer: Customer;
  total_arrears: number;
  days_overdue: number;
  category: string;
  last_reading_date?: string;
  billing_cycle?: string;
}
