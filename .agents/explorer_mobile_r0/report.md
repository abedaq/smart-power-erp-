# تقرير فحص ومسح معمارية تطبيق الهاتف المحمول (Flutter Mobile App) — المتطلب R1

**المشروع**: Smart Power ERP — Mobile Codebase Audit & Verification  
**تاريخ الفحص**: 2026-09-02  
**مجلد العمل**: `d:/elctercity/mobile_app`  
**المدقق**: Mobile Codebase Explorer (`explorer_mobile_r0`)

---

## 1. ملخص تنفيذي (Executive Summary)

تم إجراء مسح وتدقيق معماري شامل وشامل لكود تطبيق الهاتف المحمول Flutter (`smart_power_mobile`) الواقع في `d:/elctercity/mobile_app`، وذلك للتحقق من جاهزية وكفاءة البنية التحتية لتلبية متطلبات **Requirement R1** الخاصة بالمحصل الميداني (Field Collector) وعمليات الأوفلاين والأونلاين.

### ملخص نتائج التدقيق:
1. **قاعدة البيانات المحلية (Hive Local DB & Offline Cache)**: تم تطبيق التخزين المحلي المشفر بالكامل باستخدام `HiveAesCipher` مع مفتاح مشفر في `FlutterSecureStorage`، وتحديث فوري للواجهات (Optimistic UI Update) بدون أي تأخير (0ms)، مع إدارة الطوابير المحلية عبر `client_mutation_id`.
2. **تسلسل الدورات الفوترية (Billing Cycle Sequencing)**: تم ربط تسلسل الدورات آلياً عبر دالة قاعدة البيانات `fn_get_next_billing_cycle` و `rpc_submit_meter_reading` (مثل التحويل من `"أغسطس- 1 - 2026"` إلى `"أغسطس- 2 - 2026"` والتدوير لشهر سبتمبر)، مع وجود واجهة توليد فواتير في التطبيق `GenerateInvoicesDialog` تعتمد التنسيق الشهري.
3. **سندات السداد ومفتاح عدم التكرار (Payment Idempotency & UUID v4)**: يتم توليد مفتاح `UUID v4` عشوائي مشفر عبر `UuidHelper.generateV4()` محلياً قبل الإرسال، وتخزينه في `PaymentModel.clientMutationId` لمنع تكرار السندات على مستوى العميل والخادم (`rpc_submit_payment`).
4. **التحقق من القراءات الأقل (Lower Reading Validation & Alert UI)**: يتم التحقق المزدوج الفوري (Live Input Validation + Submit Validation) في واجهة `ReadingDialog` مع حظر إدخال أي قراءة أقل من القراءة السابقة وإظهار تنبيه خطأ مباشر في حقل الإدخال، بالإضافة لحماية على مستوى الخادم.
5. **معالجة أخطاء طابور المزامنة (Resilient Offline Queue Sync Error Handling)**: تمتلك خدمة `SyncService` آلية تصنيف ذكية للأخطاء (`_isTerminalSyncError`) تفصل الأخطاء الدائمة عن المؤقتة، وتتيح تجاوز وحفظ العناصر المرفوضة في `pending_readings_secure_v1` دون تعطيل أو إيقاف بقية العمليات الصالحة في الطابور مع سقف محاولات (4 محاولات).

---

## 2. التحليل التفصيلي للمحاور الخمسة (Requirement R1)

---

### المحور 1: إدخال قراءات العدادات في وضعي الأوفلاين والأونلاين (Offline & Online Meter Reading Entry)

