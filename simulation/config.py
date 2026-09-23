"""
Configuration module for SmartPower ERP financial simulation suite.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class SimulationConfig:
    """Configuration settings for simulation, API connectivity, and artifact generation."""

    # Backend API settings
    api_base_url: str = field(
        default_factory=lambda: os.getenv("SMARTPOWER_API_URL", "http://localhost:3000/api").rstrip("/")
    )
    ui_base_url: str = field(
        default_factory=lambda: os.getenv("SMARTPOWER_UI_URL", "http://localhost:3000").rstrip("/")
    )

    # Database settings (PostgreSQL 18 live instance)
    database_url: str = field(
        default_factory=lambda: os.getenv(
            "DATABASE_URL",
            "postgres://postgres:postgres@localhost:5432/smartpower_db?sslmode=disable",
        )
    )

    # Admin authentication credentials
    admin_username: str = field(
        default_factory=lambda: os.getenv("SMARTPOWER_ADMIN_USER", "admin")
    )
    admin_password: str = field(
        default_factory=lambda: os.getenv("SMARTPOWER_ADMIN_PASS", "admin123")
    )
    admin_alt_password: str = field(
        default_factory=lambda: os.getenv("SMARTPOWER_ADMIN_ALT_PASS", "password123")
    )

    # Simulation scale constants
    subscriber_sample_size: int = field(
        default_factory=lambda: int(os.getenv("SIMULATION_SAMPLE_SIZE", "100"))
    )
    billing_cycles_count: int = field(
        default_factory=lambda: int(os.getenv("SIMULATION_CYCLES_COUNT", "12"))
    )
    random_seed: int = field(
        default_factory=lambda: int(os.getenv("SIMULATION_RANDOM_SEED", "42"))
    )

    # Financial and pricing defaults (YER)
    default_kwh_price: float = field(
        default_factory=lambda: float(os.getenv("DEFAULT_KWH_PRICE", "1400.0"))
    )
    default_fixed_fee: float = field(
        default_factory=lambda: float(os.getenv("DEFAULT_FIXED_FEE", "1000.0"))
    )

    # Realistic consumption parameters (kWh)
    min_consumption_kwh: float = 50.0
    max_consumption_kwh: float = 650.0
    zero_consumption_ratio: float = 0.05  # 5% zero consumption cases

    # Payment profile ratios
    full_payment_ratio: float = 0.60       # 60% full payment
    partial_payment_ratio: float = 0.20    # 20% partial payment (debt aging)
    overpayment_ratio: float = 0.10        # 10% excess payment (customer credit)
    non_payment_ratio: float = 0.10        # 10% zero payment (carried forward arrears)

    # Reversal / Rollback testing parameters
    reversal_sample_count: int = 10
    tariff_modification_test_count: int = 5

    # HTTP client parameters
    http_timeout: float = 20.0
    http_max_retries: int = 3
    http_retry_backoff: float = 0.5

    # Browser & Playwright parameters
    playwright_channel: str = field(
        default_factory=lambda: os.getenv("PLAYWRIGHT_CHANNEL", "msedge")
    )
    playwright_headless: bool = True
    receipt_render_count: int = 10

    # Paths and artifacts
    workspace_root: Path = field(
        default_factory=lambda: Path(os.getenv("WORKSPACE_ROOT", r"c:\مللفات الهارد القديم D\elctercity"))
    )
    artifacts_dir: Path = field(
        default_factory=lambda: Path(os.getenv("ARTIFACTS_DIR", "artifacts"))
    )

    @property
    def receipts_dir(self) -> Path:
        """Directory for rendered receipt image artifacts."""
        path = self.artifacts_dir / "receipts"
        path.mkdir(parents=True, exist_ok=True)
        return path

    @property
    def reports_dir(self) -> Path:
        """Directory for exported audit spreadsheet artifacts."""
        path = self.artifacts_dir / "reports"
        path.mkdir(parents=True, exist_ok=True)
        return path

    @property
    def invoices_dir(self) -> Path:
        """Directory for exported invoice artifacts."""
        path = self.artifacts_dir / "invoices"
        path.mkdir(parents=True, exist_ok=True)
        return path


# Default singleton instance
config = SimulationConfig()
