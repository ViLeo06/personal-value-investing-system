begin;

insert into fundamentals.metric_definitions
    (metric_code,name_cn,name_en,statement_type,default_unit,description)
values
    ('revenue','营业收入','Revenue','income_statement','CNY','Consolidated operating revenue.'),
    ('net_income_parent','归母净利润','Net income attributable to parent','income_statement','CNY','Net income attributable to owners of the parent.'),
    ('operating_cash_flow','经营活动现金流量净额','Operating cash flow','cash_flow','CNY','Net cash generated from operating activities.'),
    ('total_assets','总资产','Total assets','balance_sheet','CNY','Consolidated total assets.'),
    ('equity_parent','归母净资产','Equity attributable to parent','balance_sheet','CNY','Equity attributable to owners of the parent.'),
    ('basic_eps','基本每股收益','Basic earnings per share','income_statement','CNY/share','Basic earnings per share.'),
    ('owner_earnings_proxy','所有者收益代理值','Owner earnings proxy','derived','CNY','Gate-0 conservative proxy: lower of parent net income and operating cash flow until maintenance capex is available.'),
    ('shares_outstanding_proxy','股份数量代理值','Shares outstanding proxy','derived','shares','Parent net income divided by basic EPS for Gate-0 reconciliation.'),
    ('owner_earnings_per_share_proxy','每股所有者收益代理值','Owner earnings per share proxy','derived','CNY/share','Owner earnings proxy divided by the derived share count.'),
    ('owner_earnings_conversion','所有者收益转换率','Owner earnings conversion ratio','derived','ratio','Owner earnings proxy divided by parent net income.')
on conflict (metric_code) do update
set name_cn=excluded.name_cn,name_en=excluded.name_en,
    statement_type=excluded.statement_type,default_unit=excluded.default_unit,
    description=excluded.description;

with src as (
    select f.* from pit.financial_facts f
    join master.issuers i using(issuer_id)
    where i.issuer_code='KWEICHOW_MOUTAI'
      and f.period_end=date '2020-12-31'
      and f.source_fact_key like 'KWEICHOW_MOUTAI|2020FY|%'
      and f.available_at<=timestamptz '2021-04-01 00:00:00+08'
)
insert into fundamentals.normalized_facts
    (issuer_id,metric_code,period_start,period_end,value_numeric,value_text,
     unit,currency,normalization_version,available_at,record_hash,metadata)
select s.issuer_id,s.metric_code,s.period_start,s.period_end,s.value_numeric,s.value_text,
       s.unit,s.currency,'gate0_v1',s.available_at,
       md5(concat_ws('|','gate0_v1',s.source_fact_key,s.record_hash)),
       jsonb_build_object('method','direct_mapping','source_fact_id',s.fact_id,
                          'source_fact_key',s.source_fact_key,'source_label',s.metric_label)
from src s
where not exists (
    select 1 from fundamentals.normalized_facts n
    where n.issuer_id=s.issuer_id and n.metric_code=s.metric_code
      and n.period_end=s.period_end and n.normalization_version='gate0_v1'
      and n.available_at=s.available_at
);

with base as (
    select i.issuer_id,
           max(f.value_numeric) filter(where f.metric_code='net_income_parent') as net_income,
           max(f.value_numeric) filter(where f.metric_code='operating_cash_flow') as ocf,
           max(f.value_numeric) filter(where f.metric_code='basic_eps') as eps,
           max(f.available_at) as available_at
    from master.issuers i join pit.financial_facts f using(issuer_id)
    where i.issuer_code='KWEICHOW_MOUTAI'
      and f.period_end=date '2020-12-31'
      and f.source_fact_key like 'KWEICHOW_MOUTAI|2020FY|%'
      and f.available_at<=timestamptz '2021-04-01 00:00:00+08'
    group by i.issuer_id
), derived as (
    select issuer_id,available_at,
           least(net_income,ocf) as owner_earnings,
           net_income/nullif(eps,0) as shares_proxy,
           least(net_income,ocf)/nullif(net_income/nullif(eps,0),0) as owner_eps,
           least(net_income,ocf)/nullif(net_income,0) as conversion
    from base
)
insert into fundamentals.normalized_facts
    (issuer_id,metric_code,period_end,value_numeric,unit,currency,
     normalization_version,available_at,record_hash,metadata)
select d.issuer_id,x.metric_code,date '2020-12-31',x.value_numeric,x.unit,x.currency,
       'gate0_v1',d.available_at,
       md5(concat_ws('|','gate0_v1',d.issuer_id::text,x.metric_code,x.value_numeric::text,d.available_at::text)),
       x.metadata
from derived d
cross join lateral (values
  ('owner_earnings_proxy',d.owner_earnings,'CNY','CNY',
   jsonb_build_object('method','least_of_net_income_and_ocf','status','prototype_proxy','requires','maintenance_capex_split')),
  ('shares_outstanding_proxy',d.shares_proxy,'shares',null::text,
   jsonb_build_object('method','net_income_divided_by_basic_eps','status','reconciliation_proxy')),
  ('owner_earnings_per_share_proxy',d.owner_eps,'CNY/share','CNY',
   jsonb_build_object('method','owner_earnings_proxy_divided_by_shares_proxy','status','prototype_proxy')),
  ('owner_earnings_conversion',d.conversion,'ratio',null::text,
   jsonb_build_object('method','owner_earnings_proxy_divided_by_net_income','status','prototype_proxy'))
) x(metric_code,value_numeric,unit,currency,metadata)
where not exists (
    select 1 from fundamentals.normalized_facts n
    where n.issuer_id=d.issuer_id and n.metric_code=x.metric_code
      and n.period_end=date '2020-12-31' and n.normalization_version='gate0_v1'
      and n.available_at=d.available_at
);

insert into fundamentals.fact_lineage
    (normalized_fact_id,source_fact_id,lineage_role)
select n.normalized_fact_id,f.fact_id,
       case when n.metric_code=f.metric_code then 'direct_source' else 'derivation_input' end
from fundamentals.normalized_facts n
join master.issuers i on i.issuer_id=n.issuer_id and i.issuer_code='KWEICHOW_MOUTAI'
join pit.financial_facts f on f.issuer_id=n.issuer_id and f.period_end=n.period_end
where n.normalization_version='gate0_v1'
  and n.period_end=date '2020-12-31'
  and f.available_at<=n.available_at
  and (
    n.metric_code=f.metric_code
    or (n.metric_code in ('owner_earnings_proxy','owner_earnings_conversion')
        and f.metric_code in ('net_income_parent','operating_cash_flow'))
    or (n.metric_code in ('shares_outstanding_proxy','owner_earnings_per_share_proxy')
        and f.metric_code in ('net_income_parent','operating_cash_flow','basic_eps'))
  )
on conflict do nothing;

commit;
