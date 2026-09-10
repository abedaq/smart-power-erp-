<div dir="rtl">

# تقرير فحص ومسح الباك إند وإجراءات PostgreSQL المخزنة (Backend & RPCs Audit Report)
**المشروع:** نظام الطاقة الذكية (Smart Power ERP)  
**المتطلبات المستهدفة:** R2 (المزامنة وإجراءات Supabase RPC) و R3 (المصادقة والصلاحيات وإدارة الجلسات)  
**تاريخ الفحص:** 2026-09-02  
**حالة التدقيق:** [مؤكد] مكتمل بالكامل مع توثيق المسارات والأسطر البرمجية  

---

## 1. الملخص التنفيذي

تم إجراء مسح شامل لكود الباك إند المبني على Node.js/Express ومخطط Prisma وإجراءات PostgreSQL المخزنة (RPCs) ومصادقة JWT وحدود التحكم في الوصول القائم على الأدوار (RBAC)، بالإضافة إلى فحص آليات مرونة طابور المزامنة الأوفلاين في تطبيق Flutter. أظهر التدقيق الفني التزاماً دقيقاً بالمعايير المعمارية لمنع تضارب دوال RPC وتوحيد معالجة السدادات المالية بآلية FIFO وعزل صلاحيات المحصلين بدقة وفرض كود الحالة HTTP 403 Forbidden على المسارات الإدارية والتعريفات.

---

## 2. جدول مطابقة متطلبات التحقق الفني (Compliance Matrix)

| المتطلب | المكون / الوظيفة | الحالة | مستوى اليقين | الملفات المرجعية الأساسية |
|---|---|---|---|---|
| **R2.1** | إجراء `rpc_submit_meter_reading`، مطابقة المعاملات، منع PGRST203، واستجابة JSON | **مطابق (PASS)** | [مؤكد] | `backend/src/scripts/clean_and_unify_rpc.ts`<br>`backend/src/scripts/fix_postgrest_pgrst203.ts`<br>`backend/src/services/financial-rpc.service.ts` |
| **R2.2** | إجراء `rpc_submit_payment`، توزيع FIFO للفواتير، وسجل الأرصدة الدائنة | **مطابق (PASS)** | [مؤكد] | `backend/src/scripts/unify_payment_rpc.ts`<br>`backend/src/services/financial-rpc.service.ts`<br>`backend/src/controllers/payment.controller.ts` |
| **R2.3** | مرونة طابور المزامنة الأوفلاين (Offline Queue Resilience) ومنع تعليق المزامنة | **مطابق (PASS)** | [مؤكد] | `mobile_app/lib/services/sync_service.dart`<br>`mobile_app/lib/services/local_db_service.dart` |
| **R3.1** | مصادقة JWT وأسبقية التوكن المحلي على توكن السحابة | **مطابق (PASS)** | [مؤكد] | `backend/src/middleware/auth.middleware.ts`<br>`backend/src/controllers/auth.controller.ts`<br>`frontend/src/context/AuthContext.tsx` |
| **R3.2** | حدود الصلاحيات RBAC وفرض كود 403 للمحصلين على مسارات الإدارة والتعرفات | **مطابق (PASS)** | [مؤكد] | `backend/src/routes/plan.routes.ts`<br>`backend/src/routes/user.routes.ts`<br>`backend/src/routes/settings.routes.ts`<br>`backend/src/middleware/auth.middleware.ts` |

---

## 3. تفاصيل نتائج التدقيق المعماري والبرمجي

### 3.1. التدقيق الفني لإجراء `rpc_submit_meter_reading` (المتطلب R2.1)

#### أ. تعريف الدالة في PostgreSQL ومطابقة المعاملات
تم تعريف الإجراء الموحد الماستر في ملف `backend/src/scripts/fix_postgrest_pgrst203.ts` (الأسطر 22-165) و `backend/src/scripts/clean_and_unify_rpc.ts` (الأسطر 74-216):

```sql
CREATE OR REPLACE FUNCTION public.rpc_submit_meter_reading(
  p_customer_id integer,
  p_reading_value numeric,
  p_collector_name text,
  p_idempotency_key uuid,
  p_auto_approve boolean DEFAULT false,
  p_reading_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  p_custom_cycle text DEFAULT NULL,
  p_actor_user_id integer DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
```

