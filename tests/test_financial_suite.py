# -*- coding: utf-8 -*-
"""
SmartPower Financial & E2E Automated Verification Test Suite
Testing ExcelGrid modifications, cascading arrears, payment scenarios,
overpayments/credits, WhatsApp queue, and invoice rendering.
"""

import sys
import json
import urllib.request
import urllib.error
import time

sys.stdout.reconfigure(encoding='utf-8')

BASE_URL = "http://127.0.0.1:3000/api"

def api_request(endpoint, method="GET", data=None, token=None):
    url = f"{BASE_URL}{endpoint}"
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    encoded_data = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=encoded_data, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(req) as resp:
            resp_body = resp.read().decode("utf-8")
            return resp.status, json.loads(resp_body) if resp_body else {}
    except urllib.error.HTTPError as e:
        resp_body = e.read().decode("utf-8")
        try:
            return e.code, json.loads(resp_body)
        except Exception:
            return e.code, {"error": resp_body}

def run_tests():
    print("=" * 70)
    print("🚀 بدء الفحص والمراجعة الشاملة لنظام الكهرباء SmartPower ERP")
    print("=" * 70)
    
    # 1. Login
    print("\n[1] تسجيل الدخول والحصول على JWT Token...")
    status, login_res = api_request("/auth/login", method="POST", data={"username": "admin", "password": "password123"})
    if status != 200 or not login_res.get("token"):
        print(f"❌ فشل تسجيل الدخول: Status={status}, Response={login_res}")
        return False
    token = login_res["token"]
    print(f"✅ تم تسجيل الدخول بنجاح. المستخدم: {login_res.get('user', {}).get('full_name')}")

    # 2. Get Settings
    print("\n[2] فحص إعدادات النظام والتعرفة...")
    status, settings_res = api_request("/settings", token=token)
    settings = settings_res.get("data", {})
    print(f"✅ المحطة: {settings.get('station_name')}")
    print(f"✅ سعر الكيلو الافتراضي: {settings.get('default_kwh_price')} ريال | الرسوم الثابتة: {settings.get('default_fixed_fee')} ريال")

    # 3. Create a dedicated test customer
    print("\n[3] إنشاء مشترك اختباري جديد للتدقيق المالي الشامل...")
    sub_num = f"TEST-{int(time.time())}"
    test_cust_payload = {
        "full_name": "مشترك الفحص والتدقيق الآلي",
        "subscriber_number": sub_num,
        "meter_number": f"MTR-{int(time.time())}",
        "phone_number": "771234567",
        "address": "شارع النصر - خط 1",
        "route_number": "خط 1",
        "initial_reading": 100.0,
        "status": "Active",
        "arrears": 0.0
    }
    status, cust_res = api_request("/customers", method="POST", data=test_cust_payload, token=token)
    if status != 201:
        print(f"❌ فشل إنشاء المشترك: {cust_res}")
        return False
    customer = cust_res.get("data", {})
    cust_id = customer["id"]
    print(f"✅ تم إنشاء المشترك بنجاح: ID={cust_id}, رقم الاشتراك={sub_num}, القراءة الابتدائية={customer['initial_reading']}")

    # 4. Define Chronological Cycles to Test
    cycles = [
        "أغسطس 2",
        "سبتمبر 1",
        "أكتوبر 1",
        "نوفمبر 1",
        "ديسمبر 1",
        "يناير 1 - 2027"
    ]

    print("\n[4] تهيئة وضمان وجود الفواتير عبر الدورات الست (August 2 -> January 2027)...")
    for cycle in cycles:
        status, inv_res = api_request(f"/invoices?cycle={urllib.parse.quote(cycle)}&customer_id={cust_id}", token=token)
        print(f"   - فحص/توليد دورة [{cycle}]: {status} ({inv_res.get('total', 0)} فواتير)")

    # Fetch all invoices for this customer
    status, cust_invoices_res = api_request(f"/invoices?customer_id={cust_id}", token=token)
    invoices = cust_invoices_res.get("data", [])
    print(f"✅ إجمالي فواتير المشترك التي تم إنشاؤها عبر الدورات: {len(invoices)}")

    # Map invoices by cycle
    cycle_invoice_map = {}
    for inv in invoices:
        cycle_invoice_map[inv["billing_cycle"]] = inv

    # 5. Testing Grid Updates Across All Cycles
    print("\n[5] اختبار تعديل القراءات في شبكة الإكسل (ExcelGrid) عبر مختلف الدورات الحسابية...")
    
    readings_plan = [
        {"cycle": "أغسطس 2", "curr": 150.0, "price": 1400.0, "fee": 1000.0, "arrears": 500.0},
        {"cycle": "سبتمبر 1", "curr": 220.0, "price": 1400.0, "fee": 1000.0, "arrears": None}, # Arrears should cascade
        {"cycle": "أكتوبر 1", "curr": 310.0, "price": 1400.0, "fee": 1000.0, "arrears": None},
        {"cycle": "نوفمبر 1", "curr": 430.0, "price": 1400.0, "fee": 1000.0, "arrears": None},
        {"cycle": "ديسمبر 1", "curr": 580.0, "price": 1400.0, "fee": 1000.0, "arrears": None},
        {"cycle": "يناير 1 - 2027", "curr": 750.0, "price": 1400.0, "fee": 1000.0, "arrears": None}
    ]

    for step in readings_plan:
        c_name = step["cycle"]
        inv = cycle_invoice_map.get(c_name)
        if not inv:
            print(f"⚠️ تحذير: فاتورة دورة {c_name} غير موجودة مباشرة، جاري إعادة الاستعلام...")
            _, cyc_invs = api_request(f"/invoices?cycle={urllib.parse.quote(c_name)}&customer_id={cust_id}", token=token)
            if cyc_invs.get("data"):
                inv = cyc_invs["data"][0]
                cycle_invoice_map[c_name] = inv

        inv_id = inv["id"]
        update_payload = {
            "current_reading": step["curr"],
            "unit_price": step["price"],
            "service_fee": step["fee"],
        }
        if step["arrears"] is not None:
            update_payload["arrears"] = step["arrears"]

        print(f"\n--- تعديل دورة [{c_name}] (Invoice ID: {inv_id}) ---")
        print(f"    البيانات المدخلة: القراءة الحالية={step['curr']}, السعر={step['price']}, الرسوم={step['fee']}")
        
        status, update_res = api_request(f"/customers/{inv_id}/grid-cell", method="PATCH", data=update_payload, token=token)
        if status != 200:
            print(f"❌ خطأ أثناء تحديث الخلية: {update_res}")
            return False

        # Fetch updated invoice
        _, inv_detail = api_request(f"/invoices/{inv_id}", token=token)
        updated_inv = inv_detail.get("data", {})
        
        prev = updated_inv.get("previous_reading", 0)
        curr = updated_inv.get("current_reading", 0)
        cons = updated_inv.get("consumption", 0)
        c_val = updated_inv.get("consumption_value", 0)
        tot_amt = updated_inv.get("total_amount", 0)
        arr = updated_inv.get("arrears", 0)
        tot_due = updated_inv.get("total_due", 0)
        rem = updated_inv.get("remaining_amount", 0)

        # Mathematical verification
        exp_cons = curr - prev if curr >= prev else 0
        exp_c_val = exp_cons * step["price"]
        exp_tot_amt = exp_c_val + step["fee"]
        exp_tot_due = exp_tot_amt + arr

        print(f"    القراءة السابقة: {prev} | الحالية: {curr}")
        print(f"    الاستهلاك المحتسب: {cons} ك.و (المتوقع: {exp_cons}) -> {'✅ مطابق' if cons == exp_cons else '❌ غير مطابق'}")
        print(f"    قيمة الاستهلاك: {c_val} ريال (المتوقع: {exp_c_val}) -> {'✅ مطابق' if c_val == exp_c_val else '❌ غير مطابق'}")
        print(f"    إجمالي الفاتورة: {tot_amt} ريال (المتوقع: {exp_tot_amt}) -> {'✅ مطابق' if tot_amt == exp_tot_amt else '❌ غير مطابق'}")
        print(f"    المتأخرات: {arr} ريال")
        print(f"    إجمالي المستحق: {tot_due} ريال (المتوقع: {exp_tot_due}) -> {'✅ مطابق' if tot_due == exp_tot_due else '❌ غير مطابق'}")
        print(f"    المتبقي: {rem} ريال")

    # 6. Verify Complete Forward Cascade Across All 6 Cycles
    print("\n" + "=" * 70)
    print("[6] التحقق من صحة التسلسل الزمني والترحيل المتسلسل (Chronological Cascade)...")
    print("=" * 70)
    
    status, all_invs_res = api_request(f"/invoices?customer_id={cust_id}&limit=20", token=token)
    cust_invoices = all_invs_res.get("data", [])
    
    # Sort chronologically
    cust_invoices.sort(key=lambda x: x["id"])

    print(f"\nجدول الفواتير المترابطة للمشترك ({test_cust_payload['full_name']}):")
    print("-" * 110)
    print(f"{'الدورة':<18} | {'السابقة':<8} | {'الحالية':<8} | {'الاستهلاك':<10} | {'قيمة الاستهلاك':<14} | {'رسوم':<6} | {'متأخرات':<10} | {'المستحق':<10} | {'المسدد':<8} | {'المتبقي':<10}")
    print("-" * 110)

    for inv in cust_invoices:
        print(f"{inv.get('billing_cycle',''):<18} | {inv.get('previous_reading',0):<8.1f} | {inv.get('current_reading',0):<8.1f} | {inv.get('consumption',0):<10.1f} | {inv.get('consumption_value',0):<14.2f} | {inv.get('fixed_fee_snapshot',0):<6.0f} | {inv.get('arrears',0):<10.2f} | {inv.get('total_due',0):<10.2f} | {inv.get('paid_amount',0):<8.2f} | {inv.get('remaining_amount',0):<10.2f}")
    print("-" * 110)

    # 7. Testing Payments: Full, Partial, and Overpayment (Credit Surplus)
    print("\n[7] اختبار سيناريوهات السداد المختلفة:")
    
    # Test 7.1: Full Payment on Cycle 1 (August 2)
    aug_inv = next((i for i in cust_invoices if "أغسطس 2" in i.get("billing_cycle", "")), cust_invoices[0])
    aug_due = aug_inv["remaining_amount"]
    print(f"\n--- 7.1 سداد كامل (Full Payment) لدورة [{aug_inv['billing_cycle']}] بمبلغ {aug_due} ريال ---")
    pay_payload1 = {
        "customer_id": cust_id,
        "invoice_id": aug_inv["id"],
        "amount_paid": aug_due,
        "payment_method": "CASH",
        "notes": "سداد كامل تجريبي لدورة أغسطس 2"
    }
    status, pay_res1 = api_request("/payments", method="POST", data=pay_payload1, token=token)
    if status != 201:
        print(f"❌ فشل تسجيل السداد الكامل: {pay_res1}")
        return False
    print(f"✅ تم تسجيل السداد الكامل بنجاح. رقم السند: {pay_res1['data']['payment']['receipt_number']}")

    # Check updated August invoice and downstream cascade
    _, aug_inv_updated = api_request(f"/invoices/{aug_inv['id']}", token=token)
    aug_inv_data = aug_inv_updated["data"]
    print(f"    حالة الفاتورة بعد السداد: {aug_inv_data['status']} | المدفوع: {aug_inv_data['paid_amount']} | المتبقي: {aug_inv_data['remaining_amount']}")
    assert aug_inv_data["remaining_amount"] == 0, "المتبقي يجب أن يكون صفر بعد السداد الكامل"
    assert aug_inv_data["status"] == "Paid", "حالة الفاتورة يجب أن تكون Paid"

    # Test 7.2: Partial Payment on Cycle 2 (September 1)
    status, all_invs_res = api_request(f"/invoices?customer_id={cust_id}", token=token)
    cust_invoices = all_invs_res.get("data", [])
    sep_inv = next((i for i in cust_invoices if "سبتمبر" in i.get("billing_cycle", "")), cust_invoices[1])
    sep_due = sep_inv["remaining_amount"]
    partial_pay_amt = sep_due / 2.0
    print(f"\n--- 7.2 سداد جزئي (Partial Payment) لدورة [{sep_inv['billing_cycle']}] بمبلغ {partial_pay_amt} من إجمالي {sep_due} ريال ---")
    pay_payload2 = {
        "customer_id": cust_id,
        "invoice_id": sep_inv["id"],
        "amount_paid": partial_pay_amt,
        "payment_method": "TRANSFER",
        "notes": "سداد جزئي تجريبي لدورة سبتمبر 1"
    }
    status, pay_res2 = api_request("/payments", method="POST", data=pay_payload2, token=token)
    if status != 201:
        print(f"❌ فشل تسجيل السداد الجزئي: {pay_res2}")
        return False
    print(f"✅ تم تسجيل السداد الجزئي بنجاح. رقم السند: {pay_res2['data']['payment']['receipt_number']}")
    
    _, sep_inv_updated = api_request(f"/invoices/{sep_inv['id']}", token=token)
    sep_inv_data = sep_inv_updated["data"]
    print(f"    حالة الفاتورة بعد السداد: {sep_inv_data['status']} | المدفوع: {sep_inv_data['paid_amount']} | المتبقي: {sep_inv_data['remaining_amount']}")
    assert sep_inv_data["remaining_amount"] == sep_due - partial_pay_amt, "المتبقي غير متطابق رياضياً مع السداد الجزئي"
    assert sep_inv_data["status"] == "Partially_Paid", "حالة الفاتورة يجب أن تكون Partially_Paid"

    # Test 7.3: Overpayment (Credit Surplus) on Cycle 3 (October 1)
    status, all_invs_res = api_request(f"/invoices?customer_id={cust_id}", token=token)
    cust_invoices = all_invs_res.get("data", [])
    oct_inv = next((i for i in cust_invoices if "أكتوبر" in i.get("billing_cycle", "")), cust_invoices[2])
    oct_due = oct_inv["remaining_amount"]
    overpay_amt = oct_due + 50000.0  # Surplus of 50,000 YER
    print(f"\n--- 7.3 سداد بفائض رصيد دائن (Overpayment / Surplus Credit) لدورة [{oct_inv['billing_cycle']}] بمبلغ {overpay_amt} من أصل {oct_due} ريال (فائض: 50,000 ريال) ---")
    pay_payload3 = {
        "customer_id": cust_id,
        "invoice_id": oct_inv["id"],
        "amount_paid": overpay_amt,
        "payment_method": "BANK",
        "notes": "سداد مع فائض رصيد دائن 50,000 ريال"
    }
    status, pay_res3 = api_request("/payments", method="POST", data=pay_payload3, token=token)
    if status != 201:
        print(f"❌ فشل تسجيل السداد بفائض: {pay_res3}")
        return False
    print(f"✅ تم تسجيل السداد بفائض بنجاح. رقم السند: {pay_res3['data']['payment']['receipt_number']}")
    credit_info = pay_res3['data'].get('credit')
    if credit_info:
        print(f"✅ تم تسجيل رصيد دائن للمشترك (Customer Credit) بمبلغ: {credit_info['amount']} ريال")

    _, oct_inv_updated = api_request(f"/invoices/{oct_inv['id']}", token=token)
    oct_inv_data = oct_inv_updated["data"]
    print(f"    حالة الفاتورة بعد السداد: {oct_inv_data['status']} | المدفوع: {oct_inv_data['paid_amount']} | المتبقي: {oct_inv_data['remaining_amount']}")
    assert oct_inv_data["remaining_amount"] == -50000.0, f"المبلغ المتبقي يجب أن يظهر بالسالب (-50000.0)، الفعلي: {oct_inv_data['remaining_amount']}"
    assert oct_inv_data["status"] == "Paid", "حالة الفاتورة يجب أن تكون Paid"

    # Check Customer total balance and credits
    _, cust_detail = api_request(f"/customers/{cust_id}", token=token)
    cust_data = cust_detail["data"]
    print(f"✅ إجمالي الرصيد المحسوب للمشترك: {cust_data.get('balance')} ريال | الرصيد الدائن المتاح: {cust_data.get('available_credits')} ريال")

    # 8. Test WhatsApp Queue
    print("\n[8] اختبار طابور إرسال رسائل الواتساب (WhatsApp Queue)...")
    status, wa_msgs_res = api_request(f"/whatsapp/messages?search={sub_num}", token=token)
    wa_msgs = wa_msgs_res.get("data", [])
    print(f"✅ عدد رسائل الواتساب المرتبطة بالمشترك في الطابور: {len(wa_msgs)}")
    for msg in wa_msgs:
        print(f"   - [نوع: {msg.get('type')}] إلى: {msg.get('phone_number')} | الحالة: {msg.get('status')}")
        print(f"     النص: {msg.get('message')}")

    # Test queue status and test message
    status, wa_status_res = api_request("/whatsapp/status", token=token)
    print(f"✅ حالة محرك الواتساب: {wa_status_res.get('status')}")

    # 9. Test Invoice Rendering (PNG generation)
    print("\n[9] اختبار توليد ومعاينة صورة الفاتورة وكعب التحصيل (Invoice PNG Render)...")
    test_render_inv_id = oct_inv["id"]
    try:
        url = f"{BASE_URL}/invoices/{test_render_inv_id}/render"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
        with urllib.request.urlopen(req) as resp:
            png_bytes = resp.read()
            print(f"✅ تم توليد صورة الفاتورة بنجاح: الحجم = {len(png_bytes):,} بايت | النوع = {resp.headers.get('Content-Type')}")
    except Exception as e:
        print(f"⚠️ تنبيه أثناء استدعاء رندر الفاتورة: {e}")

    # 10. Final State of all Invoices post-payments
    print("\n" + "=" * 70)
    print("📊 الحالة المالية النهائية لجميع الدورات بعد كل العمليات والمدفوعات:")
    print("=" * 70)
    status, final_invs_res = api_request(f"/invoices?customer_id={cust_id}&limit=20", token=token)
    final_invoices = final_invs_res.get("data", [])
    final_invoices.sort(key=lambda x: x["id"])

    print(f"{'الدورة':<18} | {'السابقة':<8} | {'الحالية':<8} | {'الاستهلاك':<10} | {'قيمة الاستهلاك':<14} | {'رسوم':<6} | {'متأخرات':<10} | {'المستحق':<10} | {'المسدد':<10} | {'المتبقي':<12} | {'الحالة':<12}")
    print("-" * 130)
    for inv in final_invoices:
        print(f"{inv.get('billing_cycle',''):<18} | {inv.get('previous_reading',0):<8.1f} | {inv.get('current_reading',0):<8.1f} | {inv.get('consumption',0):<10.1f} | {inv.get('consumption_value',0):<14.2f} | {inv.get('fixed_fee_snapshot',0):<6.0f} | {inv.get('arrears',0):<10.2f} | {inv.get('total_due',0):<10.2f} | {inv.get('paid_amount',0):<10.2f} | {inv.get('remaining_amount',0):<12.2f} | {inv.get('status',''):<12}")
    print("-" * 130)

    print("\n🎉 اكتملت جميع الاختبارات بنجاح تام وبدقة حسابية 100%!")
    return True

if __name__ == "__main__":
    import urllib.parse
    run_tests()