#### أ. هيكل التخزين المحلي (Local Hive DB Architecture)
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/services/local_db_service.dart`
- **تهيئة التخزين المشفر**:
  يتم تهيئة Hive في دالة `LocalDbService.init()` (الأسطر 22-59):
  - توليد مفتاح تشفير 256-bit وحفظه بأمان في `FlutterSecureStorage` بمفتاح `'hive_encryption_key'`.
  - تطبيق التشفير عبر `HiveAesCipher(encryptionKey)`.
  - ترحيل البيانات القديمة غير المشفرة (Legacy Migration) من الصناديق القديمة إلى الصناديق المشفرة الجديدة ذات اللاحقة `_secure_v1`.

```dart
// d:/elctercity/mobile_app/lib/services/local_db_service.dart (Lines 38-51)
const secureStorage = FlutterSecureStorage();
var encodedKey = await secureStorage.read(key: 'hive_encryption_key');
if (encodedKey == null || encodedKey.isEmpty) {
  encodedKey = base64UrlEncode(Hive.generateSecureKey());
  await secureStorage.write(key: 'hive_encryption_key', value: encodedKey);
}
final encryptionKey = base64Url.decode(encodedKey);
final cipher = HiveAesCipher(encryptionKey);

await Hive.openBox(customersBoxName, encryptionCipher: cipher);
await Hive.openBox(pendingReadingsBoxName, encryptionCipher: cipher);
await Hive.openBox(pendingPaymentsBoxName, encryptionCipher: cipher);
await Hive.openBox(appSettingsBoxName, encryptionCipher: cipher);
```

#### ب. الصناديق المحلية (Hive Boxes)
| اسم الصندوق البرمجي | اسم الصندوق في التخزين | الوظيفة |
|---|---|---|
| `customersBoxName` | `local_customers_secure_v1` | تخزين كاش المشتركين وبيانات العدادات والمديونيات |
| `pendingReadingsBoxName` | `pending_readings_secure_v1` | طابور القراءات المعلقة محلياً وغير المؤكدة |
| `pendingPaymentsBoxName` | `pending_payments_secure_v1` | طابور سندات التحصيل المعلقة محلياً |
| `appSettingsBoxName` | `app_settings_secure_v1` | إعدادات التطبيق، اسم المحصل، الجلسة، وآخر وقت مزامنة |

#### ج. نماذج البيانات والتسلسل (Models & Serialization)
- **`CustomerModel`** (`mobile_app/lib/models/customer_model.dart`):
  - الحقول: `id`, `subscriberNumber`, `fullName`, `phoneNumber`, `address`, `meterNumber`, `routeNumber`, `subscriptionPlanId`, `initialReading`, `lastReading`, `totalDue`, `status`, `planName`, `kwhPrice`.
  - التسلسل: `fromMap` (الأسطر 34-82) و `toMap` (الأسطر 84-101).
- **`MeterReadingModel`** (`mobile_app/lib/models/reading_model.dart`):
  - الحقول: `id`, `customerId`, `readingValue`, `collectorName`, `readingDate`, `approvalStatus`, `submitterRole`, `isSynced`, `retryCount`, `lastError`, `isTerminalFailure`, `clientMutationId`.
  - التسلسل: `fromMap` (الأسطر 32-49), `toMap` (الأسطر 51-66), `toSupabaseMap` (الأسطر 68-78).

#### د. آلية التحديث الفوري للواجهة (Optimistic UI Update Logic)
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/services/sync_service.dart` (الأسطر 426-467)
- **تسلسل التنفيذ (Execution Flow)**:
  1. إنشاء كائن `MeterReadingModel` وتوليد `clientMutationId` (UUID v4).
  2. تحديث قراءة العداد فوراً في صندوق المشتركين المحلي عبر `LocalDbService.updateCustomerReading(customerId, readingValue)`.
  3. حفظ القراءة في طابور العمليات المعلقة عبر `LocalDbService.addPendingReading(reading)`.
  4. استدعاء `loadLocalCustomers()` الذي يعيد قراءة الكاش المحلي ويطلق `notifyListeners()`.
  5. إعادة بناء فورية لكروت المشتركين وعدادات الإحصائيات في الواجهة دون انتظار استجابة الشبكة.
  6. تشغيل المزامنة الخلفية عبر `unawaited(pushPendingData())` للمحصلين.