#### ب. استراتيجية منع خطأ PGRST203 (PostgREST Ambiguity Avoidance)
- [مؤكد] خطأ `PGRST203` يحدث في PostgREST عندما توجد عدة دوال بنفس الاسم وتوقيعات معاملات زائدة (Function Overloading) مما يجعل محرك PostgREST عاجزاً عن تحديد الدالة المستهدفة بدقة.
- **الحل المنفذ**: يقوم السكريبت `fix_postgrest_pgrst203.ts` (الأسطر 7-18) بالاستعلام عن كافة التوقيعات القديمة وحذفها صراحة عبر:
  ```sql
  SELECT oid::regprocedure::text AS func_signature FROM pg_proc WHERE proname = 'rpc_submit_meter_reading';
  -- ثم تنفيذ: DROP FUNCTION <func_signature>
  ```
- تم اعتماد توقيع واحد موحد يستخدم `DEFAULT` للمعاملات الاختيارية (`p_auto_approve`, `p_reading_date`, `p_custom_cycle`, `p_actor_user_id`)، مما يلغي التعددية نهائياً ويمنع الخطأ 203.

#### ج. بنية استجابة JSON
- **في حالة التكرار (Idempotent replay)**:
  ```sql
  RETURN json_build_object('success', true, 'is_duplicate', true, 'data', v_existing_json);
  ```
- **في حالة التسجيل الجديد الناجح**:
  ```sql
  RETURN json_build_object(
    'success', true,
    'is_duplicate', false,
    'reading_id', v_reading_id,
    'invoice_id', v_invoice_id,
    'consumption', v_consumption,
    'total_due', v_total_due,
    'billing_cycle', v_billing_cycle,
    'approval_status', v_approval_status,
    'invoice_status', v_invoice_status,
    'auto_approved', v_approval_status = 'APPROVED'
  );
  ```

#### د. استدعاء Express Backend للإجراء
- في `backend/src/services/financial-rpc.service.ts` (الأسطر 73-98):
  ```typescript
  export async function submitMeterReadingRpc(input: {
    customerId: number;
    readingValue: number;
    collectorName: string;
    idempotencyKey: string;
    autoApprove: boolean;
    actorUserId?: number | null;
    readingDate?: Date;
    customCycle?: string;
  }): Promise<any> {
    return callRpc(Prisma.sql`
      WITH actor_context AS (
        SELECT set_config('app.actor_user_id', ${String(input.actorUserId ?? '')}, true) AS configured
      )
      SELECT public.rpc_submit_meter_reading(
        ${input.customerId},
        ${input.readingValue},
        ${input.collectorName},
        ${input.idempotencyKey}::uuid,
        ${input.autoApprove},
        ${input.readingDate ?? new Date()},
        ${input.customCycle ?? null}
      ) AS result
      FROM actor_context
    `);
  }
  ```
- في `backend/src/controllers/reading.controller.ts` (الأسطر 15-76):
  يتحقق الكونترولر من المعاملات وصلاحية الدور، ويستدعي `submitMeterReadingRpc`، ويعالج الناتج ويعيد كود `201 Created` مع تفاصيل الكائن المالي المُنشأ.

---

### 3.2. التدقيق الفني لإجراء `rpc_submit_payment` وتوزيع FIFO (المتطلب R2.2)

#### أ. تعريف الدالة ومطابقة المعاملات
تم تعريف الإجراء الموحد في `backend/src/scripts/unify_payment_rpc.ts` (الأسطر 18-167):

```sql
CREATE OR REPLACE FUNCTION public.rpc_submit_payment(
  p_customer_id integer,
  p_amount_paid numeric,
  p_payment_method text,
  p_collector_name text,
  p_idempotency_key uuid,
  p_notes text DEFAULT NULL,
  p_payment_date timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  p_invoice_id integer DEFAULT NULL,
  p_actor_user_id integer DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
```

