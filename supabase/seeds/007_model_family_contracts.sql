begin;

insert into fundamentals.metric_definitions
    (metric_code, name_cn, name_en, statement_type, default_unit, description)
values
    ('operating_income', '营业利润/经营利润', 'Operating income', 'income_statement', 'currency', 'Operating profit before financing and non-operating items under the applicable accounting standard.'),
    ('ebit', '息税前利润', 'EBIT', 'normalized', 'currency', 'Normalized earnings before interest and tax.'),
    ('tax_rate_normalized', '正常化税率', 'Normalized tax rate', 'normalization', 'ratio', 'Tax rate used to convert operating profit to NOPAT; provenance must identify reported inputs and analyst adjustments.'),
    ('nopat', '税后经营利润', 'NOPAT', 'normalized', 'currency', 'Normalized after-tax operating profit, excluding financing and non-operating investment returns.'),
    ('depreciation_amortization', '折旧与摊销', 'Depreciation and amortization', 'cash_flow', 'currency', 'Reported or reconstructed depreciation and amortization.'),
    ('capital_expenditure', '资本开支', 'Capital expenditure', 'cash_flow', 'currency', 'Cash capital expenditure before maintenance/growth classification.'),
    ('maintenance_capex', '维护性资本开支', 'Maintenance capital expenditure', 'normalization', 'currency', 'Versioned estimate of capital spending required to maintain current operating capacity.'),
    ('working_capital_change', '营运资本变动', 'Change in working capital', 'cash_flow', 'currency', 'Period change in operating working capital using a documented sign convention.'),
    ('invested_capital', '投入资本', 'Invested capital', 'normalized', 'currency', 'Operating capital invested in the business under a versioned normalization policy.'),
    ('net_debt', '净负债', 'Net debt', 'balance_sheet', 'currency', 'Interest-bearing debt less cash and cash equivalents; negative values represent net cash.'),
    ('cash_and_equivalents', '现金及现金等价物', 'Cash and cash equivalents', 'balance_sheet', 'currency', 'Cash and cash equivalents at period end.'),
    ('shares_outstanding', '期末股份数', 'Shares outstanding', 'per_share_denominator', 'shares', 'Security-level shares outstanding at period end, adjusted only through explicitly recorded corporate actions.'),
    ('weighted_average_shares', '加权平均股份数', 'Weighted-average shares', 'per_share_denominator', 'shares', 'Weighted-average shares used for income-statement per-share metrics.'),
    ('owner_earnings', '所有者收益', 'Owner earnings', 'normalized', 'currency', 'Normalized cash earnings after maintenance reinvestment.'),
    ('sales_to_capital', '销售收入/投入资本', 'Sales-to-capital ratio', 'valuation_input', 'ratio', 'Revenue generated per unit of incremental invested capital.'),
    ('roic', '投入资本回报率', 'ROIC', 'normalized', 'ratio', 'NOPAT divided by average normalized invested capital.'),
    ('ronic', '新增资本回报率', 'RONIC', 'normalized', 'ratio', 'Incremental NOPAT divided by incremental invested capital over a documented measurement window.'),
    ('reinvestment_rate', '再投资率', 'Reinvestment rate', 'valuation_input', 'ratio', 'Reinvestment divided by NOPAT; for value-driver models it must reconcile with growth divided by RONIC.'),
    ('fcff', '企业自由现金流', 'Free cash flow to firm', 'normalized', 'currency', 'NOPAT less operating reinvestment.'),
    ('non_operating_assets', '非经营性资产', 'Non-operating assets', 'valuation_input', 'currency', 'Cash, listed investments and other assets valued separately from operating FCFF.'),
    ('investment_assets', '投资资产', 'Investment assets', 'balance_sheet', 'currency', 'Equity investments and other financial assets excluded from operating FCFF and valued separately.'),
    ('segment_revenue', '分部收入', 'Segment revenue', 'segment', 'currency', 'Revenue for a named operating segment; segment identifier belongs in metadata.'),
    ('segment_operating_profit', '分部经营利润', 'Segment operating profit', 'segment', 'currency', 'Operating profit for a named segment; segment identifier belongs in metadata.'),
    ('book_value_per_share', '每股净资产', 'Book value per share', 'normalized', 'currency/share', 'Parent-attributable common equity divided by the relevant security share denominator.'),
    ('roe', '净资产收益率', 'Return on equity', 'normalized', 'ratio', 'Parent-attributable earnings divided by average parent common equity under a versioned policy.'),
    ('payout_ratio', '分红率', 'Payout ratio', 'valuation_input', 'ratio', 'Common dividends divided by parent-attributable earnings.'),
    ('dividend_per_share', '每股股利', 'Dividend per share', 'corporate_action', 'currency/share', 'Cash dividend per eligible share, linked to official announcement and ex/payment dates.'),
    ('loans_gross', '贷款总额', 'Gross loans', 'balance_sheet', 'currency', 'Gross customer loans before provisions.'),
    ('customer_deposits', '客户存款', 'Customer deposits', 'balance_sheet', 'currency', 'Customer deposits at period end.'),
    ('net_interest_margin', '净息差', 'Net interest margin', 'bank_driver', 'ratio', 'Net interest income divided by average interest-earning assets using the issuer reporting convention.'),
    ('credit_cost', '信用成本', 'Credit cost', 'bank_driver', 'ratio', 'Loan impairment/provision expense divided by average gross loans under a documented convention.'),
    ('npl_ratio', '不良贷款率', 'NPL ratio', 'bank_driver', 'ratio', 'Non-performing loans divided by gross loans.'),
    ('provision_coverage_ratio', '拨备覆盖率', 'Provision coverage ratio', 'bank_driver', 'ratio', 'Loan-loss provisions divided by non-performing loans.'),
    ('cet1_ratio', '核心一级资本充足率', 'CET1 ratio', 'bank_driver', 'ratio', 'Common Equity Tier 1 capital divided by risk-weighted assets.'),
    ('risk_weighted_assets', '风险加权资产', 'Risk-weighted assets', 'balance_sheet', 'currency', 'Regulatory risk-weighted assets.'),
    ('residual_income_per_share', '每股剩余收益', 'Residual income per share', 'valuation_output', 'currency/share', 'Beginning book value per share multiplied by ROE less cost of equity.'),
    ('cost_of_equity', '股权资本成本', 'Cost of equity', 'valuation_input', 'ratio', 'Required return used in residual-income or equity cash-flow valuation.'),
    ('revenue_yoy_growth', '营业收入同比增速', 'Revenue year-on-year growth', 'derived', 'ratio', 'Year-on-year revenue growth using comparable periods and the same statement scope.'),
    ('net_income_parent_yoy_growth', '归母净利润同比增速', 'Parent net income year-on-year growth', 'derived', 'ratio', 'Year-on-year growth in parent-attributable net income using comparable periods.'),
    ('cash_conversion_ratio', '现金转化率', 'Cash conversion ratio', 'diagnostic', 'ratio', 'Operating cash flow divided by parent-attributable net income; diagnostic only unless the model policy states otherwise.'),
    ('growth_anchor', '经营增长锚', 'Operating growth anchor', 'valuation_input', 'ratio', 'Versioned growth prior derived from PIT-eligible operating evidence rather than a current consensus archive.')
