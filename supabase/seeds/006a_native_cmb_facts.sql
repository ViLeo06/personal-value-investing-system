begin;

insert into fundamentals.metric_definitions (
    metric_code,name_cn,name_en,statement_type,default_unit,description
) values
('annualized_eps','年化每股收益','Annualized EPS','normalization','currency/share','Half-year EPS multiplied by two for diagnostic use only.'),
('cost_income_ratio','成本收入比','Cost-income ratio','bank_operating_metric','ratio','Operating expenses divided by operating revenue.'),
('non_performing_loan_ratio','不良贷款率','Non-performing-loan ratio','bank_asset_quality','ratio','Non-performing loans divided by total loans.'),
('common_equity_tier1_ratio','核心一级资本充足率','Common-equity Tier-1 ratio','bank_capital','ratio','Common-equity Tier-1 capital ratio.')
on conflict (metric_code) do update set
    name_cn=excluded.name_cn,
    name_en=excluded.name_en,
    statement_type=excluded.statement_type,
    default_unit=excluded.default_unit,
    description=excluded.description;

insert into raw.documents (
    source_id,issuer_id,security_id,document_type,title,source_url,mime_type,
    language,published_at,available_at,publication_precision,evidence_quality,
    effective_date,parser_version,metadata
)
select ds.source_id,i.issuer_id,s.security_id,'half_year_report',
       '招商银行股份有限公司2021年半年度报告（A股）',
       'https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF',
       'application/pdf','zh-CN','2021-08-14 00:00:00+08',
       '2021-08-16 09:30:00+08','date','official_reference','2021-06-30',
       'manual_official_reference_v1',
       '{"gate":"gate0","binary_archived":false,"evidence_status":"official_url_verified","next_usable_session":"2021-08-16T09:30:00+08:00","availability_policy":"availability_policy_v1"}'::jsonb
from raw.data_sources ds
join master.issuers i on i.issuer_code='CMB'
join master.securities s on s.issuer_id=i.issuer_id and s.security_code='600036.SH'
where ds.source_code='CNINFO'
  and not exists (
      select 1 from raw.documents d
      where d.source_url='https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF'
  );

