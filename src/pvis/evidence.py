"""历史时点证据资格校验。"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date


def _as_date(value: str | date) -> date:
    if isinstance(value, date):
        return value
    return date.fromisoformat(value)


def is_point_in_time_eligible(
    available_at: str | date, decision_at: str | date
) -> bool:
    """资料公开可用日不晚于决策日时，才允许进入历史决策。"""

    return _as_date(available_at) <= _as_date(decision_at)


@dataclass(frozen=True)
class EvidenceRecord:
    source: str
    available_at: str
    decision_at: str
    as_of: str | None = None

    def validate(self) -> None:
        if not self.source.strip():
            raise ValueError("证据来源不能为空")
        if not is_point_in_time_eligible(self.available_at, self.decision_at):
            raise ValueError("证据在决策时点尚不可用")
        if self.as_of is not None and _as_date(self.as_of) > _as_date(self.available_at):
            raise ValueError("资料期末日不能晚于公开可用日")

