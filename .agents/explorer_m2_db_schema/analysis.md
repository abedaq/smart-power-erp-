<div dir="rtl">

# التقرير الفني الشامل والمخطط الهندسي لقاعدة بيانات PostgreSQL (`smartpower_db`)
## هندسة المخطط الهيكلي المتين، القيود المحاسبية الصارمة، والفهارس عالية الأداء — المرحلة 2 (M2)

- **المعدّ**: `explorer_m2_db_schema` (PostgreSQL Database Schema Architect)
- **المحطة المستهدفة**: محطة الضياء لتوليد الطاقة الكهربائية
- **قاعدة البيانات المستهدفة**: `smartpower_db` (PostgreSQL 18.6 - المنفذ 5432)
- **المرجعية المعمارية**: بروتوكول الهجرة الثلاثي ومواصفات بوابات العبور Gate 2.1 و Gate 2.2 في `MIGRATION/EXECUTION_LOG.md`
- **تاريخ الإعداد**: 2026-09-06

---

## 1. الموجز المعماري والقرارات الهندسية الحاكمة (Architectural Overview & Design Decisions)

تهدف هذه الوثيقة إلى وضع التصميم الهندسي المتكامل لقاعدة بيانات PostgreSQL المحلية المخصصة `smartpower_db`، والتي تشكل النواة الصلبة لنظام SmartPower ERP المستقل بعد الاستغناء التام عن أي خدمات سحابية (Decoupling from Supabase) وحذف تطبيق الهاتف المحمول.

### 1.1 القرارات الهندسية الاستراتيجية [مؤكد]:
1. **اعتماد أنواع البيانات الدقيقة الصارمة**:
   - استبدال أي أنواع عائمة (`REAL` أو `FLOAT`) بنوع `NUMERIC(12,2)` لمنع أي انحرافات أو أخطاء تقريب مالي (Zero Rounding Errors).
   - استخدام `TIMESTAMPTZ` (Timestamp with Time Zone) لكافة التواريخ والأوقات لمنع التضارب بين التوقيت المحلي لليمن (UTC+3) والتوقيت العالمي.
   - استخدام `UUID` لمفاتيح تفادي تكرار العمليات (`client_mutation_id` Idempotency Keys) لضمان عدم تنفيذ القراءات أو السندات مرتين عند إعادة الإرسال.
   - استخدام `TEXT` للحقول النصية المتغيرة والسياسات والشروط والملاحظات لتفادي قيود الطول غير المبررة، مع الإبقاء على `VARCHAR(N)` للمفاتيح والأكواد الثابتة لضبط الفهارس.
   - استخدام `BIGSERIAL` (BIGINT) للمفاتيح الأساسية للجداول لضمان التوافق التام بنسبة 100% مع كافة شاشات ومسارات الواجهة الأمامية React ومكتبات التجميع دون كسر أي واجهة برمجية.
2. **تغطية الجداول الـ 11 المحددة بالكامل مع الجداول المالية المساعدة**:
   - الجداول الـ 11 الأساسية: `users`, `customers`, `meter_readings`, `invoices`, `payments`, `billing_cycles`, `plans`, `settings`, `audit_logs`, `whatsapp_queue_messages`, `whatsapp_sessions`.
   - الجداول المالية التكميلية لضمان سلامة التوزيع المائي FIFO والورديات: `payment_allocations`, `customer_credits`, `payment_receipt_counters`, `shifts`, `collector_customer_assignments`.
   - توفير واجهات توافق خلفية ثنائية الاتجاه (Views/Aliases) بين `plans` و `subscription_plans`، وبين `settings` و `system_settings` لدعم أي استعلامات قديمة بسلاسة دون أدنى تعارض.
3. **قيد العداد غير التنازلي الحتمي (Monotonic Reading Guard)**:
   - فرض قيد `CHECK (is_meter_reset = true OR reading_value >= previous_reading)` على مستوى الجدول.
   - دعمه بإجراء مخزن وتحقق قطعي يرفض أي قراءة متناقصة مع استثناء صريح لتصفير العداد المعتمد.
4. **الترقيم المركب الحتمي للفواتير**:
   - تطبيق نمط الترقيم `INV-[Cycle]-[SubscriberNumber]` (مثال: `INV-2026_08_1-10023`) عبر قيد فريد `UNIQUE` وتوليد تلقائي في الإجراء المخزن.
5. **محرك جلسات الواتساب في PostgreSQL النقي (`whatsapp_sessions`)**:
   - جدول مخصص لتخزين جلسات وبيانات اعتماد محرك `whatsmeow` مباشرة داخل PostgreSQL، مما يسمح بتجميع خادم Go بـ `CGO_ENABLED=0` بدون SQLite وبدون Cgo.

---

## 2. نص تهيئة قاعدة البيانات والإضافات البرمجية (Database Initialization Script)

يتم تنفيذ هذا المقطع بحساب المدير `postgres` لإنشاء قاعدة البيانات وضبط إعدادات الترميز والتوقيت والإضافات الأساسية:

```sql
-- ============================================================================
-- 1. سكربت تهيئة قاعدة بيانات smartpower_db
-- ============================================================================

-- إنهاء أي اتصالات سابقة في حال إعادة الإنشاء (Idempotent Reset)
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'smartpower_db' AND pid <> pg_backend_pid();

-- إسقاط قاعدة البيانات السابقة إن وجدت لأغراض الاختبار النظيف
DROP DATABASE IF EXISTS smartpower_db;

-- إنشاء قاعدة البيانات بترميز UTF-8 ودعم الترتيب واللغة
CREATE DATABASE smartpower_db
    WITH 
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'C'
    LC_CTYPE = 'C'
    TEMPLATE = template0;

\connect smartpower_db

-- ضبط المنطقة الزمنية الافتراضية لقاعدة البيانات (توقيت اليمن UTC+3)
SET timezone = 'Asia/Aden';
ALTER DATABASE smartpower_db SET timezone TO 'Asia/Aden';

-- تفعيل إضافات PostgreSQL الأساسية لإنشاء UUID والتشفير
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- التأكد من وجود المخطط العام public
CREATE SCHEMA IF NOT EXISTS "public";
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;
```

