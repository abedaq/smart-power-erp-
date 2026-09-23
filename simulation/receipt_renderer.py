"""
Playwright-based dual-stub receipt generator for SmartPower ERP.
Produces authentic A5 dual-stub receipts (PNG and PDF) matching the official station layout.
"""

import base64
import html
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional
from playwright.sync_api import sync_playwright

from simulation.config import SimulationConfig, config as default_config

logger = logging.getLogger("simulation.receipt_renderer")


@dataclass
class ReceiptRenderData:
    """Data required to render an official dual-stub receipt."""

    receipt_number: str
    customer_name: str
    subscriber_number: str
    phone_number: str = ""
    address: str = "صنعاء"
    meter_number: str = "-"
    route_number: str = "A1"
    billing_cycle: str = "2027-03-1"
    payment_date: str = "23/09/2026"
    previous_reading: float = 0.0
    current_reading: float = 0.0
    consumption: float = 0.0
    kwh_price: float = 1400.0
    consumption_value: float = 0.0
    fixed_fee: float = 1000.0
    arrears: float = 0.0
    total_due: float = 0.0
    paid_amount: float = 0.0
    remaining_balance: float = 0.0
    station_name: str = "محطة الضياء لتوليد الطاقة الكهربائية"
    station_phone: str = "777000000 - 733000000"
    bank_accounts: str = "كريمي: 12345678"
    is_reversed: bool = False


