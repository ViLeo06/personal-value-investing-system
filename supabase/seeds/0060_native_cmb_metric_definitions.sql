begin;

-- Keep the clean-room metric dictionary complete before CMB normalization facts
-- are inserted. These upserts are intentionally idempotent and may refine
-- definitions that were introduced by earlier legacy/native seeds.
insert into fundamentals.metric_definitions (
    metric_code,name_cn,name_en,statement_type,default_unit,description
) values
('book_value_per_share','每股净资产','Book value per share','bank_balance_metric','currency/share','Common equity book value attributable to ordinary shareholders per share.'),
('roe','净资产收益率','Return on equity','bank_profitability','ratio','Return attributable to ordinary shareholders divided by average ordinary common equity.'),
('annualized_eps','年化每股收益','Annualized EPS','normalization','currency/share','Half-year EPS multiplied by two for diagnostic use only.'),
('net_interest_margin','净利息收益率','Net interest margin','bank_profitability','ratio','Annualized net interest income divided by average interest-earning assets.'),
('credit_cost','信用成本','Credit cost','bank_asset_quality','ratio','Annualized impairment charge on loans divided by average loans; source-specific definitions must be preserved.'),
('cost_income_ratio','成本收入比','Cost-income ratio','bank_efficiency','ratio','Operating expenses divided by operating revenue.'),
('non_performing_loan_ratio','不良贷款率','Non-performing-loan ratio','bank_asset_quality','ratio','Non-performing loans divided by total loans.'),
('common_equity_tier1_ratio','核心一级资本充足率','Common-equity Tier-1 ratio','bank_capital','ratio','Common-equity Tier-1 capital divided by risk-weighted assets under the reported regulatory approach.')
on conflict (metric_code) do update set
    name_cn=excluded.name_cn,
    name_en=excluded.name_en,
    statement_type=excluded.statement_type,
    default_unit=excluded.default_unit,
    description=excluded.description;

commit;