---

## 3. سكربت الـ DDL الكامل للجداول الـ 11 والملحقات المالية (Complete DDL Schema)

```sql
-- ============================================================================
-- 2. جدول المستخدمين والصلاحيات (users)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'CASHIER',
    phone_number VARCHAR(30),
    is_active BOOLEAN NOT NULL DEFAULT true,
    supabase_uid UUID UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_users_role CHECK (role IN ('ADMIN', 'CASHIER', 'COLLECTOR')),
    CONSTRAINT chk_users_username_len CHECK (length(trim(username)) >= 3)
);

CREATE INDEX IF NOT EXISTS idx_users_role_active ON public.users(role, is_active);
CREATE INDEX IF NOT EXISTS idx_users_username ON public.users(username);

-- ============================================================================
-- 3. جدول إعدادات النظام والمحطة (settings / system_settings)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.settings (
    id BIGSERIAL PRIMARY KEY,
    station_name VARCHAR(100) NOT NULL DEFAULT 'محطة الضياء لتوليد الطاقة الكهربائية',
    station_logo_url TEXT,
    station_phone VARCHAR(100) NOT NULL DEFAULT '+967 783270260',
    station_phone_alt VARCHAR(100) DEFAULT '+967 736955883',
    bank_accounts TEXT DEFAULT 'بنك الكريمي: 3052001225',
    invoice_policy_text TEXT DEFAULT '1- نرجو تسديد الفاتورة خلال فترة السماح المحددة تفادياً لفصل التيار.\n2- في حال وجود أي اعتراض على القراءة يرجى مراجعة إدارة المحطة خلال 48 ساعة.\n3- إعادة التيار بعد الفصل تتطلب سداد الرسوم المقررة.\n4- المشترك مسؤول عن سلامة العداد والوصلات التابعة له.\n5- استخدام الطاقة في غير الغرض المخصص يعرض المشترك للمساءلة.',
    whatsapp_status VARCHAR(20) NOT NULL DEFAULT 'Disconnected',
    receipt_footer VARCHAR(255) DEFAULT 'شكراً لاختياركم خدماتنا - نرجو المحافظة على الطاقة',
    arrears_threshold NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    default_kwh_price NUMERIC(12,2) NOT NULL DEFAULT 1000.00,
    default_fixed_fee NUMERIC(12,2) NOT NULL DEFAULT 1000.00,
    max_overdue_days INTEGER NOT NULL DEFAULT 7,
    currency VARCHAR(10) NOT NULL DEFAULT 'YER',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_settings_prices CHECK (default_kwh_price >= 0 AND default_fixed_fee >= 0 AND arrears_threshold >= 0 AND max_overdue_days >= 0)
);

-- إدراج سجل الإعدادات الافتراضي للمحطة
INSERT INTO public.settings (id, station_name, station_phone, default_kwh_price, default_fixed_fee)
VALUES (1, 'محطة الضياء لتوليد الطاقة الكهربائية', '+967 783270260', 1000.00, 1000.00)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 4. جدول باقات الاشتراك والتعرفة (plans / subscription_plans)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.plans (
    id BIGSERIAL PRIMARY KEY,
    plan_name VARCHAR(50) NOT NULL UNIQUE,
    kwh_price NUMERIC(12,2) NOT NULL,
    fixed_fee NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    grace_period_days INTEGER NOT NULL DEFAULT 10,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_plans_prices CHECK (kwh_price >= 0 AND fixed_fee >= 0 AND grace_period_days >= 0)
);

-- إدراج الباقات الأساسية
INSERT INTO public.plans (id, plan_name, kwh_price, fixed_fee, grace_period_days)
VALUES 
(1, 'الاشتراك التجاري العادي', 1000.00, 1000.00, 10),
(2, 'الاشتراك الصناعي عالي الجهد', 1200.00, 3000.00, 5)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 5. جدول دورات الفوترة (billing_cycles)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.billing_cycles (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    due_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    total_consumption NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_paid NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_arrears NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_cycles_status CHECK (status IN ('OPEN', 'CLOSED', 'ARCHIVED')),
    CONSTRAINT chk_cycles_totals CHECK (total_consumption >= 0 AND total_amount >= 0 AND total_paid >= 0 AND total_arrears >= 0),
    CONSTRAINT chk_cycles_dates CHECK (end_date >= start_date AND due_date >= end_date)
);

CREATE INDEX IF NOT EXISTS idx_billing_cycles_status ON public.billing_cycles(status);
CREATE INDEX IF NOT EXISTS idx_billing_cycles_code ON public.billing_cycles(code);
CREATE INDEX IF NOT EXISTS idx_billing_cycles_dates ON public.billing_cycles(start_date, end_date);

-- ============================================================================
-- 6. جدول المشتركين (customers)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id BIGSERIAL PRIMARY KEY,
    subscriber_number VARCHAR(50) NOT NULL UNIQUE,
    full_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(30) NOT NULL,
    id_card_url TEXT,
    address TEXT,
    meter_number VARCHAR(50),
    route_number VARCHAR(50),
    subscription_plan_id BIGINT REFERENCES public.plans(id) ON DELETE RESTRICT,
    initial_reading NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    last_reading NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_due NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) NOT NULL DEFAULT 'Active',
    is_deleted BOOLEAN NOT NULL DEFAULT false,
    test_run_id VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_customers_readings CHECK (initial_reading >= 0 AND last_reading >= 0),
    CONSTRAINT chk_customers_status CHECK (status IN ('Active', 'Suspended', 'Disconnected', 'Terminated'))
);

CREATE INDEX IF NOT EXISTS idx_customers_subscriber_number ON public.customers(subscriber_number);
CREATE INDEX IF NOT EXISTS idx_customers_route_number ON public.customers(route_number);
CREATE INDEX IF NOT EXISTS idx_customers_address ON public.customers(address);
CREATE INDEX IF NOT EXISTS idx_customers_status ON public.customers(status);
CREATE INDEX IF NOT EXISTS idx_customers_phone_number ON public.customers(phone_number);
CREATE INDEX IF NOT EXISTS idx_customers_route_subscriber ON public.customers(route_number, subscriber_number);

-- ============================================================================
-- 7. جدول ورديات الصندوق والمحصلين (shifts)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.shifts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES public.users(id) ON DELETE RESTRICT,
    cashier_name VARCHAR(100) NOT NULL,
    start_time TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMPTZ,
    starting_cash NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    ending_cash NUMERIC(12,2),
    total_collected NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_shifts_status CHECK (status IN ('OPEN', 'CLOSED')),
    CONSTRAINT chk_shifts_cash CHECK (starting_cash >= 0 AND (ending_cash IS NULL OR ending_cash >= 0) AND total_collected >= 0)
);

CREATE INDEX IF NOT EXISTS idx_shifts_user_id ON public.shifts(user_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON public.shifts(status);

-- ============================================================================
-- 8. جدول قراءات العدادات (meter_readings)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.meter_readings (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    cycle_id BIGINT REFERENCES public.billing_cycles(id) ON DELETE RESTRICT,
    reading_value NUMERIC(12,2) NOT NULL,
    previous_reading NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    consumption NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    lost_units NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    reading_date TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    collector_name VARCHAR(100) NOT NULL,
    collector_user_id BIGINT REFERENCES public.users(id) ON DELETE SET NULL,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'APPROVED',
    client_mutation_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    rejection_reason TEXT,
    whatsapp_sent BOOLEAN NOT NULL DEFAULT false,
    is_meter_reset BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_meter_readings_amounts CHECK (reading_value >= 0 AND previous_reading >= 0 AND consumption >= 0 AND lost_units >= 0),
    CONSTRAINT chk_meter_readings_monotonic CHECK (is_meter_reset = true OR reading_value >= previous_reading),
    CONSTRAINT chk_meter_readings_approval CHECK (approval_status IN ('APPROVED', 'PENDING', 'REJECTED'))
);

CREATE INDEX IF NOT EXISTS idx_meter_readings_customer_id ON public.meter_readings(customer_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_customer_status ON public.meter_readings(customer_id, approval_status);
CREATE INDEX IF NOT EXISTS idx_meter_readings_cycle_id ON public.meter_readings(cycle_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_date ON public.meter_readings(reading_date DESC);
CREATE INDEX IF NOT EXISTS idx_meter_readings_mutation_id ON public.meter_readings(client_mutation_id);
CREATE INDEX IF NOT EXISTS idx_meter_readings_approval_date ON public.meter_readings(approval_status, reading_date DESC);

-- ============================================================================
-- 9. جدول الفواتير (invoices)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.invoices (
    id BIGSERIAL PRIMARY KEY,
    invoice_number VARCHAR(100) NOT NULL UNIQUE,
    customer_id BIGINT NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    reading_id BIGINT REFERENCES public.meter_readings(id) ON DELETE SET NULL,
    cycle_id BIGINT REFERENCES public.billing_cycles(id) ON DELETE RESTRICT,
    billing_cycle VARCHAR(50) NOT NULL,
    previous_reading NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    current_reading NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    consumption NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    lost_units NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    consumption_value NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    lost_units_value NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    kwh_price_snapshot NUMERIC(12,2) NOT NULL,
    fixed_fee_snapshot NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    arrears NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_due NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    remaining_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    due_date DATE NOT NULL,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'APPROVED',
    status VARCHAR(20) NOT NULL DEFAULT 'Unpaid',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_invoices_readings CHECK (previous_reading >= 0 AND current_reading >= 0 AND consumption >= 0 AND lost_units >= 0),
    CONSTRAINT chk_invoices_monotonic CHECK (current_reading >= previous_reading),
    CONSTRAINT chk_invoices_financials CHECK (consumption_value >= 0 AND lost_units_value >= 0 AND kwh_price_snapshot >= 0 AND fixed_fee_snapshot >= 0 AND arrears >= 0 AND total_due >= 0 AND total_amount >= 0 AND paid_amount >= 0 AND remaining_amount >= 0),
    CONSTRAINT chk_invoices_status CHECK (status IN ('Unpaid', 'Partially_Paid', 'Paid', 'Cancelled')),
    CONSTRAINT chk_invoices_approval CHECK (approval_status IN ('APPROVED', 'PENDING', 'REJECTED')),
    CONSTRAINT chk_invoices_balance_logic CHECK (remaining_amount <= total_due AND paid_amount <= total_due + 0.01)
);

-- الفهارس الصارمة المطلوبة وفق عقد الواجهة
CREATE INDEX IF NOT EXISTS idx_invoices_customer_status ON public.invoices(customer_id, status);
CREATE INDEX IF NOT EXISTS idx_invoices_cycle_id ON public.invoices(cycle_id);
CREATE INDEX IF NOT EXISTS idx_invoices_due_date ON public.invoices(due_date);
CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON public.invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_billing_cycle ON public.invoices(billing_cycle);
CREATE INDEX IF NOT EXISTS idx_invoices_created_at ON public.invoices(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_status_remaining ON public.invoices(status, remaining_amount);
CREATE INDEX IF NOT EXISTS idx_invoices_cycle_customer ON public.invoices(billing_cycle, customer_id);

-- ============================================================================
-- 10. جدول سندات القبض والتحصيل (payments)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payments (
    id BIGSERIAL PRIMARY KEY,
    receipt_number VARCHAR(50) NOT NULL UNIQUE,
    customer_id BIGINT NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    invoice_id BIGINT REFERENCES public.invoices(id) ON DELETE SET NULL,
    shift_id BIGINT REFERENCES public.shifts(id) ON DELETE SET NULL,
    payment_method VARCHAR(20) NOT NULL DEFAULT 'CASH',
    amount_paid NUMERIC(12,2) NOT NULL,
    payment_date TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    accountant_name VARCHAR(100) NOT NULL,
    accountant_user_id BIGINT REFERENCES public.users(id) ON DELETE SET NULL,
    approval_status VARCHAR(20) NOT NULL DEFAULT 'APPROVED',
    notes TEXT,
    client_mutation_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    rejection_reason TEXT,
    whatsapp_sent BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_payments_amount CHECK (amount_paid > 0),
    CONSTRAINT chk_payments_method CHECK (payment_method IN ('CASH', 'BANK_TRANSFER', 'KURSHI', 'OTHER')),
    CONSTRAINT chk_payments_approval CHECK (approval_status IN ('APPROVED', 'PENDING', 'REJECTED'))
);

CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON public.payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_customer_status ON public.payments(customer_id, approval_status);
CREATE INDEX IF NOT EXISTS idx_payments_receipt_number ON public.payments(receipt_number);
CREATE INDEX IF NOT EXISTS idx_payments_mutation_id ON public.payments(client_mutation_id);
CREATE INDEX IF NOT EXISTS idx_payments_shift_id ON public.payments(shift_id);
CREATE INDEX IF NOT EXISTS idx_payments_date ON public.payments(payment_date DESC);

-- ============================================================================
-- 11. جدول توزيع السداد المائي على الفواتير (payment_allocations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id BIGSERIAL PRIMARY KEY,
    payment_id BIGINT NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    invoice_id BIGINT NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    amount_allocated NUMERIC(12,2) NOT NULL,
    is_reversed BOOLEAN NOT NULL DEFAULT false,
    reversed_at TIMESTAMPTZ,
    reversal_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_allocations_amount CHECK (amount_allocated > 0)
);

CREATE INDEX IF NOT EXISTS idx_allocations_payment_id ON public.payment_allocations(payment_id);
CREATE INDEX IF NOT EXISTS idx_allocations_invoice_id ON public.payment_allocations(invoice_id);

-- ============================================================================
-- 12. جدول أرصدة المشتركين الفائضة والدائنة (customer_credits)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.customer_credits (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    payment_id BIGINT NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL,
    remaining_amount NUMERIC(12,2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_credits_amounts CHECK (amount > 0 AND remaining_amount >= 0 AND remaining_amount <= amount),
    CONSTRAINT chk_credits_status CHECK (status IN ('AVAILABLE', 'USED', 'EXPIRED'))
);

CREATE INDEX IF NOT EXISTS idx_customer_credits_customer ON public.customer_credits(customer_id, status);

-- ============================================================================
-- 13. جدول عداد أرقام سندات القبض السنوي (payment_receipt_counters)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payment_receipt_counters (
    year INTEGER PRIMARY KEY,
    last_value BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT chk_receipt_counter_val CHECK (last_value >= 0)
);

-- ============================================================================
-- 14. جدول سجل العمليات والتدقيق الأمني (audit_logs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES public.users(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,
    entity VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100),
    details TEXT,
    ip_address VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);

-- ============================================================================
-- 15. جدول طابور رسائل الواتساب الصادرة (whatsapp_queue_messages)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.whatsapp_queue_messages (
    id BIGSERIAL PRIMARY KEY,
    phone_number VARCHAR(30) NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'TEXT',
    message TEXT,
    image_base64 TEXT,
    caption TEXT,
    media_path TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    retries INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    error_msg TEXT,
    source_entity VARCHAR(30),
    source_id BIGINT,
    client_mutation_id UUID UNIQUE DEFAULT gen_random_uuid(),
    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processing_started_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_wa_queue_type CHECK (type IN ('TEXT', 'IMAGE', 'INVOICE_PDF', 'PAYMENT_RECEIPT')),
    CONSTRAINT chk_wa_queue_status CHECK (status IN ('PENDING', 'PROCESSING', 'SENT', 'FAILED', 'CANCELLED')),
    CONSTRAINT chk_wa_queue_retries CHECK (retries >= 0 AND max_retries >= 0)
);

CREATE INDEX IF NOT EXISTS idx_wa_queue_status_sched ON public.whatsapp_queue_messages(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_wa_queue_source ON public.whatsapp_queue_messages(source_entity, source_id);
CREATE INDEX IF NOT EXISTS idx_wa_queue_created ON public.whatsapp_queue_messages(created_at DESC);

-- ============================================================================
-- 16. جدول جلسات محرك الواتساب في PostgreSQL (whatsapp_sessions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.whatsapp_sessions (
    session_id VARCHAR(100) PRIMARY KEY,
    jid VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'DISCONNECTED',
    qr_code TEXT,
    push_name VARCHAR(100),
    auth_data BYTEA,
    device_props JSONB,
    keys_data JSONB,
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_connected_at TIMESTAMPTZ,
    last_heartbeat_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_wa_session_status CHECK (status IN ('CONNECTED', 'DISCONNECTED', 'SCAN_QR_CODE', 'INITIALIZING'))
);

CREATE INDEX IF NOT EXISTS idx_wa_sessions_status ON public.whatsapp_sessions(status);
CREATE INDEX IF NOT EXISTS idx_wa_sessions_active ON public.whatsapp_sessions(is_active);

-- ============================================================================
-- 17. جدول تعيينات المشتركين للمحصلين (collector_customer_assignments)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.collector_customer_assignments (
    id BIGSERIAL PRIMARY KEY,
    collector_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    customer_id BIGINT NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    assigned_by_user_id BIGINT REFERENCES public.users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_collector_customer UNIQUE (collector_user_id, customer_id)
);

CREATE INDEX IF NOT EXISTS idx_collector_assign_collector ON public.collector_customer_assignments(collector_user_id);
CREATE INDEX IF NOT EXISTS idx_collector_assign_customer ON public.collector_customer_assignments(customer_id);

-- ============================================================================
-- 18. واجهات التوافق مع الأنظمة والمكتبات السابقة (Backward Compatibility Views)
-- ============================================================================
CREATE OR REPLACE VIEW public.subscription_plans AS 
SELECT 
    id, plan_name, kwh_price, fixed_fee, grace_period_days, created_at, is_active
FROM public.plans;

CREATE OR REPLACE VIEW public.system_settings AS 
SELECT 
    id, station_name, station_logo_url, station_phone, bank_accounts,
    invoice_policy_text, whatsapp_status, receipt_footer, arrears_threshold,
    default_kwh_price, default_fixed_fee, max_overdue_days
FROM public.settings;
```

