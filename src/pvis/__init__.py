"""个人价值投资系统的确定性计算内核。"""

from .evidence import EvidenceRecord, is_point_in_time_eligible
from .finance import irr, max_drawdown, target_entry_price
from .scenario import Scenario, analyze_scenarios

__all__ = [
    "EvidenceRecord",
    "Scenario",
    "analyze_scenarios",
    "irr",
    "is_point_in_time_eligible",
    "max_drawdown",
    "target_entry_price",
]

__version__ = "0.1.0"

