# الخطة التنفيذية والهندسية الشاملة: النظام المحلي المستقل بالكامل (100% Local Standalone ERP)

## 1. الملخص الفني للتحول المعماري
تحويل منظومة إدارة محطة الكهرباء من بنية سحابية هجينة إلى **نظام محلي مستقل بالكامل يعمل على بيئة Windows دون أي اعتمادية على الإنترنت أو سحابة Supabase لتشغيل العمليات اليومية**.

---

## 2. شكل ومخطط النظام بعد التغيير (Target Architecture)

```mermaid
flowchart TD
    subgraph Station_PC["جهاز المحطة المكتبي (Station Windows PC)"]
        
        subgraph UI_Tier["1. طبقة الواجهة وسطح المكتب (React Desktop)"]
            ExcelGrid["شبكة القراءات السريعة (ExcelGrid)"]
            InvoiceA5["نموذج الفاتورة A5 ذو الوصلين (InvoiceModal)"]
            CashierModal["نافذة التحصيل والسندات (PaymentModal)"]
            ReportsDashboard["لوحة التحكم والتقارير المالية"]
        end

        subgraph Local_Backend["2. خادم العمليات والخدمات المحلي (Local Node.js Engine)"]
            LocalAPI["خادم Express API المحلي (Port 3000)"]
            FinancialBrain["محرك الحسابات المالية وإعادة ضبط الدورات (Recalculation)"]
            ExcelWorker["محرك معالجة الإكسل بالدفعات (SheetJS / ExcelJS)"]
            PuppeteerRenderer["محرك تصوير الفواتير (Puppeteer Headless)"]
            BaileysWA["محرك الواتساب وطابور الإرسال (Baileys)"]
            BackupScheduler["مجدول النسخ الاحتياطي التلقائي (Daily Dumps)"]
        end

        subgraph Local_Data["3. قاعدة البيانات والملفات المحلية (Local Data Storage)"]
            LocalPostgres[(قاعدة بيانات PostgreSQL المحلية)]
            UploadsDir[مجلد الشعار والملفات AppData/uploads]
            BackupsDir[مجلد النسخ الاحتياطية المحلي]
        end

        A5Printer["طابعة الفواتير الورقية A5 المعتمدة"]
    end

    ExternalUSB["فلاش ميموري خارجي للنسخ الاحتياطي (USB Backup)"]
    WhatsAppCloud((شبكة واتساب المشتركين))

    %% Connections
    UI_Tier -- "استعلامات وإدخال محلي فوري (0ms)" --> LocalAPI
    LocalAPI --> FinancialBrain
    FinancialBrain --> LocalPostgres
    
    %% Invoicing
    UI_Tier -- "طباعة فورية للنموذج A5 ذو الوصلين" --> A5Printer
    
    %% Excel
    UI_Tier -- "استيراد وتصدير إكسل فوري" --> ExcelWorker
    ExcelWorker --> LocalPostgres

    %% WhatsApp
    LocalPostgres -- "طابور رسائل محلي whatsapp_queue_messages" --> PuppeteerRenderer
    PuppeteerRenderer --> BaileysWA
    BaileysWA -. "إرسال تلقائي فقط عند توفر أي اتصال مؤقت بالإنترنت" .-> WhatsAppCloud

    %% Backup
    BackupScheduler -- "نسخ احتياطي يومي تلقائي" --> BackupsDir
    BackupsDir -- "تصدير نسخة إضافية آمنة" --> ExternalUSB
```

---

## 3. تفصيل كل ما سيتغير في النظام (Inventory of Changes)

### أولاً: قاعدة البيانات المحلية (Local PostgreSQL Setup)
1. **توجيه الاتصال**: تعديل ملفات البيئة `.env` في المشروع لاستخدام رابط قاعدة البيانات المحلية:
   `DATABASE_URL="postgresql://postgres:password@localhost:5432/smartpower_db"`
2. **تجهيز الجداول المحلية عبر Prisma**:
   - تطبيق `prisma db push` / `prisma migrate deploy` لتثبيت الهيكل الكامل على قاعدة البيانات المحلية.
   - تهيئة جداول: `customers`, `meter_readings`, `invoices`, `payments`, `payment_allocations`, `customer_credits`, `system_settings`, `users`, `audit_logs`, `whatsapp_queue_messages`, `import_jobs`.
