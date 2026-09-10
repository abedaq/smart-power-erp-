<div dir="rtl">

# مصدر الحقيقة لقواعد الأعمال (Business Logic Source of Truth)

تحليل معمق لأماكن تنفيذ العمليات الحسابية والمالية في النظام.

## 1. الاستهلاك (Consumption)
- **التقييم:** DUPLICATED
- **Backend:** `backend/src/controllers/reading.controller.ts` (السطر 28: `consumption = Math.max(0, reading_value - previous_reading)`)
- **Flutter:** `mobile_app/lib/widgets/reading_dialog.dart` (السطر 64: `int consumption = (_currentInput > previousReading) ? (_currentInput - previousReading) : 0;`)
- **المدخلات:** القراءة الحالية، القراءة السابقة.
- **المخرجات:** كمية الاستهلاك.
- **مصدر القراءة السابقة:** قاعدة البيانات (Backend) أو Hive (Flutter).
- **مصدر القراءة الحالية:** إدخال المستخدم.

## 2. الفاتورة (Invoice) وإجمالي الفاتورة
- **التقييم:** DUPLICATED
- **Backend:** `backend/src/controllers/reading.controller.ts` (السطر 58: `totalDue = consumptionValue + fixedFee + arrears;`)
- **Flutter:** `mobile_app/lib/widgets/reading_dialog.dart` (السطر 65: `double estimatedCost = consumption * widget.customer.kwhPrice;`) - حساب تقديري.
- **المدخلات:** الاستهلاك، سعر الكيلوواط، الرسوم الثابتة، المتأخرات.
- **المخرجات:** إجمالي الفاتورة.
- **مصدر السعر:** `SubscriptionPlan` أو `SystemSettings`.

## 3. الرصيد / المتأخرات (Balance / Arrears / Previous Balance)
- **التقييم:** DUPLICATED
- **Backend:** 
  - `reading.controller.ts` (السطر 44: يجمع الفواتير غير المدفوعة).
  - `payment.controller.ts` (السطر 93: يجمع الفواتير غير المدفوعة لحساب الرصيد المتبقي).
- **Flutter:** 
  - `sync_service.dart` (السطر 114: يجمع `remaining_amount` من الفواتير المسترجعة).
  - `local_db_service.dart` (السطر 51: يخصم قيمة السداد من الرصيد المحلي `newDue = currentDue - paidAmount;`).
- **المدخلات:** الفواتير غير المدفوعة، المبالغ المسددة.
- **المخرجات:** الرصيد الإجمالي المستحق على المشترك.

## 4. التعرفة / السعر (Tariff / Price / Package)
- **التقييم:** BACKEND (مع نسخ محلية في Flutter)
- **Backend:** `schema.prisma` (`SubscriptionPlan` و `SystemSettings`). `reading.controller.ts` يحدد السعر بناءً عليها.
- **Flutter:** `sync_service.dart` (السطر 85) يجلب `kwh_price` ويخزنه محلياً.

## 5. الخصم (Discount)
- **التقييم:** UNKNOWN
- CANNOT CONFIRM FROM CURRENT SOURCE

## 6. الضريبة (Tax)
- **التقييم:** UNKNOWN
- CANNOT CONFIRM FROM CURRENT SOURCE

## 7. الإجمالي (Total)
- **التقييم:** DUPLICATED
- يتم حسابه في Backend عند إنشاء الفاتورة، ويتم تقديره في Flutter وتحديثه محلياً عند السداد في `local_db_service.dart`.

## الخلاصة
القواعد المالية موزعة بشكل خطير بين Backend و Flutter. تطبيق Flutter يقوم بتحديثات متفائلة (Optimistic) للأرصدة محلياً، بينما يقوم Backend بحساباتها بشكل مستقل. يجب أن تكون جميع القواعد في **BACKEND** فقط.

</div>