with issuer as (
    select issuer_id from master.issuers where issuer_code='CMB'
), document as (
    select document_id from raw.documents
    where source_url='https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF'
    order by retrieved_at limit 1
), rows(
    statement_type,metric_code,metric_label,period_start,period_end,
    fiscal_year,fiscal_period,fact_kind,value_numeric,unit,currency,
    source_fact_key,record_hash,metadata
) as (
    values
    ('income_statement','revenue','营业收入','2021-01-01'::date,'2021-06-30'::date,2021,'H1','duration',168749000000::numeric,'CNY','CNY','2021H1:revenue','4b3c6da762f8405d120984d8e63b2c6e21f943e8ae87e226bd5ba6ae0878f9a4','{"report_page":6,"evidence_quality":"official_reference"}'::jsonb),
    ('income_statement','net_income_parent','归属于本行股东的净利润','2021-01-01','2021-06-30',2021,'H1','duration',61150000000,'CNY','CNY','2021H1:net_income_parent','de37ebe6217d431c268400207b433a8d0de1cbccb055a36485678ade91fb6704','{"report_page":6,"ordinary_shareholder_profit_after_perpetual_debt_interest":59175000000,"evidence_quality":"official_reference"}'::jsonb),
    ('income_statement','basic_eps','归属于本行普通股股东的基本每股收益','2021-01-01','2021-06-30',2021,'H1','duration',2.35,'CNY/share','CNY','2021H1:basic_eps','f3c941358b8780df4ac8452690ec9b689ba424072ea0803cef575363fcc5c8ca','{"report_page":6,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_balance_metric','book_value_per_share','归属于本行普通股股东的每股净资产',null,'2021-06-30',2021,'H1','instant',26.60,'CNY/share','CNY','2021H1:book_value_per_share','72839d63db30841a3a3830cae100418d0a80ef60607c2b48becd32cc86bdd204','{"report_page":7,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_profitability','roe','归属于本行普通股股东的平均净资产收益率（年化）','2021-01-01','2021-06-30',2021,'H1','other',0.1806,'ratio',null,'2021H1:roe','78c9a394f2aad8053fcf370b2397c2c7d70f69e0f74f55e54f24862bbf1395f6','{"report_page":6,"annualized":true,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_profitability','net_interest_margin','净利息收益率','2021-01-01','2021-06-30',2021,'H1','other',0.0249,'ratio',null,'2021H1:net_interest_margin','f7e3d3dab496170c24484566bb72cf7a87af5bfd0afc63a659e4778624a2136f','{"report_page":8,"annualized":true,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_asset_quality','credit_cost','信用成本（年化）','2021-01-01','2021-06-30',2021,'H1','other',0.0056,'ratio',null,'2021H1:credit_cost','58ba2c108ab2007bc29447123fdf0b16b5c65dc67015beabce7a2652f8acf9ff','{"report_page":8,"annualized":true,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_efficiency','cost_income_ratio','成本收入比','2021-01-01','2021-06-30',2021,'H1','other',0.2795,'ratio',null,'2021H1:cost_income_ratio','424aa6de0d42ff542745f77b27e09f74b089877655bf53fb1e65c93b38152e44','{"report_page":8,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_asset_quality','non_performing_loan_ratio','不良贷款率',null,'2021-06-30',2021,'H1','instant',0.0101,'ratio',null,'2021H1:non_performing_loan_ratio','f05df37c268540c5604a8def6b206feb7bf76a15f8048cdd423290cce273bb7f','{"report_page":8,"evidence_quality":"official_reference"}'::jsonb),
    ('bank_capital','common_equity_tier1_ratio','核心一级资本充足率（高级法）',null,'2021-06-30',2021,'H1','instant',0.1189,'ratio',null,'2021H1:common_equity_tier1_ratio','e3853b3d2e3d5fe0a4be2df61ac2c91f56fd24f33c8637cfc0bd7807b207932a','{"report_page":8,"evidence_quality":"official_reference"}'::jsonb),
    ('balance_sheet','total_assets','总资产',null,'2021-06-30',2021,'H1','instant',8885886000000,'CNY','CNY','2021H1:total_assets','8922e22399aa8db245bcd6beb7bb34968a7ae3b2a6e7b5beee04a3490e09cebb','{"report_page":7,"evidence_quality":"official_reference"}'::jsonb),
    ('balance_sheet','equity_parent','归属于本行股东权益',null,'2021-06-30',2021,'H1','instant',754875000000,'CNY','CNY','2021H1:equity_parent','00b5b99b818ffe4c7b783aedd8504453e57fcf986cdb6b9a6684fbaa4a8778a4','{"report_page":7,"includes_other_equity_instruments":true,"evidence_quality":"official_reference"}'::jsonb)
)
insert into pit.financial_facts (
    issuer_id,statement_scope,statement_type,metric_code,metric_label,
    period_start,period_end,fiscal_year,fiscal_period,fact_kind,value_numeric,
    unit,currency,published_at,available_at,source_document_id,source_fact_key,
    record_hash,metadata
)
select issuer.issuer_id,'consolidated',rows.statement_type,rows.metric_code,
       rows.metric_label,rows.period_start,rows.period_end,rows.fiscal_year,
       rows.fiscal_period,rows.fact_kind,rows.value_numeric,rows.unit,
       rows.currency,'2021-08-14 00:00:00+08','2021-08-16 09:30:00+08',
       document.document_id,rows.source_fact_key,rows.record_hash,rows.metadata
from issuer cross join document cross join rows
where not exists (
    select 1 from pit.financial_facts f where f.record_hash=rows.record_hash
);