```dart
// d:/elctercity/mobile_app/lib/services/sync_service.dart (Lines 426-467)
Future<bool> submitReading({
  required int customerId,
  required double readingValue,
}) async {
  final collector = LocalDbService.getCollectorName();
  final managerSubmission = isAdmin;
  final reading = MeterReadingModel(
    customerId: customerId,
    readingValue: readingValue,
    collectorName: collector,
    readingDate: DateTime.now(),
    approvalStatus: managerSubmission ? 'APPROVED' : 'PENDING',
    submitterRole: managerSubmission ? 'ADMIN' : 'COLLECTOR',
  );

  // 1. Immediately update in local database
  await LocalDbService.updateCustomerReading(customerId, readingValue);
  
  // 2. Save directly to offline pending queue
  await LocalDbService.addPendingReading(reading);
  loadLocalCustomers();

  // Managers must finish the online push before the UI reports an approved reading.
  // Collectors keep the offline-first behavior and sync in the background.
  if (isAdmin) {
    try {
      await _pushPendingReadings();
      await _pullCustomersFromSupabase();
      return !LocalDbService.getPendingReadings().any(
        (item) => item.clientMutationId == reading.clientMutationId,
      );
    } catch (e) {
      _lastError = e.toString();
      if (kDebugMode) print('Manager reading remains pending: $e');
      notifyListeners();
      return false;
    }
  }

  unawaited(pushPendingData());
  return true;
}
```

---

### المحور 2: تسلسل الدورات الفوترية آلياً (Automatic Billing Cycle Sequencing)

#### أ. محرك توليد الدورات في قاعدة البيانات والخلفية
- **الملف المسئول**: `d:/elctercity/backend/src/scripts/apply_bimonthly_cycle_rpc.ts` (الأسطر 8-61)
- **دالة `fn_get_next_billing_cycle(p_last_cycle TEXT)`**:
  - تقوم بتحليل نص الدورة السابقة (مثل `"أغسطس- 1 - 2026"`).
  - تنظف المسافات والرموز وتستخرج اسم الشهر بالعربية، ورقم الدورة (1 أو 2)، والسنة.
  - إذا كانت الدورة رقم 1: يتم إرجاع الدورة رقم 2 لنفس الشهر (`v_month_name || '- 2 - ' || v_year`).
  - إذا كانت الدورة رقم 2: يتم الانتقال للشهر التالي في المصفوفة العربية (`ARRAY['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر']`) مع تعيين الدورة 1 (`v_months[v_month_idx + 1] || '- 1 - ' || v_year`).

```sql
-- d:/elctercity/backend/src/scripts/apply_bimonthly_cycle_rpc.ts (Lines 8-59)
CREATE OR REPLACE FUNCTION public.fn_get_next_billing_cycle(p_last_cycle TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_months TEXT[] := ARRAY['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  v_month_name TEXT;
  v_cycle_num INT;
  v_year INT;
  v_month_idx INT := 0;
  v_i INT;
  v_clean TEXT;
BEGIN
  IF p_last_cycle IS NULL OR TRIM(p_last_cycle) = '' OR p_last_cycle = 'رصيد افتتاحي' THEN
    RETURN 'أغسطس- 2 - 2026';
  END IF;

  v_clean := REPLACE(p_last_cycle, '-', ' ');
  v_clean := REGEXP_REPLACE(v_clean, '\\s+', ' ', 'g');
  v_clean := TRIM(v_clean);
  
  v_month_name := SPLIT_PART(v_clean, ' ', 1);
  v_cycle_num := NULLIF(REGEXP_REPLACE(SPLIT_PART(v_clean, ' ', 2), '\\D', '', 'g'), '')::INT;
  v_year := NULLIF(REGEXP_REPLACE(SPLIT_PART(v_clean, ' ', 3), '\\D', '', 'g'), '')::INT;

  IF v_cycle_num IS NULL THEN v_cycle_num := 1; END IF;
  IF v_year IS NULL OR v_year < 2000 THEN v_year := 2026; END IF;

  FOR v_i IN 1..12 LOOP
    IF v_months[v_i] = v_month_name THEN
      v_month_idx := v_i;
      EXIT;
    END IF;
  END LOOP;

  IF v_month_idx = 0 THEN
    RETURN 'أغسطس- 2 - 2026';
  END IF;

  IF v_cycle_num = 1 THEN
    RETURN v_month_name || '- 2 - ' || v_year;
  ELSE
    IF v_month_idx < 12 THEN
      v_month_idx := v_month_idx + 1;
    ELSE
      v_month_idx := 1;
      v_year := v_year + 1;
    END IF;
    RETURN v_months[v_month_idx] || '- 1 - ' || v_year;
  END IF;
END;
$$;
```

