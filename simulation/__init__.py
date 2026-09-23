"""
SmartPower ERP Financial Simulation and Stress-Testing Package.

This package provides a comprehensive simulation, verification, and proof-generation suite
for the SmartPower ERP Go backend and PostgreSQL database.
"""

from simulation.config import SimulationConfig, config
from simulation.client import SmartPowerClient
from simulation.selector import SubscriberSelector, SubscriberSnapshot
from simulation.engine import SimulationEngine, SimulationCycleResult, SimulationRunResult
from simulation.verifier import FinancialVerifier, VerificationResult
from simulation.receipt_renderer import ReceiptRenderer
from simulation.excel_exporter import ExcelExporter

__version__ = "1.0.0"
__all__ = [
    "SimulationConfig",
    "config",
    "SmartPowerClient",
    "SubscriberSelector",
    "SubscriberSnapshot",
    "SimulationEngine",
    "SimulationCycleResult",
    "SimulationRunResult",
    "FinancialVerifier",
    "VerificationResult",
    "ReceiptRenderer",
    "ExcelExporter",
]