#### ب. خوارزمية توزيع السداد بنظام FIFO وحماية Concurrency
- [مؤكد] يقوم الإجراء بقفل سجلات الفواتير غير المسددة عبر `FOR UPDATE` بترتيب تاريخ الاستحقاق القديم أولاً:
  ```sql
  v_remaining_to_distribute := p_amount_paid;

  FOR v_invoice IN 
    SELECT * FROM public.invoices 
    WHERE customer_id = p_customer_id
      AND status IN ('Unpaid', 'Partially_Paid')
      AND (p_invoice_id IS NULL OR id = p_invoice_id)
    ORDER BY due_date ASC, id ASC
    FOR UPDATE
  LOOP
    IF v_remaining_to_distribute <= 0 THEN
      EXIT;
    END IF;

    v_allocated_amount := LEAST(v_remaining_to_distribute, v_invoice.remaining_amount);
    v_new_paid := v_invoice.paid_amount + v_allocated_amount;
    v_new_remaining := v_invoice.total_due - v_new_paid;
    v_new_status := CASE WHEN v_new_remaining <= 0 THEN 'Paid' ELSE 'Partially_Paid' END;

    -- تحديث الفاتورة
    UPDATE public.invoices 
    SET paid_amount = v_new_paid, remaining_amount = v_new_remaining, status = v_new_status
    WHERE id = v_invoice.id;

    -- إنشاء سجل تخصيص السداد
    INSERT INTO public.payment_allocations (
      payment_id, invoice_id, amount_allocated, is_reversed, created_at
    ) VALUES (
      v_payment_id, v_invoice.id, v_allocated_amount, false, p_payment_date
    );

    v_remaining_to_distribute := v_remaining_to_distribute - v_allocated_amount;
  END LOOP;
  ```

#### ج. معالجة الفائض وسجل الأرصدة الدائنة (Customer Credit Ledger)
- [مؤكد] إذا كان المبلغ المسدد أكبر من إجمالي الفواتير القائمة (`v_remaining_to_distribute > 0`):
  ```sql
  IF v_remaining_to_distribute > 0 THEN
    v_credit_amount := v_remaining_to_distribute;
    INSERT INTO public.customer_credits (
      customer_id, payment_id, amount, remaining_amount, status, created_at
    ) VALUES (
      p_customer_id, v_payment_id, v_credit_amount, v_credit_amount, 'AVAILABLE', p_payment_date
    );
  END IF;
  ```
- يُحسب الرصيد المتبقي الإجمالي للمشترك عبر:
  ```sql
  SELECT COALESCE(SUM(remaining_amount), 0) INTO v_updated_balance FROM public.invoices
  WHERE customer_id = p_customer_id AND status IN ('Unpaid', 'Partially_Paid');
  ```
- **استجابة JSON**:
  ```sql
  RETURN json_build_object(
    'success', true,
    'is_duplicate', false,
    'payment_id', v_payment_id,
    'receipt_number', v_receipt_number,
    'updated_balance', v_updated_balance,
    'credit_balance', v_credit_amount,
    'allocations', v_allocations
  );
  ```

---

### 3.3. التدقيق الفني لمرونة طابور المزامنة الأوفلاين (المتطلب R2.3)

#### أ. آلية تصنيف الأخطاء (Terminal vs Retryable Errors)
في `mobile_app/lib/services/sync_service.dart` (الأسطر 238-254):
```dart
bool _isTerminalSyncError(Object error) {
  final message = error.toString().toLowerCase();
  const terminalMarkers = [
    'cannot be less',
    'must be greater',
    'must be positive',
    'not found',
    'unauthorized',
    'forbidden',
    'invalid',
    'authentication required',
    'customer not found',
    'reading not found',
    'payment not found'
  ];
  return terminalMarkers.any(message.contains);
}
```

#### ب. عزل العناصر الفاشلة دون تعطيل باقي الطابور
في `sync_service.dart` (الأسطر 313-398):
- عند محاولة رفع كل قراءة أو دفعة:
  ```dart
  if (reading.isTerminalFailure) {
    _lastError ??= 'توجد قراءة مرفوضة سابقاً تحتاج مراجعة محلية';
    continue; // تجاوز العنصر المرفوض فوراً لمنع حظر الطابور
  }
  ```