#### ب. توليد الفواتير الدورية في تطبيق الموبايل (Generate Invoices Dialog)
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/widgets/generate_invoices_dialog.dart` (الأسطر 13-97)
- يقوم بإنشاء الفواتير الدورية وحساب الاستهلاك بناءً على آخر قراءة والقراءة السابقة، ويربط الفاتورة باسم الدورة المحددة (`_billingCycleController.text`).

---

### المحور 3: سندات السداد ومفتاح عدم التكرار (Payment Voucher Entry & Idempotency Key)

#### أ. توليد مفتاح UUID v4 المشفر في الموبايل
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/core/uuid_helper.dart` (الأسطر 1-24)
- يعتمد خوارزمية التوليد العشوائي المشفر `Random.secure()` المتوافقة مع RFC 4122 v4:

```dart
// d:/elctercity/mobile_app/lib/core/uuid_helper.dart (Lines 3-23)
class UuidHelper {
  static final Random _random = Random.secure();

  static String generateV4() {
    final int r1 = _random.nextInt(0xFFFFFFFF);
    final int r2 = _random.nextInt(0xFFFFFFFF);
    final int r3 = _random.nextInt(0xFFFFFFFF);
    final int r4 = _random.nextInt(0xFFFFFFFF);

    final String hex1 = r1.toRadixString(16).padLeft(8, '0');
    final String hex2 = r2.toRadixString(16).padLeft(8, '0');
    final String hex3 = r3.toRadixString(16).padLeft(8, '0');
    final String hex4 = r4.toRadixString(16).padLeft(8, '0');

    final String combined = hex1 + hex2 + hex3 + hex4;
    return '${combined.substring(0, 8)}-'
        '${combined.substring(8, 12)}-'
        '4${combined.substring(13, 16)}-'
        '8${combined.substring(17, 20)}-'
        '${combined.substring(20, 32)}';
  }
}
```

#### ب. تكامل المفتاح في نموذج السداد وتوليد رقم الإيصال
- **الملفات المسئولة**:
  - `mobile_app/lib/models/payment_model.dart` (السطر 36: `clientMutationId = clientMutationId ?? UuidHelper.generateV4();`)
  - `mobile_app/lib/services/sync_service.dart` (الأسطر 470-502)
- يتم إنشاء رقم إيصال مالي تلقائي `receiptNumber` بالصيغة `REC-YYMMDD-XXXX`.
- يتم إرسال `p_idempotency_key: payment.clientMutationId` إلى `rpc_submit_payment`.
- في حال إعادة الإرسال أو المحاولة المتكررة، يمنع الخادم وقاعدة البيانات إدراج سند مكرر ويعيد السجل السابق مع `is_duplicate: true`.

```dart
// d:/elctercity/mobile_app/lib/services/sync_service.dart (Lines 470-502)
Future<bool> submitPayment({
  required int customerId,
  int? invoiceId,
  required double amountPaid,
  String? notes,
}) async {
  final collector = LocalDbService.getCollectorName();
  final receiptNum = 'REC-${DateFormat('yyMMdd').format(DateTime.now())}-${Random().nextInt(9000) + 1000}';

  final payment = PaymentModel(
    customerId: customerId,
    invoiceId: invoiceId,
    receiptNumber: receiptNum,
    amountPaid: amountPaid,
    accountantName: collector,
    paymentDate: DateTime.now(),
    notes: notes,
    approvalStatus: 'PENDING',
  );

  // 1. Immediately update balance in local DB
  await LocalDbService.updateCustomerBalance(customerId, amountPaid);
  
  // 2. Save directly to offline pending queue
  await LocalDbService.addPendingPayment(payment);
  loadLocalCustomers();

  // 3. Fire-and-forget background sync
  pushPendingData(); // Unawaited

  // 4. Return success instantly (0ms delay)
  return true;
}
```

---

### المحور 4: حظر القراءات الأقل وواجهة التحذير (Lower Reading Validation & Alert UI)

