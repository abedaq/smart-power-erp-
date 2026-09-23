"""
12-Month financial simulation engine for SmartPower ERP.
Generates realistic monotonic meter readings and diverse payment profiles.
"""

import logging
import random
from dataclasses import asdict, dataclass, field
from typing import Any, Callable, Dict, List, Optional

from simulation.client import SmartPowerClient
from simulation.config import SimulationConfig, config as default_config
from simulation.selector import SubscriberSnapshot

logger = logging.getLogger("simulation.engine")


@dataclass
class SimulationCycleRecord:
    """Record of a subscriber's financial transaction in a specific billing cycle."""

    cycle_name: str
    cycle_index: int
    customer_id: int
    subscriber_number: str
    full_name: str
    route_number: str
    previous_reading: float
    current_reading: float
    consumption_kwh: float
    kwh_price: float
    fixed_fee: float
    consumption_value: float
    carried_arrears: float
    total_due: float
    paid_amount: float
    remaining_balance: float
    invoice_id: Optional[int] = None
    invoice_number: Optional[str] = None
    invoice_status: str = "Unpaid"
    payment_id: Optional[int] = None
    receipt_number: Optional[str] = None
    payment_profile: str = "FULL"  # FULL, PARTIAL, OVERPAYMENT, ZERO
    is_reversed: bool = False

    def to_dict(self) -> Dict[str, Any]:
        """Convert record to dictionary with strict English numbers."""
        return asdict(self)


# Alias for backwards/interface compatibility
SimulationCycleResult = SimulationCycleRecord


@dataclass
class SimulationRunResult:
    """Aggregated results of the entire multi-cycle simulation."""

    subscribers_count: int
    cycles_count: int
    records: List[SimulationCycleRecord] = field(default_factory=list)
    baseline_snapshots: List[SubscriberSnapshot] = field(default_factory=list)
    total_billed_amount: float = 0.0
    total_paid_amount: float = 0.0
    total_remaining_arrears: float = 0.0
    total_consumption_kwh: float = 0.0
    total_reversals_tested: int = 0
    anomalies: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        """Convert result summary to dictionary."""
        return {
            "subscribers_count": self.subscribers_count,
            "cycles_count": self.cycles_count,
            "total_records": len(self.records),
            "total_billed_amount": round(self.total_billed_amount, 2),
            "total_paid_amount": round(self.total_paid_amount, 2),
            "total_remaining_arrears": round(self.total_remaining_arrears, 2),
            "total_consumption_kwh": round(self.total_consumption_kwh, 2),
            "total_reversals_tested": self.total_reversals_tested,
            "anomalies_count": len(self.anomalies),
        }