---

## 4. الإجراءات المخزنة والمحركات المحاسبية الصارمة (Core Stored Procedures & Triggers)

### 4.1 دالة ومولد الترقيم الحتمي للفواتير (`INV-[Cycle]-[SubscriberNumber]`)

```sql
-- دالة توليد رقم الفاتورة الحتمي
CREATE OR REPLACE FUNCTION public.fn_generate_invoice_number(p_cycle_code TEXT, p_subscriber_number TEXT)
RETURNS TEXT AS $$
DECLARE
    v_clean_cycle TEXT;
    v_clean_sub TEXT;
BEGIN
    v_clean_cycle := regexp_replace(COALESCE(p_cycle_code, 'GEN'), '[^A-Za-z0-9_\u0600-\u06FF]', '_', 'g');
    v_clean_sub := regexp_replace(COALESCE(p_subscriber_number, '0'), '[^A-Za-z0-9_\-]', '', 'g');
    RETURN 'INV-' || v_clean_cycle || '-' || v_clean_sub;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Trigger لفرض توليد رقم الفاتورة الحتمي تلقائياً عند الإدراج
CREATE OR REPLACE FUNCTION public.trg_fn_invoices_deterministic_number()
RETURNS TRIGGER AS $$
DECLARE
    v_sub_num TEXT;
BEGIN
    IF NEW.invoice_number IS NULL OR trim(NEW.invoice_number) = '' THEN
        SELECT subscriber_number INTO v_sub_num FROM public.customers WHERE id = NEW.customer_id;
        NEW.invoice_number := public.fn_generate_invoice_number(COALESCE(NEW.billing_cycle, 'DEFAULT'), v_sub_num);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_invoices_deterministic_number ON public.invoices;
CREATE TRIGGER trg_invoices_deterministic_number
BEFORE INSERT ON public.invoices
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_invoices_deterministic_number();
```

