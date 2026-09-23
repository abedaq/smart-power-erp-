"""
Subscriber selection and baseline financial snapshotting module.
"""

import json
import logging
import random
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from simulation.client import SmartPowerClient
from simulation.config import SimulationConfig, config as default_config

logger = logging.getLogger("simulation.selector")


@dataclass
class SubscriberSnapshot:
    """Represents the baseline state of a subscriber before simulation operations."""

    customer_id: int
    subscriber_number: str
    full_name: str
    phone_number: str
    meter_number: str
    route_number: str
    initial_reading: float
    last_reading: float
    baseline_total_due: float
    baseline_balance: float
    latest_invoice_id: Optional[int] = None
    latest_cycle: Optional[str] = None
    extra_metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert snapshot to dictionary with strict English numbers."""
        return asdict(self)


class SubscriberSelector:
    """Selects and snapshots active subscribers deterministically."""

    def __init__(
        self,
        client: SmartPowerClient,
        config: Optional[SimulationConfig] = None,
    ):
        self.client = client
        self.config = config or default_config

    def select_active_subscribers(
        self,
        sample_size: Optional[int] = None,
        seed: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """
        Fetch all customers, filter for active non-deleted subscribers,
        and select a reproducible sample based on the given seed.
        """
        count = sample_size or self.config.subscriber_sample_size
        rnd_seed = seed if seed is not None else self.config.random_seed

        logger.info("Fetching customer directory from backend...")
        raw_customers = self.client.get_customers(page=1, limit=1000)

        # Filter active non-deleted customers
        active_customers = [
            c for c in raw_customers
            if (c.get("status") in ("Active", "active", None) and not c.get("is_deleted", False))
        ]

        if not active_customers:
            raise RuntimeError("No active subscribers found in the database!")

        total_active = len(active_customers)
        logger.info("Found %d active subscribers in system.", total_active)

        if total_active <= count:
            logger.warning(
                "Requested sample size %d >= total active %d. Using all available.",
                count, total_active
            )
            return sorted(active_customers, key=lambda c: int(c.get("id", 0)))

        # Deterministic sorting first to ensure identical input ordering
        active_customers.sort(key=lambda c: str(c.get("subscriber_number", "")).zfill(10))

        # Deterministic random shuffle with fixed seed
        rng = random.Random(rnd_seed)
        shuffled = list(active_customers)
        rng.shuffle(shuffled)

        selected = shuffled[:count]
        # Re-sort selected by ID for structured sequential processing
        selected.sort(key=lambda c: int(c.get("id", 0)))

        logger.info("Deterministically selected %d subscribers (seed=%d).", len(selected), rnd_seed)
        return selected

    def capture_baseline_snapshots(
        self,
        selected_customers: List[Dict[str, Any]],
        output_file: Optional[Path] = None,
    ) -> List[SubscriberSnapshot]:
        """
        Capture detailed financial snapshot for each selected subscriber
        including opening balance, last reading, and latest invoice.
        """
        logger.info("Capturing baseline financial snapshots for %d subscribers...", len(selected_customers))
        snapshots: List[SubscriberSnapshot] = []

        for cust in selected_customers:
            cid = int(cust["id"])
            sub_no = str(cust.get("subscriber_number", "")).strip()
            name = str(cust.get("full_name", "")).strip()
            phone = str(cust.get("phone_number", "")).strip()
            meter = str(cust.get("meter_number") or "").strip()
            route = str(cust.get("route_number") or "").strip()

            initial_r = float(cust.get("initial_reading") or 0.0)
            last_r = float(cust.get("last_reading") or initial_r)
            total_due = float(cust.get("total_due") or 0.0)
            balance = float(cust.get("balance") or total_due)

            # Query latest invoice and readings to get exact current state
            latest_inv_id = None
            latest_cycle = None
            try:
                invoices = self.client.get_invoices(customer_id=cid, limit=1)
                if invoices:
                    latest_inv = invoices[0]
                    latest_inv_id = int(latest_inv.get("id", 0)) or None
                    latest_cycle = latest_inv.get("billing_cycle")
            except Exception as e:
                logger.debug("Could not fetch latest invoice for customer %d: %s", cid, str(e))

            snapshot = SubscriberSnapshot(
                customer_id=cid,
                subscriber_number=sub_no,
                full_name=name,
                phone_number=phone,
                meter_number=meter,
                route_number=route,
                initial_reading=initial_r,
                last_reading=last_r,
                baseline_total_due=total_due,
                baseline_balance=balance,
                latest_invoice_id=latest_inv_id,
                latest_cycle=latest_cycle,
                extra_metadata={
                    "subscription_plan_id": cust.get("subscription_plan_id"),
                    "start_cycle": cust.get("start_cycle"),
                },
            )
            snapshots.append(snapshot)

        logger.info("Successfully captured baseline snapshots for %d subscribers.", len(snapshots))

        if output_file:
            output_file.parent.mkdir(parents=True, exist_ok=True)
            with open(output_file, "w", encoding="utf-8") as f:
                json.dump([s.to_dict() for s in snapshots], f, ensure_ascii=False, indent=2)
            logger.info("Baseline snapshots saved to %s", output_file)

        return snapshots