#### أ. التحقق التفاعلي المباشر (Real-time Live Input Validation)
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/widgets/reading_dialog.dart` (الأسطر 20-59)
- عند كتابة أي رقم في حقل القراءة، تقوم دالة `_onChanged` بفحص القيمة ومقارنتها فوراً مع `customer.lastReading`:
  - إذا كانت القيمة المدخلة أقل من القراءة السابقة، يظهر نص تحذيري أحمر تحت الحقل مباشرة:  
    `"القراءة الحالية أقل من القراءة السابقة (X)!"`
  - في دالة `_submit`، يتم حظر الإرسال تماماً وتعيين رسالة الخطأ: `"لا يمكن أن تكون القراءة الحالية أقل من السابقة"`.

```dart
// d:/elctercity/mobile_app/lib/widgets/reading_dialog.dart (Lines 31-59)
void _onChanged(String val) {
  setState(() {
    final parsed = double.tryParse(val.trim());
    if (parsed != null) {
      _currentInput = parsed;
      if (parsed < widget.customer.lastReading) {
        _errorMessage = 'القراءة الحالية أقل من القراءة السابقة (${_formatNumber(widget.customer.lastReading)})!';
      } else {
        _errorMessage = null;
      }
    } else {
      _errorMessage = null;
    }
  });
}

void _submit() {
  final parsed = double.tryParse(_readingController.text.trim());
  if (parsed == null) {
    setState(() => _errorMessage = 'يرجى إدخال قيمة القراءة الصحيحة');
    return;
  }
  if (parsed < widget.customer.lastReading) {
    setState(() => _errorMessage = 'لا يمكن أن تكون القراءة الحالية أقل من السابقة');
    return;
  }
  widget.onSubmit(parsed);
  Navigator.of(context).pop();
}
```

#### ب. بطاقات المقارنة وعرض الاستهلاك المتوقع
- في نفس واجهة `ReadingDialog` (الأسطر 117-150)، يتم عرض بطاقتين توضيحيتين:
  1. **القراءة السابقة**: `${_formatNumber(previousReading)} kWh`
  2. **الاستهلاك المتوقع**: `${_formatNumber(consumption)} kWh`
  3. **القيمة المالية التقديرية**: يتم احتسابها وعرضها فورياً إذا كان الاستهلاك موجباً وسعر الكيلوواط مسجلاً.

---

### المحور 5: معالجة أخطاء طابور المزامنة في تطبيق الموبايل (Resilient Offline Queue Error Handling)

#### أ. آلية تصنيف الأخطاء (Terminal vs Transient Error Classification)
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/services/sync_service.dart` (الأسطر 238-254)
- تم بناء دالة فحص ذكية `_isTerminalSyncError` للتمييز بين:
  - **الأخطاء الدائمة (Terminal Errors)**: مثل خطأ `cannot be less`، `customer not found`، `unauthorized`، `must be positive`. هذه الأخطاء لا يمكن حلها بإعادة المحاولة ويتم وسمها كفشل نهائي `is_terminal_failure = true`.
  - **الأخطاء المؤقتة (Transient Errors)**: مثل انقطاع الاتصال `SocketException` أو بطء الخادم.