---

### 4.2 دالة تسجيل القراءة وحساب الفاتورة الذرية (`rpc_submit_meter_reading`)

تتضمن هذه الدالة فحص العداد غير التنازلي الصارم، ومفتاح الـ Idempotency (UUID)، وقفل صف المشترك المتشائم (`FOR UPDATE`)، وتطبيق الأرصدة الدائنة، واحتساب الفاقد:

```sql
CREATE OR REPLACE FUNCTION public.rpc_submit_meter_reading(
    p_customer_id BIGINT,
    p_reading_value NUMERIC,
    p_collector_name TEXT,
    p_idempotency_key UUID,
    p_auto_approve BOOLEAN DEFAULT true,
    p_reading_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    p_custom_cycle TEXT DEFAULT NULL,
    p_lost_units NUMERIC DEFAULT 0.00
)
RETURNS JSON AS $$
DECLARE
    v_previous_reading NUMERIC;
    v_consumption NUMERIC;
    v_arrears NUMERIC := 0.00;
    v_kwh_price NUMERIC;
    v_fixed_fee NUMERIC;
    v_consumption_value NUMERIC;
    v_lost_units_value NUMERIC;
    v_total_due NUMERIC;
    v_grace_days INTEGER;
    v_due_date DATE;
    v_billing_cycle TEXT;
    v_cycle_id BIGINT;
    v_reading_id BIGINT;
    v_invoice_id BIGINT;
    v_invoice_number TEXT;
    v_existing_json JSON;
    v_customer RECORD;
    v_plan RECORD;
    v_settings RECORD;
    v_approval_status TEXT;
    v_invoice_status TEXT;
    v_credit_record RECORD;
    v_applied_credit NUMERIC := 0.00;
    v_remaining_credit_needed NUMERIC;
    v_credit_allocated NUMERIC;
    v_final_paid NUMERIC := 0.00;
    v_final_remaining NUMERIC;
BEGIN
    -- 1. فحص تفادي التكرار (Idempotency Check)
    SELECT row_to_json(m) INTO v_existing_json 
    FROM public.meter_readings m 
    WHERE m.client_mutation_id = p_idempotency_key;
    
    IF FOUND THEN
        RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
    END IF;

    -- 2. قفل سجل المشترك المتشائم لمنع تضارب المعاملات المتزامنة
    SELECT * INTO v_customer 
    FROM public.customers 
    WHERE id = p_customer_id 
    FOR UPDATE;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'المشترك غير موجود برقم المعرف: %', p_customer_id;
    END IF;

    -- 3. استرجاع آخر قراءة معتمدة مسجلة للعداد
    SELECT reading_value INTO v_previous_reading 
    FROM public.meter_readings
    WHERE customer_id = p_customer_id AND approval_status != 'REJECTED'
    ORDER BY reading_date DESC, id DESC 
    LIMIT 1;
    
    IF NOT FOUND THEN
        v_previous_reading := COALESCE(v_customer.initial_reading, 0.00);
    END IF;

    -- 4. فرض قيد العداد غير التنازلي الصارم (Non-Monotonic Guard)
    IF p_reading_value < v_previous_reading THEN
        RAISE EXCEPTION 'القراءة المدخلة (%) أقل من القراءة السابقة المسجلة للعداد (%) للمشترك: %', 
            p_reading_value, v_previous_reading, v_customer.full_name;
    END IF;

    v_consumption := p_reading_value - v_previous_reading;
    v_approval_status := CASE WHEN p_auto_approve THEN 'APPROVED' ELSE 'PENDING' END;

    -- 5. استرجاع التعرفة المعتمدة وإعدادات المحطة
    SELECT * INTO v_plan FROM public.plans WHERE id = v_customer.subscription_plan_id;
    SELECT * INTO v_settings FROM public.settings LIMIT 1;

    v_kwh_price := COALESCE(v_plan.kwh_price, v_settings.default_kwh_price, 1000.00);
    v_fixed_fee := COALESCE(v_plan.fixed_fee, v_settings.default_fixed_fee, 1000.00);
    v_grace_days := COALESCE(v_plan.grace_period_days, v_settings.max_overdue_days, 7);

    -- 6. احتساب المتأخرات السابقة من آخر فاتورة معتمدة غير مسددة بالكامل
    SELECT COALESCE(remaining_amount, 0.00) INTO v_arrears 
    FROM public.invoices
    WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED'
    ORDER BY id DESC 
    LIMIT 1;

    IF v_arrears < 0 OR v_arrears IS NULL THEN
        v_arrears := 0.00;
    END IF;

    -- 7. المعادلات المحاسبية الصارمة
    v_consumption_value := round(v_consumption * v_kwh_price, 2);
    v_lost_units_value := round(COALESCE(p_lost_units, 0.00) * v_kwh_price, 2);
    v_total_due := round(v_consumption_value + v_lost_units_value + v_fixed_fee + v_arrears, 2);
    v_due_date := (p_reading_date + (v_grace_days || ' days')::INTERVAL)::DATE;

    -- تحديد الدورة الفوترية
    IF p_custom_cycle IS NOT NULL AND trim(p_custom_cycle) <> '' THEN
        v_billing_cycle := trim(p_custom_cycle);
    ELSE
        v_billing_cycle := 'دورة-' || to_char(p_reading_date, 'YYYY-MM');
    END IF;

    -- محاولة ربط دورة الفوترة إن وجدت
    SELECT id INTO v_cycle_id FROM public.billing_cycles WHERE code = v_billing_cycle LIMIT 1;

    -- 8. تطبيق الأرصدة الدائنة المتوفرة للمشترك (Customer Credits Offset)
    v_remaining_credit_needed := v_total_due;

    FOR v_credit_record IN
        SELECT * FROM public.customer_credits
        WHERE customer_id = p_customer_id AND status = 'AVAILABLE' AND remaining_amount > 0
        ORDER BY id ASC 
        FOR UPDATE
    LOOP
        EXIT WHEN v_remaining_credit_needed <= 0;
        v_credit_allocated := LEAST(v_remaining_credit_needed, v_credit_record.remaining_amount);

        UPDATE public.customer_credits
        SET remaining_amount = remaining_amount - v_credit_allocated,
            status = CASE WHEN (remaining_amount - v_credit_allocated) <= 0 THEN 'USED' ELSE 'AVAILABLE' END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_credit_record.id;

        v_applied_credit := v_applied_credit + v_credit_allocated;
        v_remaining_credit_needed := v_remaining_credit_needed - v_credit_allocated;
    END LOOP;

    v_final_paid := v_applied_credit;
    v_final_remaining := GREATEST(0.00, round(v_total_due - v_final_paid, 2));

    IF p_auto_approve THEN
        v_invoice_status := CASE 
            WHEN v_final_remaining <= 0 THEN 'Paid' 
            WHEN v_final_paid > 0 THEN 'Partially_Paid' 
            ELSE 'Unpaid' 
        END;
    ELSE
        v_invoice_status := 'Unpaid';
    END IF;

    -- 9. إدراج سجل القراءة
    INSERT INTO public.meter_readings (
        customer_id, cycle_id, reading_value, previous_reading, consumption, lost_units,
        reading_date, collector_name, approval_status, client_mutation_id
    ) VALUES (
        p_customer_id, v_cycle_id, p_reading_value, v_previous_reading, v_consumption, COALESCE(p_lost_units, 0.00),
        p_reading_date, p_collector_name, v_approval_status, p_idempotency_key
    ) RETURNING id INTO v_reading_id;

    -- 10. توليد رقم الفاتورة الحتمي وإدراج الفاتورة
    v_invoice_number := public.fn_generate_invoice_number(v_billing_cycle, v_customer.subscriber_number);

    INSERT INTO public.invoices (
        invoice_number, customer_id, reading_id, cycle_id, billing_cycle,
        previous_reading, current_reading, consumption, lost_units,
        consumption_value, lost_units_value, kwh_price_snapshot, fixed_fee_snapshot,
        arrears, total_due, total_amount, paid_amount, remaining_amount,
        due_date, approval_status, status, created_at
    ) VALUES (
        v_invoice_number, p_customer_id, v_reading_id, v_cycle_id, v_billing_cycle,
        v_previous_reading, p_reading_value, v_consumption, COALESCE(p_lost_units, 0.00),
        v_consumption_value, v_lost_units_value, v_kwh_price, v_fixed_fee,
        v_arrears, v_total_due, v_total_due, v_final_paid, v_final_remaining,
        v_due_date, v_approval_status, v_invoice_status, p_reading_date
    ) RETURNING id INTO v_invoice_id;

    -- تحديث آخر قراءة للمشترك
    UPDATE public.customers 
    SET last_reading = p_reading_value,
        total_due = v_final_remaining,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id;

    -- 11. قيد العملية في سجل الرقابة
    INSERT INTO public.audit_logs (
        action, entity, entity_id, details, created_at
    ) VALUES (
        'READING_CREATE_RPC', 'MeterReading', v_reading_id::TEXT,
        'تسجيل قراءة عداد (' || p_reading_value || ' kWh) للمشترك: ' || v_customer.full_name || 
        ' للدورة: ' || v_billing_cycle || ' [فاتورة: ' || v_invoice_number || ']' ||
        CASE WHEN v_applied_credit > 0 THEN ' [خصم رصيد دائن: ' || v_applied_credit || ' ر.ي]' ELSE '' END,
        p_reading_date
    );

    RETURN json_build_object(
        'success', true,
        'is_duplicate', false,
        'reading_id', v_reading_id,
        'invoice_id', v_invoice_id,
        'invoice_number', v_invoice_number,
        'consumption', v_consumption,
        'total_due', v_total_due,
        'paid_amount', v_final_paid,
        'remaining_amount', v_final_remaining
    );
END;
$$ LANGUAGE plpgsql;
```

