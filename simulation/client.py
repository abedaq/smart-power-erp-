"""
Thread-safe REST API client for SmartPower ERP Go backend.
"""

import logging
import time
import uuid
from typing import Any, Dict, List, Optional
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from simulation.config import SimulationConfig, config as default_config

logger = logging.getLogger("simulation.client")


class SmartPowerClient:
    """Client for interacting with the SmartPower ERP Go Fiber REST API."""

    def __init__(self, config: Optional[SimulationConfig] = None):
        self.config = config or default_config
        self.base_url = self.config.api_base_url
        self.session = requests.Session()
        self.token: Optional[str] = None

        # Setup retry strategy for transient network errors
        retries = Retry(
            total=self.config.http_max_retries,
            backoff_factor=self.config.http_retry_backoff,
            status_forcelist=[502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS"],
            raise_on_status=False,
        )
        adapter = HTTPAdapter(max_retries=retries, pool_connections=20, pool_maxsize=50)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

    def _request(
        self,
        method: str,
        endpoint: str,
        params: Optional[Dict[str, Any]] = None,
        json_data: Optional[Dict[str, Any]] = None,
        data: Optional[Any] = None,
        headers: Optional[Dict[str, str]] = None,
        timeout: Optional[float] = None,
        retry_auth: bool = True,
    ) -> requests.Response:
        """Execute HTTP request with automatic token injection and 401 recovery."""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        req_headers = {"Accept": "application/json"}
        if headers:
            req_headers.update(headers)

        if self.token:
            req_headers["Authorization"] = f"Bearer {self.token}"

        timeout_sec = timeout or self.config.http_timeout

        try:
            response = self.session.request(
                method=method,
                url=url,
                params=params,
                json=json_data,
                data=data,
                headers=req_headers,
                timeout=timeout_sec,
            )

            # Auto-relogin on 401 Unauthorized if token expired
            if response.status_code == 401 and retry_auth:
                logger.info("Token expired or unauthorized (401). Refreshing authentication...")
                self.login()
                req_headers["Authorization"] = f"Bearer {self.token}"
                response = self.session.request(
                    method=method,
                    url=url,
                    params=params,
                    json=json_data,
                    data=data,
                    headers=req_headers,
                    timeout=timeout_sec,
                )

            return response
        except requests.RequestException as e:
            logger.error("HTTP request error to %s: %s", url, str(e))
            raise

    # -------------------------------------------------------------------------
    # Authentication
    # -------------------------------------------------------------------------
    def login(
        self,
        username: Optional[str] = None,
        password: Optional[str] = None,
    ) -> str:
        """Authenticate as administrator and obtain JWT token."""
        user = username or self.config.admin_username
        passwords_to_try = [
            password or self.config.admin_password,
            self.config.admin_alt_password,
        ]

        last_resp = None
        for pwd in passwords_to_try:
            if not pwd:
                continue
            resp = self._request(
                method="POST",
                endpoint="/auth/login",
                json_data={"username": user, "password": pwd},
                retry_auth=False,
            )
            last_resp = resp
            if resp.status_code == 200:
                body = resp.json()
                token = body.get("token") or (body.get("data") or {}).get("token")
                if token:
                    self.token = token
                    logger.debug("Successfully authenticated as %s", user)
                    return token

        err_msg = f"Failed to authenticate as {user}: Status {last_resp.status_code if last_resp else 'N/A'}"
        logger.error(err_msg)
        raise ConnectionRefusedError(err_msg)

    def ensure_auth(self) -> str:
        """Ensure client has a valid JWT token, acquiring one if absent."""
        if not self.token:
            return self.login()
        return self.token

    def health_check(self) -> bool:
        """Check if backend API is reachable and healthy."""
        try:
            resp = self._request("GET", "/settings", timeout=5.0)
            return resp.status_code in (200, 201)
        except Exception:
            return False

    # -------------------------------------------------------------------------
    # Customer Management
    # -------------------------------------------------------------------------
    def get_customers(
        self,
        page: int = 1,
        limit: int = 500,
        status: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Retrieve list of customers with pagination and optional status filter."""
        self.ensure_auth()
        params: Dict[str, Any] = {"page": page, "limit": limit}
        if status:
            params["status"] = status

        resp = self._request("GET", "/customers", params=params)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch customers: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if isinstance(res_json, list):
            return res_json
        if isinstance(res_json, dict):
            if "data" in res_json and isinstance(res_json["data"], list):
                return res_json["data"]
            if "customers" in res_json and isinstance(res_json["customers"], list):
                return res_json["customers"]
        return []

    def get_customer(self, customer_id: int) -> Dict[str, Any]:
        """Fetch customer details and current calculated balance by ID."""
        self.ensure_auth()
        resp = self._request("GET", f"/customers/{customer_id}")
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch customer {customer_id}: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if "data" in res_json and isinstance(res_json["data"], dict):
            return res_json["data"]
        return res_json

    # -------------------------------------------------------------------------
    # Meter Readings
    # -------------------------------------------------------------------------
    def get_readings(
        self,
        customer_id: Optional[int] = None,
        limit: int = 20,
        cycle: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Fetch historical meter readings with optional customer and cycle filter."""
        self.ensure_auth()
        params: Dict[str, Any] = {"limit": limit}
        if customer_id is not None:
            params["customer_id"] = customer_id
        if cycle:
            params["cycle"] = cycle

        resp = self._request("GET", "/readings", params=params)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch readings: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if isinstance(res_json, list):
            return res_json
        if isinstance(res_json, dict):
            if "data" in res_json and isinstance(res_json["data"], list):
                return res_json["data"]
            if "readings" in res_json and isinstance(res_json["readings"], list):
                return res_json["readings"]
        return []

    def submit_reading(
        self,
        customer_id: int,
        reading_value: float,
        billing_cycle: str,
        collector_name: str = "محاكي النظام المالي",
        approval_status: str = "APPROVED",
        client_mutation_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Submit a meter reading and automatically generate/update the associated invoice.
        Enforces monotonicity and chronological locking on the backend.
        """
        self.ensure_auth()
        payload = {
            "customer_id": customer_id,
            "reading_value": float(reading_value),
            "billing_cycle": billing_cycle,
            "collector_name": collector_name,
            "approval_status": approval_status,
            "client_mutation_id": client_mutation_id or str(uuid.uuid4()),
        }

        resp = self._request("POST", "/readings", json_data=payload)
        if resp.status_code not in (200, 201):
            raise RuntimeError(
                f"Failed to submit reading for customer {customer_id} (value={reading_value}): "
                f"{resp.status_code} {resp.text}"
            )

        res_json = resp.json()
        return res_json.get("data") if "data" in res_json else res_json

    # -------------------------------------------------------------------------
    # Invoices
    # -------------------------------------------------------------------------
    def get_invoices(
        self,
        customer_id: Optional[int] = None,
        cycle: Optional[str] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Fetch invoices filtered by customer and/or billing cycle."""
        self.ensure_auth()
        params: Dict[str, Any] = {"limit": limit}
        if customer_id is not None:
            params["customer_id"] = customer_id
        if cycle:
            params["cycle"] = cycle

        resp = self._request("GET", "/invoices", params=params)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch invoices: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if isinstance(res_json, list):
            return res_json
        if isinstance(res_json, dict):
            if "data" in res_json and isinstance(res_json["data"], list):
                return res_json["data"]
            if "invoices" in res_json and isinstance(res_json["invoices"], list):
                return res_json["invoices"]
        return []

    def get_invoice(self, invoice_id: int) -> Dict[str, Any]:
        """Fetch a specific invoice by ID."""
        self.ensure_auth()
        resp = self._request("GET", f"/invoices/{invoice_id}")
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch invoice {invoice_id}: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if "data" in res_json and isinstance(res_json["data"], dict):
            return res_json["data"]
        return res_json

    def render_invoice_png(self, invoice_id: int) -> bytes:
        """Call Go backend chromedp renderer to generate official A5 invoice PNG bytes."""
        self.ensure_auth()
        resp = self._request("GET", f"/invoices/{invoice_id}/render", timeout=30.0)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to render invoice PNG for {invoice_id}: {resp.status_code} {resp.text}")
        return resp.content

    def update_invoice_cell(
        self,
        invoice_id: int,
        field: str,
        value: Any,
    ) -> Dict[str, Any]:
        """Update a specific invoice cell (e.g. kwh_price, unit_price, service_fee)."""
        self.ensure_auth()
        payload = {field: value}
        resp = self._request("PATCH", f"/invoices/{invoice_id}/cell-update", json_data=payload)
        if resp.status_code not in (200, 201):
            # Fallback to PUT if PATCH isn't accepted
            resp = self._request("PUT", f"/invoices/{invoice_id}/cell-update", json_data=payload)
        if resp.status_code not in (200, 201):
            raise RuntimeError(
                f"Failed to update cell {field}={value} on invoice {invoice_id}: "
                f"{resp.status_code} {resp.text}"
            )
        return resp.json()

    # -------------------------------------------------------------------------
    # Payments & Collections
    # -------------------------------------------------------------------------
    def create_payment(
        self,
        customer_id: int,
        amount_paid: float,
        invoice_id: Optional[int] = None,
        payment_method: str = "CASH",
        notes: Optional[str] = "سداد محاكاة مالية",
        client_mutation_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Record a payment voucher for a customer.
        Executes atomic FIFO waterfall allocation and returns receipt data.
        """
        self.ensure_auth()
        payload: Dict[str, Any] = {
            "customer_id": customer_id,
            "amount_paid": float(amount_paid),
            "payment_method": payment_method,
            "notes": notes,
            "client_mutation_id": client_mutation_id or str(uuid.uuid4()),
        }
        if invoice_id is not None:
            payload["invoice_id"] = invoice_id

        resp = self._request("POST", "/payments", json_data=payload)
        if resp.status_code not in (200, 201):
            raise RuntimeError(
                f"Failed to create payment of {amount_paid} for customer {customer_id}: "
                f"{resp.status_code} {resp.text}"
            )

        res_json = resp.json()
        if "data" in res_json:
            return res_json["data"]
        if "payment" in res_json:
            return res_json
        return res_json

    def get_payments(
        self,
        customer_id: Optional[int] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Retrieve payment receipts with allocations."""
        self.ensure_auth()
        params: Dict[str, Any] = {"limit": limit}
        if customer_id is not None:
            params["customer_id"] = customer_id

        resp = self._request("GET", "/payments", params=params)
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch payments: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if isinstance(res_json, list):
            return res_json
        if isinstance(res_json, dict):
            if "data" in res_json and isinstance(res_json["data"], list):
                return res_json["data"]
            if "payments" in res_json and isinstance(res_json["payments"], list):
                return res_json["payments"]
        return []

    def reverse_payment(
        self,
        payment_id: int,
        reason: str = "محاكاة التدقيق المالي وعكس سند القبض",
    ) -> Dict[str, Any]:
        """
        Execute payment reversal / rollback via POST /api/payments/:id/reverse.
        Atomically restores invoice remaining balances and cascades arrears downstream.
        """
        self.ensure_auth()
        payload = {"reason": reason}
        resp = self._request("POST", f"/payments/{payment_id}/reverse", json_data=payload)
        if resp.status_code not in (200, 201):
            raise RuntimeError(
                f"Failed to reverse payment {payment_id}: {resp.status_code} {resp.text}"
            )
        return resp.json()

    # -------------------------------------------------------------------------
    # Settings & Tariff
    # -------------------------------------------------------------------------
    def get_settings(self) -> Dict[str, Any]:
        """Fetch system settings including default kWh price and station metadata."""
        self.ensure_auth()
        resp = self._request("GET", "/settings")
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch settings: {resp.status_code} {resp.text}")

        res_json = resp.json()
        if "data" in res_json and isinstance(res_json["data"], dict):
            return res_json["data"]
        return res_json

    def update_settings(self, **kwargs) -> Dict[str, Any]:
        """Update system settings (requires ADMIN role)."""
        self.ensure_auth()
        resp = self._request("PUT", "/settings", json_data=kwargs)
        if resp.status_code not in (200, 201):
            raise RuntimeError(f"Failed to update settings: {resp.status_code} {resp.text}")
        return resp.json()

    def export_cycle_excel(self, cycle_name: str) -> bytes:
        """Download official cycle Excel spreadsheet from backend."""
        self.ensure_auth()
        resp = self._request("GET", "/export/cycle", params={"cycle": cycle_name})
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to export cycle {cycle_name}: {resp.status_code} {resp.text}")
        return resp.content