on conflict (metric_code) do update set
    name_cn = excluded.name_cn,
    name_en = excluded.name_en,
    statement_type = excluded.statement_type,
    default_unit = excluded.default_unit,
    description = excluded.description;

insert into model.model_versions
    (model_name, semantic_version, model_family, status, effective_from, notes)
select * from (values
    ('owner_earnings_dcf', '1.0.0', 'owner_earnings_dcf', 'development', timestamptz '2026-08-30T00:00:00Z', 'High-moat consumer model with explicit fade, target-price and reverse-growth contracts.'),
    ('platform_fcff_sotp', '1.0.0', 'fcff_sotp', 'development', timestamptz '2026-08-30T00:00:00Z', 'Revenue-driver operating FCFF plus separately valued non-operating assets.'),
    ('value_driver_fcff', '1.0.0', 'value_driver_fcff', 'development', timestamptz '2026-08-30T00:00:00Z', 'Capital-intensive model enforcing growth = reinvestment rate x RONIC.'),
    ('bank_residual_income', '1.0.0', 'residual_income', 'development', timestamptz '2026-08-30T00:00:00Z', 'Bank model with book-value roll-forward, ROE fade, dividends and reverse-implied ROE.')
) as candidate(model_name, semantic_version, model_family, status, effective_from, notes)
where not exists (
    select 1 from model.model_versions existing
    where existing.model_name = candidate.model_name
      and existing.semantic_version = candidate.semantic_version
);

commit;