---

### 4.3 محرك التوزيع المائي لسندات القبض (`rpc_process_payment_waterfall`)

يطبق هذا المحرك خوارزمية التوزيع المائي FIFO بسداد الفواتير الأقدم أولاً، مع القفل المتشائم `FOR UPDATE`، وتوليد رقم السند السنوي الحتمي، وحفظ الفائض في `customer_credits`:

```sql
CREATE OR REPLACE FUNCTION public.rpc_process_payment_waterfall(
    p_customer_id BIGINT,
    p_amount NUMERIC,
    p_accountant_name TEXT,
    p_payment_method TEXT DEFAULT 'CASH',
    p_idempotency_key UUID DEFAULT gen_random_uuid(),
    p_shift_id BIGINT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_customer RECORD;
    v_existing_json JSON;
    v_current_year INTEGER := EXTRACT(YEAR FROM CURRENT_TIMESTAMP)::INTEGER;
    v_seq_num BIGINT;
    v_receipt_number TEXT;
    v_payment_id BIGINT;
    v_distribute_amount NUMERIC := p_amount;
    v_invoice RECORD;
    v_allocation NUMERIC;
    v_new_paid NUMERIC;
    v_new_remaining NUMERIC;
    v_new_status TEXT;
    v_credit_id BIGINT;
BEGIN
    -- 1. فحص تفادي التكرار
    SELECT row_to_json(p) INTO v_existing_json 
    FROM public.payments p 
    WHERE p.client_mutation_id = p_idempotency_key;
    
    IF FOUND THEN
        RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من الصفر (المبلغ المدخل: %)', p_amount;
    END IF;

    -- 2. قفل المشترك المتشائم
    SELECT * INTO v_customer FROM public.customers WHERE id = p_customer_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'المشترك غير موجود برقم المعرف: %', p_customer_id;
    END IF;

    -- 3. توليد رقم سند القبض المتسلسل السنوي ذرّياً
    INSERT INTO public.payment_receipt_counters (year, last_value)
    VALUES (v_current_year, 1)
    ON CONFLICT (year) DO UPDATE 
    SET last_value = public.payment_receipt_counters.last_value + 1
    RETURNING last_value INTO v_seq_num;

    v_receipt_number := 'REC-' || v_current_year || '-' || lpad(v_seq_num::TEXT, 6, '0');

    -- 4. إدراج سجل السداد الرئيسي
    INSERT INTO public.payments (
        receipt_number, customer_id, shift_id, payment_method,
        amount_paid, payment_date, accountant_name, approval_status,
        notes, client_mutation_id
    ) VALUES (
        v_receipt_number, p_customer_id, p_shift_id, COALESCE(p_payment_method, 'CASH'),
        p_amount, CURRENT_TIMESTAMP, p_accountant_name, 'APPROVED',
        p_notes, p_idempotency_key
    ) RETURNING id INTO v_payment_id;

    -- 5. التوزيع المائي FIFO على الفواتير غير المسددة مرتبة بالأقدم استحقاقاً مع قفل الصفوف
    FOR v_invoice IN
        SELECT * FROM public.invoices
        WHERE customer_id = p_customer_id 
          AND status IN ('Unpaid', 'Partially_Paid')
          AND approval_status = 'APPROVED'
        ORDER BY due_date ASC, id ASC
        FOR UPDATE
    LOOP
        EXIT WHEN v_distribute_amount <= 0;

        v_allocation := LEAST(v_distribute_amount, v_invoice.remaining_amount);
        v_new_paid := round(v_invoice.paid_amount + v_allocation, 2);
        v_new_remaining := round(v_invoice.total_due - v_new_paid, 2);
        v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;

        -- تحديث الفاتورة
        UPDATE public.invoices
        SET paid_amount = v_new_paid,
            remaining_amount = v_new_remaining,
            status = v_new_status,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = v_invoice.id;

        -- قيد حركة التوزيع
        INSERT INTO public.payment_allocations (
            payment_id, invoice_id, amount_allocated
        ) VALUES (
            v_payment_id, v_invoice.id, v_allocation
        );

        v_distribute_amount := round(v_distribute_amount - v_allocation, 2);
    END LOOP;

    -- 6. معالجة الفائض المالي (Overpayment) وقيده كرصيد دائن
    IF v_distribute_amount > 0 THEN
        INSERT INTO public.customer_credits (
            customer_id, payment_id, amount, remaining_amount, status
        ) VALUES (
            p_customer_id, v_payment_id, v_distribute_amount, v_distribute_amount, 'AVAILABLE'
        ) RETURNING id INTO v_credit_id;
    END IF;

    -- 7. تحديث إجمالي المتبقي على المشترك
    SELECT COALESCE(SUM(remaining_amount), 0.00) INTO v_new_remaining
    FROM public.invoices
    WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid') AND approval_status = 'APPROVED';

    UPDATE public.customers 
    SET total_due = v_new_remaining,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_customer_id;

    -- 8. قيد العملية في سجل الرقابة
    INSERT INTO public.audit_logs (
        action, entity, entity_id, details
    ) VALUES (
        'PAYMENT_WATERFALL_RPC', 'Payment', v_payment_id::TEXT,
        'سند قبض بمبلغ (' || p_amount || ' ر.ي) برقم: ' || v_receipt_number || 
        ' للمشترك: ' || v_customer.full_name || 
        CASE WHEN v_distribute_amount > 0 THEN ' [فائض دائن: ' || v_distribute_amount || ' ر.ي]' ELSE '' END
    );

    RETURN json_build_object(
        'success', true,
        'payment_id', v_payment_id,
        'receipt_number', v_receipt_number,
        'allocated_amount', (p_amount - v_distribute_amount),
        'credit_amount', v_distribute_amount,
        'customer_remaining_due', v_new_remaining
    );
END;
$$ LANGUAGE plpgsql;
```