- عند حدوث استثناء:
  ```dart
  final terminal = _isTerminalSyncError(e) || reading.retryCount >= 4;
  await LocalDbService.markPendingReadingFailure(
    reading.clientMutationId,
    error: friendlyMsg,
    terminal: terminal,
  );
  if (!terminal) allAcknowledged = false;
  ```
- **النتيجة الفنية [مؤكد]**: في حال فشل عنصر بسبب خطأ منطقي (مثل قراءة أقل من القراءة السابقة)، يتم تمييزه كـ `terminal: true` ويستمر التطبيق في مزامنة كافة العناصر اللاحقة الصالحة بدون أي توقف، كما يستمر في سحب البيانات الجديدة (`_pullCustomersFromSupabase`) دون عوائق.

---

### 3.4. تدقيق المصادقة وإدارة الجلسات JWT وأسبقية التوكن (المتطلب R3.1)

#### أ. ميدلوير المصادقة `authenticateToken`
في `backend/src/middleware/auth.middleware.ts` (الأسطر 40-116):

1. **المرحلة الأولى (Primary Local JWT Verification)**:
   - فك وتشفير التوكن عبر `jwt.verify(token, JWT_SECRET)` (السطر 51).
   - الاستعلام عن المستخدم في قاعدة البيانات المحلية Prisma عبر `prisma.user.findUnique({ where: { id: Number(decoded.id) } })`.
   - التحقق من تفعيل الحساب `dbUser.is_active`؛ إذا كان معطلاً يُعاد `403 Forbidden` ("تم إيقاف هذا الحساب أو تجميده").
   - تعيين `req.user = { id: dbUser.id, username: dbUser.username, role: dbUser.role, full_name: dbUser.full_name }` واستدعاء `next()`.

2. **المرحلة الثانية (Secondary Supabase Cloud Fallback)**:
   - في حال فشل التحقق المحلي (`catch (localJwtErr)`): يتم الاستعلام عبر `supabase.auth.getUser(token)` (السطر 78).
   - مطابقة المعرف `supabase_uid` أو اسم المستخدم مع السجل المحلي، والتأكد من فعالية الحساب ثم إرفاق `req.user`.

3. **المرحلة الثالثة (فشل المصادقة بالكامل)**:
   - إعادة كود `401 Unauthorized` (`{ success: false, message: 'رمز الجلسة غير صالح أو منتهي الصلاحية' }`).

#### ب. أسبقية تسجيل الدخول في الواجهة الأمامية (Frontend Login Precedence)
في `frontend/src/context/AuthContext.tsx` (الأسطر 78-148):
- يقوم تطبيق الويب بمحاولة تسجيل الدخول أولاً عبر `loginApi` (Express Backend `/api/auth/login`) واستلام توكن محلي مباشر.
- لا يتم اللجوء إلى مصادقة Supabase إلا في حال تعذر الوصول إلى سيرفر الباك إند المحلي.

---

### 3.5. تدقيق حدود الصلاحيات RBAC وفرض كود 403 Forbidden (المتطلب R3.2)

#### أ. ميدلوير فحص الأدوار `requireRole`
في `backend/src/middleware/auth.middleware.ts` (الأسطر 118-126):
```typescript
export const requireRole = (allowedRoles: string[]) => {
  return (req: AuthRequest, res: Response, next: NextFunction): void => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      res.status(403).json({ success: false, message: 'غير مصرح: ليس لديك الصلاحية لتنفيذ هذا الإجراء' });
      return;
    }
    next();
  };
};
```

#### ب. حماية مسارات تعريفات الاشتراك والخطط (Tariff / Subscription Plans)
في `backend/src/routes/plan.routes.ts` (الأسطر 1-13):
- `GET /api/plans` -> متاح لكافة الحسابات المعتمدة (`authenticateToken`).
- `POST /api/plans` -> محمي بـ `requireRole(['ADMIN'])` -> **يُعيد 403 Forbidden للمحصل (COLLECTOR) والمحاسب (ACCOUNTANT)**.
- `PUT /api/plans/:id` -> محمي بـ `requireRole(['ADMIN'])` -> **يُعيد 403 Forbidden للمحصل والمحاسب**.
- `DELETE /api/plans/:id` -> محمي بـ `requireRole(['ADMIN'])` -> **يُعيد 403 Forbidden للمحصل والمحاسب**.

