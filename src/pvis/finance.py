"""无外部依赖的基础投资计算。"""

from __future__ import annotations

from collections.abc import Iterable, Sequence


def npv(rate: float, cash_flows: Sequence[float]) -> float:
    if rate <= -1.0:
        raise ValueError("折现率必须大于 -100%")
    if not cash_flows:
        raise ValueError("现金流不能为空")
    return sum(value / ((1.0 + rate) ** period) for period, value in enumerate(cash_flows))


def irr(cash_flows: Sequence[float], tolerance: float = 1e-10) -> float:
    """用二分法计算常规现金流内部收益率。"""

    if len(cash_flows) < 2:
        raise ValueError("至少需要两个期间的现金流")
    if not any(value < 0 for value in cash_flows) or not any(
        value > 0 for value in cash_flows
    ):
        raise ValueError("现金流必须同时包含流出和流入")

    lower = -0.999999
    upper = 1.0
    lower_value = npv(lower, cash_flows)
    upper_value = npv(upper, cash_flows)

    while lower_value * upper_value > 0 and upper < 1_000_000:
        upper *= 2.0
        upper_value = npv(upper, cash_flows)
    if lower_value * upper_value > 0:
        raise ValueError("给定现金流无法在搜索范围内得到唯一内部收益率")

    for _ in range(256):
        midpoint = (lower + upper) / 2.0
        midpoint_value = npv(midpoint, cash_flows)
        if abs(midpoint_value) <= tolerance:
            return midpoint
        if lower_value * midpoint_value <= 0:
            upper = midpoint
        else:
            lower = midpoint
            lower_value = midpoint_value
    return (lower + upper) / 2.0


def target_entry_price(
    annual_distributions: Sequence[float], exit_value: float, target_rate: float
) -> float:
    """达到目标收益率时，未来分配和退出价值对应的最高现值。"""

    if target_rate <= -1.0:
        raise ValueError("目标收益率必须大于 -100%")
    if exit_value < 0 or any(value < 0 for value in annual_distributions):
        raise ValueError("分配和退出价值不能为负")
    years = len(annual_distributions)
    if years == 0:
        raise ValueError("至少需要一个年度")
    present_value = sum(
        value / ((1.0 + target_rate) ** period)
        for period, value in enumerate(annual_distributions, start=1)
    )
    return present_value + exit_value / ((1.0 + target_rate) ** years)


def max_drawdown(total_return_index: Iterable[float]) -> float:
    """计算总回报指数序列的最大回撤，结果为非正数。"""

    values = list(total_return_index)
    if not values:
        raise ValueError("总回报序列不能为空")
    if any(value <= 0 for value in values):
        raise ValueError("总回报指数必须为正数")

    peak = values[0]
    worst = 0.0
    for value in values:
        peak = max(peak, value)
        worst = min(worst, value / peak - 1.0)
    return worst