class ReceiptRenderer:
    """Renders authentic A5 dual-stub payment receipts via Playwright."""

    def __init__(self, config: Optional[SimulationConfig] = None):
        self.config = config or default_config
        self._logo_base64: Optional[str] = self._load_station_logo()

    def _load_station_logo(self) -> Optional[str]:
        """Load station logo PNG and convert to base64 data URI."""
        possible_paths = [
            self.config.workspace_root / "frontend" / "public" / "station_logo.png",
            self.config.workspace_root / "dist_portable" / "frontend" / "station_logo.png",
            self.config.workspace_root / "server" / "dist" / "station_logo.png",
        ]
        for p in possible_paths:
            if p.exists() and p.is_file():
                try:
                    with open(p, "rb") as f:
                        data = f.read()
                        if data:
                            return "data:image/png;base64," + base64.b64encode(data).decode("ascii")
                except Exception as e:
                    logger.debug("Failed to read logo from %s: %s", p, str(e))
        return None

    @staticmethod
    def _format_money(val: float) -> str:
        """Format number strictly with English digits and 2 decimals or integer."""
        if abs(val - round(val)) < 0.001:
            return f"{int(round(val)):,}"
        return f"{val:,.2f}"

    def build_receipt_html(self, data: ReceiptRenderData) -> str:
        """Construct official dual-stub A5 HTML matching Go backend implementation."""
        logo_html = ""
        if self._logo_base64:
            logo_html = f'<img src="{self._logo_base64}" style="width: 48px; height: 48px; object-fit: contain;" alt="logo" />'

        prev_str = self._format_money(data.previous_reading)
        curr_str = self._format_money(data.current_reading)
        cons_str = self._format_money(data.consumption)
        fee_str = self._format_money(data.fixed_fee)
        val_str = self._format_money(data.consumption_value)
        arr_str = self._format_money(data.arrears)
        due_str = self._format_money(data.total_due)
        paid_str = self._format_money(data.paid_amount)

        rem = data.remaining_balance
        if rem > 0:
            rem_text = f"+{self._format_money(rem)} ر.ي (متبقي عليك)"
            rem_color = "#b91c1c"
            coupon_rem_label = "المتبقي بعد السداد:"
            coupon_rem_val = f"+{self._format_money(rem)} ر.ي"
        elif rem < 0:
            rem_text = f"-{self._format_money(-rem)} ر.ي (دائن لك)"
            rem_color = "#047857"
            coupon_rem_label = "الرصيد الدائن:"
            coupon_rem_val = f"-{self._format_money(-rem)} ر.ي"
        else:
            rem_text = "0 ر.ي (خالص)"
            rem_color = "#047857"
            coupon_rem_label = "المتبقي بعد السداد:"
            coupon_rem_val = "0 ر.ي (خالص)"

        c_name = data.billing_cycle.strip()
        cycle_title_coupon = f'<span style="color: #dc2626;">فاتورة استهلاك كهرباء دورة </span><span style="color: #1e3a8a;">{html.escape(c_name)}</span><span style="color: #dc2626;"> - سند سداد رسمي</span>'
        cycle_title_main = cycle_title_coupon

        watermark_html = ""
        if data.is_reversed:
            watermark_html = (
                '<div style="position: absolute; top: 35%; left: 25%; transform: rotate(-25deg); '
                'font-size: 55px; font-weight: 900; color: rgba(220, 38, 38, 0.35); '
                'border: 6px dashed #dc2626; padding: 10px 40px; pointer-events: none; z-index: 100;">'
                'ملغـــــى (REVERSED)</div>'
            )

        return f"""<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800;900&display=swap');
  * {{ box-sizing: border-box; font-family: 'Cairo', Tahoma, sans-serif; margin: 0; padding: 0; font-feature-settings: "lnum" 1, "zero" 0; font-variant-numeric: lining-nums tabular-nums; }}
  body {{ background: #fff; padding: 6px; display: flex; justify-content: center; }}
  .receipt-card {{ width: 960px; background: #fff; border: 2px solid #000; padding: 8px; position: relative; }}
  .grid-container {{ display: grid; grid-template-columns: 5fr 7fr; gap: 0; align-items: stretch; }}
  .coupon-stub {{ padding-left: 12px; padding-right: 4px; display: flex; flex-direction: column; justify-content: space-between; }}
  .main-stub {{ border-right: 2px solid #000; padding-right: 12px; padding-left: 4px; display: flex; flex-direction: column; justify-content: space-between; }}
  .header-box {{ display: flex; align-items: flex-start; justify-content: space-between; border-bottom: 2px solid #000; padding-bottom: 4px; margin-bottom: 6px; }}
  .station-title {{ font-size: 13px; font-weight: 900; color: #000; text-align: center; }}
  .station-phone {{ font-size: 12px; font-weight: 800; color: #1d4ed8; font-family: 'Cairo', Tahoma, sans-serif; direction: ltr; margin: 2px 0; text-align: center; }}
  .bank-acc {{ font-size: 10.5px; font-weight: 900; color: #000; text-align: center; }}
  .cust-info {{ font-size: 10.5px; font-weight: 900; line-height: 1.5; margin-bottom: 4px; color: #000; }}
  .red-title {{ text-align: center; font-weight: 900; color: #dc2626; font-size: 11px; margin: 5px 0; }}
  .red-title-main {{ text-align: center; font-weight: 900; color: #dc2626; font-size: 12px; margin: 5px 0; }}
  table.custom-table {{ width: 100%; border-collapse: collapse; text-align: center; border: 2px solid #000; margin-bottom: 6px; }}
  table.custom-table th, table.custom-table td {{ border: 1px solid #000; }}
  table.custom-table th {{ font-size: 9.5px; font-weight: 900; background: #fff; padding: 3px 2px; }}
  table.custom-table td {{ font-size: 10.5px; font-weight: 900; font-family: 'Cairo', Tahoma, sans-serif; padding: 4px 2px; color: #000; }}
  .summary-coupon {{ border: 1px solid #000; background: #f8fafc; padding: 4px; margin-bottom: 6px; font-size: 9.5px; font-weight: 900; }}
  .summary-coupon-row {{ display: flex; justify-content: space-between; padding: 2px 0; }}
  .summary-card {{ border: 2px solid #000; background: #f8fafc; padding: 5px; margin-bottom: 6px; font-size: 10px; font-weight: 900; }}
  .summary-grid {{ display: grid; grid-template-columns: 1fr 1fr 1fr; text-align: center; }}
  .policy-box {{ color: #dc2626; font-size: 9px; font-weight: 900; line-height: 1.35; margin: 5px 0; }}
  .sig-row {{ display: flex; justify-content: space-between; font-size: 10.5px; font-weight: 900; padding: 0 12px; margin-top: 10px; }}
  .date-footer {{ font-size: 10px; font-weight: 900; font-family: 'Cairo', Tahoma, sans-serif; text-align: left; border-top: 1px solid #000; padding-top: 4px; margin-top: 6px; color: #000; }}
</style>
</head>
<body>
<div id="receipt-card" class="receipt-card">
  {watermark_html}
  <div class="grid-container">
    
    <!-- Part 1 (RIGHT SIDE): Collector Coupon Stub -->
    <div class="coupon-stub">
      <div>
        <div class="header-box">
          <div style="flex: 1; text-align: center;">
            <div class="station-title">{html.escape(data.station_name)}</div>
            <div class="station-phone">{html.escape(data.station_phone)}</div>
          </div>
          <div style="padding-top: 2px;">
            {logo_html}
          </div>
        </div>

        <div class="cust-info">
          <div><span>اسم المشترك : </span><b>{html.escape(data.customer_name)}</b></div>
          <div><span>العنوان : </span><span>{html.escape(data.address)}</span></div>
          <div><span>رقم المشترك : </span><span>{html.escape(data.subscriber_number)}</span></div>
          <div><span>رقم العداد : </span><span>{html.escape(data.meter_number)}</span></div>
        </div>

        <div class="red-title">{cycle_title_coupon}</div>

        <table class="custom-table">
          <thead>
            <tr>
              <th colspan="2">قــــــراءة العداد</th>
              <th rowspan="2">الفارق</th>
              <th rowspan="2">متأخرات</th>
              <th rowspan="2">الاجمالي</th>
            </tr>
            <tr>
              <th>ق.السابقة</th>
              <th>ق.الحالية</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>{prev_str}</td>
              <td>{curr_str}</td>
              <td>{cons_str}</td>
              <td>{arr_str}</td>
              <td>{due_str}</td>
            </tr>
          </tbody>
        </table>

        <div class="summary-coupon">
          <div class="summary-coupon-row">
            <span>المبلغ المسدد:</span>
            <span style="color: #065f46;">{paid_str} ر.ي</span>
          </div>
          <div class="summary-coupon-row" style="border-top: 1px solid rgba(0,0,0,0.3); padding-top: 2px;">
            <span>{coupon_rem_label}</span>
            <span style="color: {rem_color};">{coupon_rem_val}</span>
          </div>
        </div>
      </div>

      <div class="sig-row">
        <div style="text-align: center;">
          <div>المحصل</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">....................</div>
        </div>
        <div style="text-align: center;">
          <div>الحسابات</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">....................</div>
        </div>
      </div>
    </div>

    <!-- Part 2 (LEFT SIDE): Main Subscriber Stub -->
    <div class="main-stub">
      <div>
        <div class="header-box">
          <div style="flex: 1; text-align: center;">
            <div class="station-title" style="font-size: 15px;">{html.escape(data.station_name)}</div>
            <div class="station-phone" style="font-size: 13px;">{html.escape(data.station_phone)}</div>
            <div class="bank-acc">يمكنك الإيداع على الحساب {html.escape(data.bank_accounts)}</div>
          </div>
          <div style="padding-top: 2px;">
            {logo_html}
          </div>
        </div>

        <div class="cust-info">
          <div style="display: flex; justify-content: space-between;">
            <div><span>اسم المشترك : </span><b>{html.escape(data.customer_name)}</b></div>
            <div><span>رقم السند : </span><b>{html.escape(data.receipt_number)}</b></div>
          </div>
          <div><span>العنوان : </span><span>{html.escape(data.address)}</span></div>
          <div><span>رقم المشترك : </span><span>{html.escape(data.subscriber_number)}</span></div>
          <div style="display: flex; justify-content: space-between;">
            <div><span>رقم العداد : </span><span>{html.escape(data.meter_number)}</span></div>
            <div style="padding-left: 12px;"><span>رقم خط السير : </span><b>{html.escape(data.route_number)}</b></div>
          </div>
        </div>

        <div class="red-title-main">{cycle_title_main}</div>

        <table class="custom-table" style="font-size: 10px;">
          <thead>
            <tr>
              <th colspan="2">قــــــراءة العداد</th>
              <th rowspan="2">الفارق</th>
              <th rowspan="2">اشتراك</th>
              <th rowspan="2">القيمـة</th>
              <th rowspan="2">متأخرات</th>
              <th rowspan="2">الاجمالي</th>
            </tr>
            <tr>
              <th>ق. السابقة</th>
              <th>ق. الحالية</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>{prev_str}</td>
              <td>{curr_str}</td>
              <td>{cons_str}</td>
              <td>{fee_str}</td>
              <td>{val_str}</td>
              <td>{arr_str}</td>
              <td>{due_str}</td>
            </tr>
          </tbody>
        </table>

        <div class="summary-card">
          <div class="summary-grid">
            <div style="border-left: 1px solid #000; padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #475569;">إجمالي المستحق</span>
              <span style="font-size: 11px; font-weight: 900;">{due_str} ر.ي</span>
            </div>
            <div style="border-left: 1px solid #000; padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #065f46;">المبلغ المسدد</span>
              <span style="font-size: 11px; font-weight: 900; color: #047857;">{paid_str} ر.ي</span>
            </div>
            <div style="padding: 0 4px;">
              <span style="display: block; font-size: 8.5px; color: #475569;">الرصيد المتبقي</span>
              <span style="font-size: 11px; font-weight: 900; color: {rem_color};">{rem_text}</span>
            </div>
          </div>
        </div>

        <div class="policy-box">
          <div>o يتم سداد الفاتورة يوم استلامها او اليوم التالي فقط.</div>
          <div>o في حالة تأخر السداد سيتم فصل التيار دون إشعار مسبق ولن يعاد الا بغرامة.</div>
          <div>o في حال قيام المشترك بتوصيل التيار لشخص آخر سيتم تغريم المشترك مبلغ وقدره 200000 مائتان ألف ريال</div>
          <div>o يتحمل المشترك مديونية أي موقف إن لم يكن هناك سند رسمي مختوم بختم المحطة.</div>
          <div>o سعر الكيلوواط / ساعة {self._format_money(data.kwh_price)} ريال ويرتفع سعر الكيلو بنسبة وتناسب بارتفاع الديزل.</div>
        </div>
      </div>

      <div class="sig-row">
        <div style="text-align: center;">
          <div>المحصل</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">..........................</div>
        </div>
        <div style="text-align: center;">
          <div>الحسابات</div>
          <div style="color: #94a3b8; font-size: 12px; margin-top: 2px;">..........................</div>
        </div>
      </div>
    </div>

  </div>

  <div class="date-footer">
    التاريخ : {html.escape(data.payment_date)}
  </div>
</div>
</body>
</html>"""

    def render_receipt(
        self,
        data: ReceiptRenderData,
        output_path: Path,
        render_pdf: bool = False,
    ) -> Path:
        """Render a single receipt to PNG or PDF using Playwright headless browser."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        html_content = self.build_receipt_html(data)

        with sync_playwright() as p:
            try:
                browser = p.chromium.launch(
                    headless=self.config.playwright_headless,
                    channel=self.config.playwright_channel,
                )
            except Exception:
                # Fallback to default chromium bundle
                browser = p.chromium.launch(headless=self.config.playwright_headless)

            page = browser.new_page(viewport={"width": 1024, "height": 720})
            page.set_content(html_content)
            page.wait_for_selector("#receipt-card")

            if render_pdf:
                page.pdf(path=str(output_path), format="A5", landscape=True, print_background=True)
            else:
                card_elem = page.locator("#receipt-card")
                card_elem.screenshot(path=str(output_path))

            browser.close()

        logger.info("Rendered receipt artifact to: %s", output_path)
        return output_path

    def render_batch(
        self,
        receipts: List[ReceiptRenderData],
        output_dir: Optional[Path] = None,
    ) -> List[Path]:
        """Render a collection of receipts reusing a single browser session for speed."""
        target_dir = output_dir or self.config.receipts_dir
        target_dir.mkdir(parents=True, exist_ok=True)
        rendered_paths: List[Path] = []

        if not receipts:
            return rendered_paths

        logger.info("Batch rendering %d receipts to %s...", len(receipts), target_dir)
        with sync_playwright() as p:
            try:
                browser = p.chromium.launch(
                    headless=self.config.playwright_headless,
                    channel=self.config.playwright_channel,
                )
            except Exception:
                browser = p.chromium.launch(headless=self.config.playwright_headless)

            context = browser.new_context(viewport={"width": 1024, "height": 720})
            page = context.new_page()

            for r_data in receipts:
                status_suffix = "REVERSED" if r_data.is_reversed else "APPROVED"
                file_name = f"{r_data.receipt_number}_SUB-{r_data.subscriber_number}_{status_suffix}.png"
                out_path = target_dir / file_name

                html_content = self.build_receipt_html(r_data)
                page.set_content(html_content)
                page.wait_for_selector("#receipt-card")
                card = page.locator("#receipt-card")
                card.screenshot(path=str(out_path))

                rendered_paths.append(out_path)

            browser.close()

        logger.info("Batch rendering complete. Created %d PNG receipts.", len(rendered_paths))
        return rendered_paths