#### ج. حماية مسارات إدارة المستخدمين والصلاحيات (Users Management)
في `backend/src/routes/user.routes.ts` (الأسطر 1-19):
- تم تطبيق `router.use(requireRole(['ADMIN']))` على كامل الراوتر (السطر 8).
- **النتيجة [مؤكد]**: أي محاولة من دور `COLLECTOR` للوصول إلى `GET /api/users` أو `POST /api/users` أو `PUT /api/users/:id` أو `POST /api/users/:id/reset-password` أو مسارات التعيينات `assignments` تُحظر فوراً بكود `403 Forbidden`.

#### د. حماية باقي المسارات الإدارية الحساسة
- **إعدادات النظام** (`backend/src/routes/settings.routes.ts` الأسطر 27-28): `PUT /api/settings` و `POST /api/settings/logo` محمية بـ `requireRole(['ADMIN'])` (403 للمحصل).
- **سجلات الرقابة** (`backend/src/routes/audit.routes.ts` السطر 8): الراوتر بالكامل محمي بـ `requireRole(['ADMIN'])` (403 للمحصل).
- **الاستيراد والتنظيف** (`backend/src/routes/import.routes.ts` السطر 36): الراوتر بالكامل محمي بـ `requireRole(['ADMIN'])` (403 للمحصل).
- **إدارة الواتساب** (`backend/src/routes/whatsapp.routes.ts` الأسطر 9-15): جميع عمليات الإرسال وإعادة التشغيل محمية بـ `requireRole(['ADMIN'])` (403 للمحصل).
- **اعتماد ورفض القراءات والسدادات** (`backend/src/routes/reading.routes.ts` و `payment.routes.ts`):
  - مسارات `approve`, `reject`, `update`, `approve-all` محصورة فقط بدور `ADMIN` (403 للمحصل).
  - مسار إنشاء القراءة `POST /api/readings`: يسمح للمحصل بتسجيل القراءة كـ `PENDING`، وإذا حاول إرسال `approval_status = 'APPROVED'` يتم رفض طلبه في السطر 34 بكود `403 Forbidden` ("اعتماد القراءة متاح للمدير فقط").

---

## 4. قائمة الملفات والأكواد المفحوصة (Evidence Files Index)

1. `backend/src/scripts/clean_and_unify_rpc.ts` — تعريف الماستر لـ `rpc_submit_meter_reading` ودوال تسلسل الدورات.
2. `backend/src/scripts/fix_postgrest_pgrst203.ts` — معالجة خطأ PGRST203 وحذف التوقيعات المتعددة.
3. `backend/src/scripts/unify_payment_rpc.ts` — تعريف الماستر لـ `rpc_submit_payment` وتوزيع FIFO للأرصدة.
4. `backend/src/services/financial-rpc.service.ts` — وسيط استدعاءات Prisma SQL RPC والترجمة العربية للأخطاء.
5. `backend/src/middleware/auth.middleware.ts` — مصادقة JWT المحلية والسحابية وميدلوير RBAC.
6. `backend/src/controllers/reading.controller.ts` — كونترولر القراءات والتحقق من صلاحية الاعتماد.
7. `backend/src/controllers/payment.controller.ts` — كونترولر السدادات والتحقق من المبالغ وتوليد السندات.
8. `backend/src/controllers/user.controller.ts` — إدارة المستخدمين وكلمات المرور والمزامنة مع Supabase.
9. `backend/src/routes/plan.routes.ts` — راوتر خطط الاشتراك وفرض كود 403.
10. `backend/src/routes/user.routes.ts` — راوتر المستخدمين وحصره بمدير النظام.
11. `backend/src/routes/settings.routes.ts` — راوتر الإعدادات وحصره بالمدير.
12. `backend/src/routes/reading.routes.ts` & `backend/src/routes/payment.routes.ts` — راوترات العمليات والصلاحيات.
13. `mobile_app/lib/services/sync_service.dart` — محرك المزامنة المتفائل والتعامل مع الأخطاء غير القابلة للإعادة.

</div>