class SimulationEngine:
    """Executes multi-month billing cycle simulation across target subscribers."""

    def __init__(
        self,
        client: SmartPowerClient,
        config: Optional[SimulationConfig] = None,
    ):
        self.client = client
        self.config = config or default_config

    @staticmethod
    def generate_cycle_sequence(
        start_year: int = 2027,
        start_month: int = 3,
        count: int = 12,
    ) -> List[str]:
        """
        Generate chronological billing cycles sequence e.g. ['2027-03-1', '2027-04-1', ...].
        Handles annual boundary transition from December to January seamlessly.
        """
        cycles = []
        cur_year = start_year
        cur_month = start_month

        for _ in range(count):
            cycle_str = f"{cur_year}-{cur_month:02d}-1"
            cycles.append(cycle_str)
            cur_month += 1
            if cur_month > 12:
                cur_month = 1
                cur_year += 1

        return cycles

    def simulate_cycle_for_subscriber(
        self,
        snapshot: SubscriberSnapshot,
        cycle_name: str,
        cycle_index: int,
        prev_reading: float,
        prev_remaining: float,
        rng: random.Random,
        dry_run: bool = False,
    ) -> SimulationCycleRecord:
        """Simulate single billing cycle transaction for one subscriber."""
        cid = snapshot.customer_id

        # 1. Realistic consumption generation
        # 5% zero consumption cases (vacant property / travel)
        if rng.random() < self.config.zero_consumption_ratio:
            consumption = 0.0
        else:
            consumption = round(rng.uniform(
                self.config.min_consumption_kwh,
                self.config.max_consumption_kwh,
            ), 2)

        # Monotonicity rule: current_reading >= previous_reading
        current_reading = round(prev_reading + consumption, 2)

        # 2. Determine pricing
        kwh_price = self.config.default_kwh_price
        fixed_fee = self.config.default_fixed_fee

        consumption_val = round(consumption * kwh_price, 2)
        total_amount = round(consumption_val + fixed_fee, 2)
        carried_arrears = round(prev_remaining, 2)
        total_due = round(total_amount + carried_arrears, 2)

        # 3. Backend submission or local mock
        invoice_id = None
        invoice_num = None
        inv_status = "Unpaid"

        if not dry_run:
            try:
                sub_res = self.client.submit_reading(
                    customer_id=cid,
                    reading_value=current_reading,
                    billing_cycle=cycle_name,
                )
                if isinstance(sub_res, dict) and "invoice" in sub_res:
                    inv = sub_res["invoice"]
                    invoice_id = inv.get("id")
                    invoice_num = inv.get("invoice_number")
                    total_due = float(inv.get("total_due", total_due))
                    carried_arrears = float(inv.get("arrears", carried_arrears))
                    consumption_val = float(inv.get("consumption_value", consumption_val))
                    kwh_price = float(inv.get("kwh_price_snapshot", kwh_price))
                    fixed_fee = float(inv.get("fixed_fee_snapshot", fixed_fee))
                    inv_status = inv.get("status", "Unpaid")
            except Exception as e:
                logger.error("Failed to submit reading for customer %d: %s", cid, str(e))
                raise
        else:
            # Deterministic synthetic invoice number
            clean_sub = snapshot.subscriber_number.lstrip("0") or "0"
            invoice_num = f"INV-{cycle_name}-{clean_sub}"

        # 4. Payment Profile Simulation
        # Full payment (60%), Partial payment (20%), Overpayment (10%), Zero payment (10%)
        roll = rng.random()
        amount_to_pay = 0.0
        profile_name = "FULL"

        if total_due <= 0:
            # Customer already has surplus credit
            amount_to_pay = 0.0
            profile_name = "CREDIT_COVERED"
        elif roll < self.config.full_payment_ratio:
            amount_to_pay = total_due
            profile_name = "FULL"
        elif roll < (self.config.full_payment_ratio + self.config.partial_payment_ratio):
            # Partial payment: pay between 30% and 70% of total due
            ratio = rng.uniform(0.30, 0.70)
            amount_to_pay = round(total_due * ratio, 2)
            profile_name = "PARTIAL"
        elif roll < (self.config.full_payment_ratio + self.config.partial_payment_ratio + self.config.overpayment_ratio):
            # Overpayment: pay total due + excess (e.g. 5,000 or 10,000 YER)
            excess = rng.choice([5000.0, 10000.0])
            amount_to_pay = round(total_due + excess, 2)
            profile_name = "OVERPAYMENT"
        else:
            # Zero payment: carries forward 100% of debt
            amount_to_pay = 0.0
            profile_name = "ZERO"

        # 5. Payment Execution
        payment_id = None
        receipt_num = None

        if amount_to_pay > 0:
            if not dry_run:
                try:
                    pay_res = self.client.create_payment(
                        customer_id=cid,
                        amount_paid=amount_to_pay,
                        invoice_id=invoice_id,
                        payment_method="CASH",
                        notes=f"سداد محاكاة الدورة {cycle_name} - نمط {profile_name}",
                    )
                    payment_data = pay_res.get("payment", pay_res)
                    payment_id = payment_data.get("id")
                    receipt_num = payment_data.get("receipt_number")
                except Exception as e:
                    logger.error("Failed to execute payment for customer %d: %s", cid, str(e))
                    raise
            else:
                payment_id = 900000 + (cycle_index * 1000) + cid
                receipt_num = f"REC-2027-{payment_id:06d}"

        # 6. Calculate Remaining Balance
        remaining_balance = round(total_due - amount_to_pay, 2)
        if remaining_balance <= 0 and amount_to_pay >= total_due:
            inv_status = "Paid"
        elif amount_to_pay > 0:
            inv_status = "Partially_Paid"
        else:
            inv_status = "Unpaid"

        return SimulationCycleRecord(
            cycle_name=cycle_name,
            cycle_index=cycle_index,
            customer_id=cid,
            subscriber_number=snapshot.subscriber_number,
            full_name=snapshot.full_name,
            route_number=snapshot.route_number,
            previous_reading=prev_reading,
            current_reading=current_reading,
            consumption_kwh=consumption,
            kwh_price=kwh_price,
            fixed_fee=fixed_fee,
            consumption_value=consumption_val,
            carried_arrears=carried_arrears,
            total_due=total_due,
            paid_amount=amount_to_pay,
            remaining_balance=remaining_balance,
            invoice_id=invoice_id,
            invoice_number=invoice_num,
            invoice_status=inv_status,
            payment_id=payment_id,
            receipt_number=receipt_num,
            payment_profile=profile_name,
        )

    def run_simulation(
        self,
        snapshots: List[SubscriberSnapshot],
        cycles: Optional[List[str]] = None,
        dry_run: bool = False,
        progress_callback: Optional[Callable[[int, int, str], None]] = None,
    ) -> SimulationRunResult:
        """
        Execute full multi-cycle simulation across all selected subscribers.
        Maintains reading and balance state tracking for each subscriber.
        """
        cycle_list = cycles or self.generate_cycle_sequence(
            start_year=2027,
            start_month=3,
            count=self.config.billing_cycles_count,
        )

        total_steps = len(cycle_list) * len(snapshots)
        step = 0
        logger.info(
            "Starting financial simulation: %d subscribers x %d cycles (%d total transactions).",
            len(snapshots), len(cycle_list), total_steps
        )

        # Track live state per subscriber
        subscriber_state: Dict[int, Dict[str, float]] = {}
        for s in snapshots:
            subscriber_state[s.customer_id] = {
                "last_reading": s.last_reading,
                "remaining_balance": s.baseline_total_due,
            }

        rng = random.Random(self.config.random_seed)
        run_result = SimulationRunResult(
            subscribers_count=len(snapshots),
            cycles_count=len(cycle_list),
            baseline_snapshots=snapshots,
        )

        for c_idx, cycle_name in enumerate(cycle_list, start=1):
            logger.info("--- Simulating Cycle %d/%d: %s ---", c_idx, len(cycle_list), cycle_name)

            for s in snapshots:
                step += 1
                cid = s.customer_id
                state = subscriber_state[cid]

                record = self.simulate_cycle_for_subscriber(
                    snapshot=s,
                    cycle_name=cycle_name,
                    cycle_index=c_idx,
                    prev_reading=state["last_reading"],
                    prev_remaining=state["remaining_balance"],
                    rng=rng,
                    dry_run=dry_run,
                )

                # Update live tracking state for next cycle
                state["last_reading"] = record.current_reading
                state["remaining_balance"] = record.remaining_balance

                # Accumulate telemetry
                run_result.records.append(record)
                run_result.total_billed_amount += record.total_due
                run_result.total_paid_amount += record.paid_amount
                run_result.total_consumption_kwh += record.consumption_kwh

                # Detect mathematical anomalies
                expected_due = round(record.consumption_value + record.fixed_fee + record.carried_arrears, 2)
                if abs(record.total_due - expected_due) > 0.05:
                    anomaly = {
                        "type": "TOTAL_DUE_CALCULATION_MISMATCH",
                        "cycle": cycle_name,
                        "customer_id": cid,
                        "expected": expected_due,
                        "actual": record.total_due,
                    }
                    run_result.anomalies.append(anomaly)
                    logger.warning("Anomaly detected: %s", anomaly)

                if progress_callback and (step % 50 == 0 or step == total_steps):
                    progress_callback(step, total_steps, f"Cycle {cycle_name} ({step}/{total_steps})")

        # Compute total remaining arrears at end of simulation
        run_result.total_remaining_arrears = sum(
            state["remaining_balance"] for state in subscriber_state.values()
        )

        logger.info(
            "Simulation completed: %d records generated. Total Billed: %.2f YER, Total Paid: %.2f YER.",
            len(run_result.records),
            run_result.total_billed_amount,
            run_result.total_paid_amount,
        )
        return run_result
