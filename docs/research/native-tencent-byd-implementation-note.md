# Native Tencent and BYD implementation note

This change set introduces two independent Gate 0 native valuation replays and one shared holding-period bridge.

## Shared calculation contract

`value_driver_holding_result` re-values remaining explicit FCFF and terminal value at a selected horizon, applies an explicit equity bridge, translates reporting currency to quote currency when needed, and derives annualized return plus the 15% target entry price.

Company modules must disclose when the equity bridge or FX is held constant. The helper does not fetch data or select assumptions.

## Tencent

- model family: platform FCFF + SOTP;
- operating facts: 2021H1 disclosed revenue and non-IFRS operating profit;
- SOTP fact: disclosed fair value of listed investee stakes;
- scenario-specific investment discount;
- shared value-driver reinvestment discipline and bounded reverse solve;
- data status: provisional.

## BYD

- model family: manufacturing value-driver FCFF;
- operating facts: 2021H1 revenue, profit-before-tax proxy, tax expense, cash, debt, minority interest and shares;
- negative explicit FCFF is allowed and retained;
- terminal-value share above 100% is treated as an explicit dependency warning, not clipped;
- data status: provisional.

## Non-goals

- reproduce the legacy workbook by tuning assumptions;
- classify either security as an executable investment recommendation;
- treat the current market and FX proxies as authoritative;
- write native results into Supabase before multi-version CI passes.