with issuer as (
    select issuer_id from master.issuers where issuer_code='CMB'
), rows(metric_code,value_numeric,unit,currency,record_hash,metadata) as (
    values
    ('book_value_per_share',26.60::numeric,'CNY/share','CNY','7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881','{"role":"model_input","source_metric":"book_value_per_share"}'::jsonb),
    ('roe',0.1806,'ratio',null,'52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8','{"role":"scenario_anchor","annualized":true}'::jsonb),
    ('annualized_eps',4.70,'CNY/share','CNY','2649e37e05b105b7a7427090414faa453c147023872879b637622965757931c7','{"role":"diagnostic_only","formula":"2 * half_year_basic_eps"}'::jsonb),
    ('net_interest_margin',0.0249,'ratio',null,'243867c869661b2040de6148b75c804ca627ce7a45e8dcbf4d36e55bfb1b613b','{"role":"diagnostic"}'::jsonb),
    ('credit_cost',0.0056,'ratio',null,'0afac2ddd2d1c4dedea04182613f3f45940581433cce88ee2df4dc4c6926dc0b','{"role":"diagnostic"}'::jsonb),
    ('cost_income_ratio',0.2795,'ratio',null,'16c2f8d582ce74ec0be6b3db930e713f7aed8e40b456a9efdfc775b99d89eb04','{"role":"diagnostic"}'::jsonb),
    ('non_performing_loan_ratio',0.0101,'ratio',null,'05899fb2b022d53b8a93cf42cf999ea1833815efceb90b037e5d2ebcc671be0b','{"role":"diagnostic"}'::jsonb),
    ('common_equity_tier1_ratio',0.1189,'ratio',null,'40b9c7d39a4a0a0ad98950e180bc726f2c330d032c03c086aa38bab208ffba8d','{"role":"diagnostic"}'::jsonb)
)
insert into fundamentals.normalized_facts (
    issuer_id,metric_code,period_start,period_end,value_numeric,unit,currency,
    normalization_version,available_at,record_hash,metadata
)
select issuer.issuer_id,rows.metric_code,
       case when rows.metric_code in ('roe','annualized_eps','net_interest_margin','credit_cost','cost_income_ratio') then '2021-01-01'::date else null end,
       '2021-06-30',rows.value_numeric,rows.unit,rows.currency,
       'cmb_residual_income_normalization_v1','2021-08-16 09:30:00+08',
       rows.record_hash,rows.metadata
from issuer cross join rows
where not exists (
    select 1 from fundamentals.normalized_facts n where n.record_hash=rows.record_hash
);

insert into fundamentals.fact_lineage (
    normalized_fact_id,source_fact_id,lineage_role
)
select n.normalized_fact_id,f.fact_id,
       case when n.metric_code='annualized_eps' then 'derived_from' else 'input' end
from fundamentals.normalized_facts n
join master.issuers i on i.issuer_id=n.issuer_id and i.issuer_code='CMB'
join pit.financial_facts f on f.issuer_id=n.issuer_id
 and f.period_end=n.period_end
 and f.metric_code=case when n.metric_code='annualized_eps' then 'basic_eps' else n.metric_code end
where n.normalization_version='cmb_residual_income_normalization_v1'
  and not exists (
      select 1 from fundamentals.fact_lineage l
      where l.normalized_fact_id=n.normalized_fact_id and l.source_fact_id=f.fact_id
  );

update pit.market_bars b
set close_price=48.45,
    trading_status='closed',
    currency='CNY',
    record_hash='a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024',
    metadata=b.metadata ||
        '{"evidence_quality":"proxy","source_sheet":"CMB_2021","authoritative_replacement_required":true}'::jsonb
from master.securities s, raw.data_sources ds
where b.security_id=s.security_id
  and b.source_id=ds.source_id
  and s.security_code='600036.SH'
  and ds.source_code='LEGACY_BACKTEST_XLSX'
  and b.trade_date='2021-08-30'
  and b.available_at='2021-08-30 15:00:00+08';

insert into pit.market_bars (
    security_id,trade_date,close_price,trading_status,currency,available_at,
    source_id,record_hash,metadata
)
select s.security_id,'2021-08-30',48.45,'closed','CNY',
       '2021-08-30 15:00:00+08',ds.source_id,
       'a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024',
       '{"evidence_quality":"proxy","source_sheet":"CMB_2021","authoritative_replacement_required":true}'::jsonb
from master.securities s
join raw.data_sources ds on ds.source_code='LEGACY_BACKTEST_XLSX'
where s.security_code='600036.SH'
  and not exists (
      select 1
      from pit.market_bars b
      where b.security_id=s.security_id
        and b.trade_date='2021-08-30'
        and b.source_id=ds.source_id
        and b.available_at='2021-08-30 15:00:00+08'
  );

insert into audit.data_snapshots (
    as_of_at,cutoff_policy_version,manifest,snapshot_hash
) values (
    '2021-08-30 15:00:00+08','pit_cutoff_v1',
    '{"decision_cutoff":"2021-08-30T15:00:00+08:00","eligible_rule":"available_at <= decision_cutoff","financial_fact_count":12,"issuer_code":"CMB","market_bar_count":1,"normalized_fact_count":8,"scope":"native_cmb_2021_h1_provisional","security_code":"600036.SH","data_quality":"provisional","official_report_binary_archived":false,"authoritative_market_bar":false}'::jsonb,
    '8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5'
)
on conflict (snapshot_hash) do nothing;

commit;