3. **تثبيت الدوال المالية المخزنة (Local Stored Procedures)**:
   - تثبيت دوال الـ SQL المحسوبة محلياً (`rpc_submit_meter_reading`, `rpc_submit_payment`, `rpc_approve_meter_reading`, `rpc_recalculate_customer_invoices`).

### ثانياً: الخادم المحلي (Backend Engine)
1. **عزل خادم Express**:
   - إزالة أي استدعاءات متبقية لـ Supabase Remote Client من كود الباك إند.
   - تشغيل الخادم على المنفذ المحلي `3000` ليخدم واجهة سطح المكتب بنمط استجابة فوري ($0\text{ms}$).
2. **محرك الواتساب المجدول (`Baileys`)**:
   - إدارة جلسة الواتساب محلياً في مجلد `.baileys_auth`.
   - سحب الرسائل من جدول `whatsapp_queue_messages` المحلي وإرسالها بمجرد اتصال الجهاز بالإنترنت.
3. **محرك تصوير الفواتير (`Puppeteer`)**:
   - تصوير الفواتير من قوالب EJS المعتمدة بناءً على بيانات قاعدة البيانات المحلية حصرياً.
4. **نظام النسخ الاحتياطي المدمج (`BackupService`)**:
   - جدولة نسخ احتياطي محلي يومي لقاعدة البيانات والملفات.
   - إضافة مسار تصدير إضافي إلى وحدة تخزين خارجية (USB Drive).

### ثالثاً: واجهة سطح المكتب (React Desktop)
1. **توجيه الـ API**:
   - ضبط `frontend/src/lib/api.ts` للاتصال المباشر والدائم بخادم `http://localhost:3000/api`.
2. **تثبيت نموذج الفاتورة A5 ذو الوصلين**:
   - الحفاظ التام على نموذج الطباعة الحالي في `InvoiceModal.tsx` و `InvoicePreviewModal.tsx` المطابق لنموذج الوصلين الرسمي (كوبون المحصل + الفاتورة الرسمية).
   - فرض الترقيم المركب `INV-[Cycle]-[SubscriberNumber]` في حقل رقم الفاتورة.
   - فرض الأرقام الإنجليزية (0, 1, 2, 3...) بنسبة 100%.
3. **شبكة الإدخال السريعة (`ExcelGrid`)**:
   - إدخال القراءات وحفظها فورياً في الخادم المحلي مع المعاينة البصرية اللحظية بدون أي بطء.

### رابعاً: الحذف والتنظيف (Deprecations)
1. **حذف تطبيق الموبايل**:
   - حذف مجلد `mobile_app/` بالكامل.
   - حذف ملف حزمة `SmartPowerCollector_v2.apk`.
   - تنظيف أي ملفات غير مستخدمة خاصة بربط الموبايل.

---

## 4. الخطة التنفيذية الميدانية خطوة بخطوة

### المرحلة 1: إعداد قاعدة البيانات المحلية والبيئة
- تجهيز قاعدة بيانات PostgreSQL المحلية (`smartpower_db`).
- تحديث ملفات `.env` وتطبيق مخطط Prisma.
- استيراد وتثبيت الدوال المالية المحلية.

### المرحلة 2: ضبط وتجهيز خادم الباك إند المحلي
- تحديث إعدادات اتصال Prisma في `backend/src/lib/prisma.ts`.
- التحقق من عمل مسارات الـ API (المشتركين، القراءات، الفواتير، السندات، الإكسل، التقارير).
- تفعيل خدمة الواتساب ومجدول النسخ الاحتياطي التلقائي.

### المرحلة 3: تدقيق وتجهيز واجهة سطح المكتب (React Desktop)
- توجيه اتصال الـ API إلى `localhost:3000`.
- التأكد من ثبات وتناسق نموذج الفاتورة A5 ذو الوصلين في `InvoiceModal.tsx`.
- تدقيق شبكة `ExcelGrid` والتأكد من انسيابية حركة الأسهم وحفظ الخلايا.
- فحص تطبيق الأرقام الإنجليزية في كافة الشاشات.

### المرحلة 4: حذف تطبيق الموبايل واختبار النظام بالكامل
- حذف مجلد `mobile_app/` وملحقاته بأمان.
- إجراء اختبار شامل: (إدخال قراءات -> طباعة فواتير A5 -> تسجيل تحصيلات -> استيراد إكسل -> إرسال واتساب تجريبي -> نسخ احتياطي).
