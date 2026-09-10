<div dir="rtl">

# خريطة واجهات برمجة التطبيقات (API Contract)

هذا الملف يوثق جميع واجهات برمجة التطبيقات (API) المتوفرة حالياً في الـ Backend والتي **يجب** أن يستهلكها تطبيق Flutter (بدلاً من اتصاله المباشر بـ Supabase).

## 1. تسجيل قراءة جديدة
- **METHOD:** `POST`
- **PATH:** `/api/readings`
- **AUTH:** Bearer Token (JWT)
- **REQUEST BODY:**
  ```json
  {
    "customer_id": 123,
    "reading_value": 4500,
    "collector_name": "اسم المحصل",
    "approval_status": "PENDING" // أو "APPROVED"
  }
  ```
- **VALIDATION:** يتم التحقق من وجود المشترك.
- **BUSINESS LOGIC:** حساب الاستهلاك، حساب المتأخرات، إصدار فاتورة جديدة `Invoice`، تحديد تاريخ الاستحقاق.
- **DATABASE WRITE:** `MeterReading`, `Invoice`, `AuditLog`.
- **RESPONSE:** `201 Created` مع بيانات `newReading` و `invoice`.
- **FLUTTER CONSUMER:** يجب استخدامه عند عمل Sync للقراءات المعلقة.

## 2. تسجيل سداد جديد
- **METHOD:** `POST`
- **PATH:** `/api/payments`
- **AUTH:** Bearer Token (JWT)
- **REQUEST BODY:**
  ```json
  {
    "customer_id": 123,
    "amount_paid": 5000,
    "payment_method": "CASH",
    "notes": "ملاحظات",
    "accountant_name": "اسم المحصل"
  }
  ```
- **VALIDATION:** التحقق من قيمة المبلغ > 0، وجود المشترك، وجود فواتير معلقة.
- **BUSINESS LOGIC:** إنشاء رقم سند Receipt Number، توزيع المبلغ على الفواتير المعلقة (Waterfall Allocation)، تحديث حالة الفواتير إلى Paid أو Partially_Paid، تحديث الرصيد.
- **DATABASE WRITE:** `Payment`, `PaymentAllocation`, `Invoice` (Updates), `AuditLog`.
- **RESPONSE:** `201 Created` مع تفاصيل `payment` والـ `allocations`.
- **FLUTTER CONSUMER:** يجب استخدامه عند عمل Sync للسدادات المعلقة.

## 3. جلب بيانات المشتركين
- **METHOD:** `GET`
- **PATH:** `/api/customers`
- **AUTH:** Bearer Token (JWT)
- **REQUEST BODY:** لا يوجد.
- **VALIDATION:** لا يوجد.
- **BUSINESS LOGIC:** جلب بيانات المشتركين مع الفواتير والرصيد الحالي.
- **DATABASE WRITE:** لا يوجد.
- **RESPONSE:** `200 OK` (قائمة ببيانات المشتركين).
- **FLUTTER CONSUMER:** يجب استخدامه في دالة `syncAll` بدلاً من استعلامات Supabase.

## 4. تسجيل الدخول
- **METHOD:** `POST`
- **PATH:** `/api/auth/login`
- **AUTH:** لا يوجد.
- **REQUEST BODY:**
  ```json
  {
    "username": "user1",
    "password": "password123"
  }
  ```
- **VALIDATION:** التحقق من كلمة المرور (BCrypt).
- **BUSINESS LOGIC:** التأكد من فعالية الحساب (is_active)، وصلاحية المحصل (role). إنشاء JWT Token.
- **DATABASE WRITE:** `AuditLog` (تسجيل الدخول).
- **RESPONSE:** `200 OK` مع `token` وبيانات المستخدم.
- **FLUTTER CONSUMER:** يجب استخدامه في شاشة `LoginScreen`.

</div>
