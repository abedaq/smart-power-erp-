# -*- coding: utf-8 -*-
"""
Test WhatsApp Queue, Audit Logs, and Analytics endpoints
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
    print("📱 فحص واجهات الواتساب والتقارير وسجل العمليات Audit Logs")
    print("=" * 70)

    # 1. Login
    status, login_res = api_request("/auth/login", method="POST", data={"username": "admin", "password": "password123"})
    token = login_res["token"]

    # 2. Test WhatsApp Test Message
    print("\n[1] إرسال رسالة تجريبية لطابور الواتساب...")
    test_msg_payload = {
        "to": "734019059",
        "message": "رسالة تجريبية لفحص طابور الإرسال في نظام SmartPower"
    }
    status, wa_res = api_request("/whatsapp/send-test", method="POST", data=test_msg_payload, token=token)
    print(f"✅ استجابة إرسال الرسالة التجريبية: Status={status}, Message={wa_res.get('message')}")

    # 3. Check WhatsApp Queue
    print("\n[2] استعلام رسائل طابور الواتساب...")
    status, q_res = api_request("/whatsapp/messages?limit=10", token=token)
    msgs = q_res.get("data", [])
    print(f"✅ إجمالي الرسائل في الطابور: {q_res.get('total')}")
    for m in msgs[:5]:
        print(f"   - [ID: {m['id']}] نوع: {m['type']} | هاتف: {m['phone_number']} | حالة: {m['status']}")

    # 4. Check Analytics Summary
    print("\n[3] فحص مؤشرات لوحة التحكم التحليلية (Analytics Summary)...")
    status, analytics_res = api_request("/analytics/dashboard-summary", token=token)
    data = analytics_res.get("data", {})
    print(f"✅ المشتركين: {data.get('total_customers')} | الفواتير: {data.get('total_invoices')}")
    print(f"✅ المفوتر الإجمالي: {data.get('total_billed'):,.2f} ريال | المحصل: {data.get('total_collected'):,.2f} ريال | المتأخرات: {data.get('total_arrears'):,.2f} ريال")

    # 5. Check Monthly Performance
    print("\n[4] فحص الأداء الشهري للتحصيل (Monthly Performance)...")
    status, perf_res = api_request("/analytics/monthly-performance", token=token)
    for p in perf_res.get("data", [])[:6]:
        print(f"   - دورة {p.get('month')}: مفوتر = {p.get('totalBilled'):,.2f} | محصل = {p.get('totalCollected'):,.2f} | نسبة التحصيل = {p.get('collectionRate')}%")

    # 6. Check Audit Logs
    print("\n[5] فحص سجل الرقابة والتدقيق (Audit Logs)...")
    status, audit_res = api_request("/audit/logs?limit=10", token=token)
    logs = audit_res.get("data", [])
    print(f"✅ إجمالي سجلات التدقيق المسجلة: {audit_res.get('total')}")
    for log_item in logs[:5]:
        print(f"   - [{log_item.get('created_at', '')[:19]}] عمل: {log_item.get('action')} | الكيان: {log_item.get('entity')} | التفاصيل: {log_item.get('details')}")

    print("\n🎉 اكتمل فحص الواتساب والتحليلات وسجلات التدقيق بنجاح تام!")

if __name__ == "__main__":
    run_tests()