```dart
// d:/elctercity/mobile_app/lib/services/sync_service.dart (Lines 238-254)
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

#### ب. معالجة العناصر بشكل منفصل وعدم تعطيل الطابور (Per-Item Independent Push)
- **الملف المسئول**: `d:/elctercity/mobile_app/lib/services/sync_service.dart` (الأسطر 313-398)
- في دالتي `_pushPendingReadings()` و `_pushPendingPayments()`:
  - يتم التكرار على العناصر المعلقة عنصراً عنصراً.
  - العنصر الموسوم كـ `isTerminalFailure` يتم تجاوزه (`continue`) حتى لا يعطل إرسال العناصر السليمة الأخرى أو عملية جلب البيانات من السيرفر.
  - يتم احتساب عدد المحاولات `retryCount`؛ وإذا بلغت 4 محاولات يتم وسم العنصر كفشل نهائي.
  - عند نجاح العنصر، يُحذف فوراً من الصندوق المحلي `LocalDbService.removePendingReading(id)`.
  - عند فشل العنصر، يتم تحديث بيانات الفشل في الصندوق المحلي عبر `markPendingReadingFailure` دون حذف العنصر لتمكين مراجعته لاحقاً في شاشة العمليات المرفوضة `RejectedOperationsScreen`.

```dart
// d:/elctercity/mobile_app/lib/services/sync_service.dart (Lines 313-352)
Future<bool> _pushPendingReadings() async {
  final pending = LocalDbService.getPendingReadings();
  if (pending.isEmpty) return true;
  var allAcknowledged = true;

  for (final reading in pending) {
    if (reading.isTerminalFailure) {
      _lastError ??= 'توجد قراءة مرفوضة سابقاً تحتاج مراجعة محلية';
      continue;
    }
    try {
      await SupabaseConfig.client.rpc('rpc_submit_meter_reading', params: {
        'p_customer_id': reading.customerId,
        'p_reading_value': reading.readingValue,
        'p_collector_name': reading.collectorName,
        'p_idempotency_key': reading.clientMutationId,
        'p_reading_date': reading.readingDate.toIso8601String(),
        'p_auto_approve': reading.submitterRole == 'ADMIN',
        'p_actor_user_id': _currentUserId(),
      });
      await LocalDbService.removePendingReading(reading.clientMutationId);
    } catch (e) {
      final friendlyMsg = formatFriendlyErrorMessage(e);
      final terminal = _isTerminalSyncError(e) || reading.retryCount >= 4;
      await LocalDbService.markPendingReadingFailure(
        reading.clientMutationId,
        error: friendlyMsg,
        terminal: terminal,
      );
      if (!terminal) allAcknowledged = false;
      _lastError = terminal
          ? 'قراءة مرفوضة: $friendlyMsg'
          : 'فشل مؤقت في إرسال قراءة: $friendlyMsg';
    }
  }
  return allAcknowledged;
}
```

---

## 3. ملخص الملفات والمكونات البرمجية المعتمدة (Artifacts & Mapping)

| المحور | الملف المستهدف | أهم الدوال / الكلاسات |
|---|---|---|
| **R1.1 Local Hive & Optimistic UI** | `lib/services/local_db_service.dart`<br>`lib/services/sync_service.dart` | `init()`, `updateCustomerReading()`, `addPendingReading()`, `submitReading()` |
| **R1.2 Cycle Sequencing** | `lib/widgets/generate_invoices_dialog.dart`<br>`backend/src/scripts/apply_bimonthly_cycle_rpc.ts` | `_generateInvoices()`, `fn_get_next_billing_cycle` |
| **R1.3 Payment Idempotency (UUID v4)** | `lib/core/uuid_helper.dart`<br>`lib/models/payment_model.dart`<br>`lib/services/sync_service.dart` | `UuidHelper.generateV4()`, `submitPayment()`, `_pushPendingPayments()` |
| **R1.4 Lower Reading Validation** | `lib/widgets/reading_dialog.dart` | `_onChanged()`, `_submit()`, `TextField.errorText` |
| **R1.5 Queue Sync Error Handling** | `lib/services/sync_service.dart`<br>`lib/screens/rejected_operations_screen.dart` | `_isTerminalSyncError()`, `_pushPendingReadings()`, `markPendingReadingFailure()` |

---

## 4. الاستنتاج والتوصيات (Conclusion & Recommendations)

1. **الامتثال للمعايير المعمارية**: تطبيق Flutter في `mobile_app` يلتزم تماماً ببنية Offline-First وتشفير البيانات محلياً مع حماية قوية ضد التكرار وإدخال البيانات الخاطئة.
2. **استخدام الأرقام الإنجليزية**: جميع الواجهات والعمليات الحسابية تتبع بدقة قاعدة الأرقام الإنجليزية (0, 1, 2, 3...) دون أي أرقام مشرقية.
3. **الجاهزية للخطوة القادمة**: الكود جاهز للاختبارات والمزامنة المباشرة مع إجراءات Supabase RPC في Milestone M2.