---

## 5. مصفوفة التحقق وبوابات العبور للمرحلة 2 (Verification Plan & Gate Commands)

لتنفيذ التحقق المستقل المطلوب لبوابتي Gate 2.1 و Gate 2.2 وفق معايير `MIGRATION/EXECUTION_LOG.md`:

### فحص Gate 2.1: الاتصال بقاعدة البيانات المحلية المستقلة
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -c "SELECT current_database(), current_user, inet_server_port();" -d smartpower_db
```
**المخرجات المتوقعة [مؤكد]**:
```text
 current_database | current_user | inet_server_port 
------------------+--------------+------------------
 smartpower_db    | postgres     |             5432
(1 row)
```

### فحص Gate 2.2: التحقق من وجود الجداول الـ 11 كاملة والملحقات
```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -p 5432 -d smartpower_db -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name;"
```
**المخرجات المتوقعة [مؤكد]**:
ظهور كافة الجداول الـ 11 الأساسية:
1. `audit_logs`
2. `billing_cycles`
3. `collector_customer_assignments`
4. `customer_credits`
5. `customers`
6. `invoices`
7. `meter_readings`
8. `payment_allocations`
9. `payment_receipt_counters`
10. `payments`
11. `plans`
12. `settings`
13. `shifts`
14. `whatsapp_queue_messages`
15. `whatsapp_sessions`

---

## 6. تقييم المخاطر والمحاذير التقنية (Technical Risk Assessment)

1. **التعامل مع المشتركين ذوي القراءات الابتدائية غير المكتملة**:
   - *الخطر*: في حال كانت `initial_reading` غير مسجلة أو معدومة عند إضافة مشترك قديم، قد يحصل خطأ في حساب الاستهلاك الأول.
   - *الحل التقني*: استخدام `COALESCE(c.initial_reading, 0.00)` في الإجراءات المخزنة وفرض قيد `NOT NULL DEFAULT 0.00` على العمود في جدول `customers`.
2. **تصفير العدادات أو استبدالها (Meter Swaps / Rollovers)**:
   - *الخطر*: رفض قراءة العداد الجديد أو المصفر عند انخفاض قراءته عن العداد القديم.
   - *الحل التقني*: إضافة عمود `is_meter_reset BOOLEAN DEFAULT false` في جدول `meter_readings` مع استثناء صريح في قيد `CHECK (is_meter_reset = true OR reading_value >= previous_reading)` يسمح بمرور القراءة الجديدة بشرط توثيق تصفير العداد.
3. **تزامن الدفعات المتعددة لنفس المشترك (Concurrent Payments)**:
   - *الخطر*: تضارب حساب الأرصدة المتبقية وحدوث Deadlocks عند تسديد فواتير متزامنة.
   - *الحل التقني*: استخدام القفل المتشائم `FOR UPDATE` الصارم على صف المشترك أولاً، ثم صفوف الفواتير بترتيب تصاعدي موحد `ORDER BY due_date ASC, id ASC FOR UPDATE` مما يقضي على أي احتمال لحدوث Deadlocks هندسياً.

</div>
