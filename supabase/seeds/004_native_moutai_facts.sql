begin;

insert into fundamentals.metric_definitions (
    metric_code,name_cn,name_en,statement_type,default_unit,description
) values
('revenue_yoy_growth','营业收入同比增长率','Revenue YoY growth','derived_disclosure_metric','ratio','Reported or derived year-over-year revenue growth.'),
('net_income_parent_yoy_growth','归母净利润同比增长率','Parent net income YoY growth','derived_disclosure_metric','ratio','Reported or derived year-over-year parent net-income growth.'),
('shares_outstanding_inferred','推算加权平均股数','Inferred weighted-average shares','normalization','shares','Net income divided by basic EPS when direct shares are absent.'),
('growth_anchor','经营增长锚','Operating growth anchor','normalization','ratio','Versioned mechanical growth anchor from contemporaneous operating metrics.'),
('cash_conversion_ratio','现金转化率','Cash conversion ratio','normalization','ratio','Operating cash flow divided by parent net income; diagnostic only.'),
('maintenance_reserve_factor','维持性资本准备系数','Maintenance reserve factor','model_assumption','ratio','Explicit haircut when maintenance capex is not separately available.')
on conflict (metric_code) do update set
    name_cn=excluded.name_cn,
    name_en=excluded.name_en,
    statement_type=excluded.statement_type,
    default_unit=excluded.default_unit,
    description=excluded.description;

with issuer as (
    select issuer_id from master.issuers where issuer_code='KWEICHOW_MOUTAI'
), annual_doc as (
    select document_id from raw.documents
    where source_url='https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf'
    order by retrieved_at limit 1
), h1_doc as (
    select document_id from raw.documents
    where content_hash='709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71'
), rows(
    doc_kind,statement_type,metric_code,metric_label,period_start,period_end,
    fiscal_year,fiscal_period,fact_kind,value_numeric,unit,currency,
    published_at,available_at,source_fact_key,record_hash,metadata
) as (
    values
    ('annual','income_statement','revenue','营业收入','2020-01-01'::date,'2020-12-31'::date,2020,'FY','duration',94915380916.72::numeric,'CNY','CNY','2021-03-31 00:00:00+08'::timestamptz,'2021-03-31 00:00:00+08'::timestamptz,'2020FY:revenue','d5b05f66d74be87e35b8ad7e13fc6a18b3552db014a71a0cc14ae352793322ea','{"evidence_quality":"official_reference"}'::jsonb),
    ('annual','income_statement','net_income_parent','归属于母公司股东的净利润','2020-01-01','2020-12-31',2020,'FY','duration',46697285429.81,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:net_income_parent','d42d6071c2df12bb975c7f72c8acc861f2bfea06c89614e3a0579324234270d9','{"evidence_quality":"official_reference"}'::jsonb),
    ('annual','cash_flow','operating_cash_flow','经营活动产生的现金流量净额','2020-01-01','2020-12-31',2020,'FY','duration',51669068693.03,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:operating_cash_flow','40e3bc475f7166c29d7f5d10d4f4e259ee1a5bdf8b474dba870c003770a3d5b1','{"evidence_quality":"official_reference"}'::jsonb),
    ('annual','balance_sheet','total_assets','资产总计',null,'2020-12-31',2020,'FY','instant',213395810527.46,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:total_assets','0ab47ad9dd4b4b5153f5cbcadefbfeaf010295dbf8b2af8104465f1938a11e20','{"evidence_quality":"official_reference"}'::jsonb),
    ('annual','balance_sheet','equity_parent','归属于母公司股东的所有者权益',null,'2020-12-31',2020,'FY','instant',161322735087.56,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:equity_parent','1337b52e09f127c4f86281714a28c7e8dd04a8abb21a8e1f807d1d51bb786ffa','{"evidence_quality":"official_reference"}'::jsonb),
    ('annual','income_statement','basic_eps','基本每股收益','2020-01-01','2020-12-31',2020,'FY','duration',37.17,'CNY/share','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:basic_eps','1a5f723fe27e086f3a5dc7c44f2d07a920dc3e9e65af87b430b00c9ad896b509','{"evidence_quality":"official_reference"}'::jsonb),

    ('h1','income_statement','revenue','营业收入','2021-01-01','2021-06-30',2021,'H1','duration',49087277796.01,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:revenue','406a83c52b588c9649f3b806f9082c344629c30cd50eea2a7f5153b032f1afd5','{"evidence_quality":"derived_archive_cross_check","reported_yoy_growth":0.1168}'::jsonb),
    ('h1','income_statement','net_income_parent','归属于母公司股东的净利润','2021-01-01','2021-06-30',2021,'H1','duration',24653985551.58,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:net_income_parent','5330df5e8985745b73bf7f280071e353a1a39e0be8f0cb4912a19a4aaaf4582d','{"evidence_quality":"derived_archive_cross_check","reported_yoy_growth":0.0908}'::jsonb),
    ('h1','cash_flow','operating_cash_flow','经营活动产生的现金流量净额','2021-01-01','2021-06-30',2021,'H1','duration',21719470732.97,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:operating_cash_flow','14dd3ac9b283fe85690d087578a5008aad063be86aa360a9c998965ba26e8c6a','{"evidence_quality":"derived_archive_cross_check","use_in_model":"diagnostic_only"}'::jsonb),
    ('h1','balance_sheet','equity_parent','归属于母公司股东的所有者权益',null,'2021-06-30',2021,'H1','instant',161737770202.27,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:equity_parent','0d3dd3232a86b6a90cd9527bdc7d73220e85a053afc3021930def793e1628d48','{"evidence_quality":"derived_archive_cross_check"}'::jsonb),
    ('h1','income_statement','basic_eps','基本每股收益','2021-01-01','2021-06-30',2021,'H1','duration',19.63,'CNY/share','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:basic_eps','82526a93a218d4d5bcbd2e20eda762c939f04d333bd283c4d9cf278d23a78f54','{"evidence_quality":"derived_archive_cross_check"}'::jsonb),
    ('h1','derived_disclosure_metric','revenue_yoy_growth','营业收入同比增长率','2021-01-01','2021-06-30',2021,'H1','other',0.1168,'ratio',null,'2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:revenue_yoy_growth','53753b17a1781bd01d2fbb60113ceb1aa2197fbf89d51afeb6ffa53a2e6fda3d','{"evidence_quality":"derived_archive_cross_check"}'::jsonb),
    ('h1','derived_disclosure_metric','net_income_parent_yoy_growth','归母净利润同比增长率','2021-01-01','2021-06-30',2021,'H1','other',0.0908,'ratio',null,'2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:net_income_parent_yoy_growth','189ed7402ee994aec87a21db5dafdb848c00f3acf4d093f26e3f49a4bb2cf337','{"evidence_quality":"derived_archive_cross_check"}'::jsonb)
), prepared as (
    select (select issuer_id from issuer) as issuer_id,
           r.*,
           case when r.doc_kind='annual' then (select document_id from annual_doc)
                else (select document_id from h1_doc) end as source_document_id
    from rows r
)
update pit.financial_facts pf
set record_hash=p.record_hash,
    source_document_id=coalesce(pf.source_document_id,p.source_document_id),
    source_fact_key=coalesce(pf.source_fact_key,p.source_fact_key),
    metadata=pf.metadata || p.metadata
from prepared p
where pf.issuer_id=p.issuer_id
  and pf.metric_code=p.metric_code
  and pf.period_end=p.period_end
  and pf.available_at=p.available_at
  and pf.value_numeric=p.value_numeric
  and pf.record_hash is null;

with issuer as (
    select issuer_id from master.issuers where issuer_code='KWEICHOW_MOUTAI'
), annual_doc as (
    select document_id from raw.documents
    where source_url='https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf'
    order by retrieved_at limit 1
), h1_doc as (
    select document_id from raw.documents
    where content_hash='709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71'
), rows(
    doc_kind,statement_type,metric_code,metric_label,period_start,period_end,
    fiscal_year,fiscal_period,fact_kind,value_numeric,unit,currency,
    published_at,available_at,source_fact_key,record_hash,metadata
) as (
    values
    ('annual','income_statement','revenue','营业收入','2020-01-01'::date,'2020-12-31'::date,2020,'FY','duration',94915380916.72::numeric,'CNY','CNY','2021-03-31 00:00:00+08'::timestamptz,'2021-03-31 00:00:00+08'::timestamptz,'2020FY:revenue','d5b05f66d74be87e35b8ad7e13fc6a18b3552db014a71a0cc14ae352793322ea','{}'::jsonb),
    ('annual','income_statement','net_income_parent','归属于母公司股东的净利润','2020-01-01','2020-12-31',2020,'FY','duration',46697285429.81,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:net_income_parent','d42d6071c2df12bb975c7f72c8acc861f2bfea06c89614e3a0579324234270d9','{}'::jsonb),
    ('annual','cash_flow','operating_cash_flow','经营活动产生的现金流量净额','2020-01-01','2020-12-31',2020,'FY','duration',51669068693.03,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:operating_cash_flow','40e3bc475f7166c29d7f5d10d4f4e259ee1a5bdf8b474dba870c003770a3d5b1','{}'::jsonb),
    ('annual','balance_sheet','total_assets','资产总计',null,'2020-12-31',2020,'FY','instant',213395810527.46,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:total_assets','0ab47ad9dd4b4b5153f5cbcadefbfeaf010295dbf8b2af8104465f1938a11e20','{}'::jsonb),
    ('annual','balance_sheet','equity_parent','归属于母公司股东的所有者权益',null,'2020-12-31',2020,'FY','instant',161322735087.56,'CNY','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:equity_parent','1337b52e09f127c4f86281714a28c7e8dd04a8abb21a8e1f807d1d51bb786ffa','{}'::jsonb),
    ('annual','income_statement','basic_eps','基本每股收益','2020-01-01','2020-12-31',2020,'FY','duration',37.17,'CNY/share','CNY','2021-03-31 00:00:00+08','2021-03-31 00:00:00+08','2020FY:basic_eps','1a5f723fe27e086f3a5dc7c44f2d07a920dc3e9e65af87b430b00c9ad896b509','{}'::jsonb),
    ('h1','income_statement','revenue','营业收入','2021-01-01','2021-06-30',2021,'H1','duration',49087277796.01,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:revenue','406a83c52b588c9649f3b806f9082c344629c30cd50eea2a7f5153b032f1afd5','{"reported_yoy_growth":0.1168}'::jsonb),
    ('h1','income_statement','net_income_parent','归属于母公司股东的净利润','2021-01-01','2021-06-30',2021,'H1','duration',24653985551.58,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:net_income_parent','5330df5e8985745b73bf7f280071e353a1a39e0be8f0cb4912a19a4aaaf4582d','{"reported_yoy_growth":0.0908}'::jsonb),
    ('h1','cash_flow','operating_cash_flow','经营活动产生的现金流量净额','2021-01-01','2021-06-30',2021,'H1','duration',21719470732.97,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:operating_cash_flow','14dd3ac9b283fe85690d087578a5008aad063be86aa360a9c998965ba26e8c6a','{"use_in_model":"diagnostic_only"}'::jsonb),
    ('h1','balance_sheet','equity_parent','归属于母公司股东的所有者权益',null,'2021-06-30',2021,'H1','instant',161737770202.27,'CNY','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:equity_parent','0d3dd3232a86b6a90cd9527bdc7d73220e85a053afc3021930def793e1628d48','{}'::jsonb),
    ('h1','income_statement','basic_eps','基本每股收益','2021-01-01','2021-06-30',2021,'H1','duration',19.63,'CNY/share','CNY','2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:basic_eps','82526a93a218d4d5bcbd2e20eda762c939f04d333bd283c4d9cf278d23a78f54','{}'::jsonb),
    ('h1','derived_disclosure_metric','revenue_yoy_growth','营业收入同比增长率','2021-01-01','2021-06-30',2021,'H1','other',0.1168,'ratio',null,'2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:revenue_yoy_growth','53753b17a1781bd01d2fbb60113ceb1aa2197fbf89d51afeb6ffa53a2e6fda3d','{}'::jsonb),
    ('h1','derived_disclosure_metric','net_income_parent_yoy_growth','归母净利润同比增长率','2021-01-01','2021-06-30',2021,'H1','other',0.0908,'ratio',null,'2021-07-30 19:34:00+08','2021-08-02 09:30:00+08','2021H1:net_income_parent_yoy_growth','189ed7402ee994aec87a21db5dafdb848c00f3acf4d093f26e3f49a4bb2cf337','{}'::jsonb)
), prepared as (
    select (select issuer_id from issuer) as issuer_id,r.*,
           case when r.doc_kind='annual' then (select document_id from annual_doc)
                else (select document_id from h1_doc) end as source_document_id
    from rows r
)
insert into pit.financial_facts (
    issuer_id,statement_scope,statement_type,metric_code,metric_label,
    period_start,period_end,fiscal_year,fiscal_period,fact_kind,value_numeric,
    unit,currency,published_at,available_at,revision_no,source_document_id,
    source_fact_key,record_hash,metadata
)
select issuer_id,'consolidated',statement_type,metric_code,metric_label,
       period_start,period_end,fiscal_year,fiscal_period,fact_kind,value_numeric,
       unit,currency,published_at,available_at,1,source_document_id,
       source_fact_key,record_hash,metadata
from prepared p
where not exists (
    select 1 from pit.financial_facts pf where pf.record_hash=p.record_hash
);

insert into pit.market_bars (
    security_id,trade_date,close_price,trading_status,currency,available_at,
    source_id,record_hash,metadata
)
select s.security_id,'2021-08-30',1586.00,'close_observed','CNY',
       '2021-08-30 15:00:00+08',ds.source_id,
       'd8e3c33cfa5aabf5727ebc0a4ed93763e34041d5f4833c6af11c650c0bed1bf8',
       '{"data_quality":"provisional","evidence":"historical archive plus legacy workbook cross-check","ohlcv_complete":false}'::jsonb
from master.securities s
join raw.data_sources ds on ds.source_code='JIEMIAN_ARCHIVE'
where s.security_code='600519.SH'
on conflict (security_id,trade_date,source_id,available_at) do update set
    close_price=excluded.close_price,
    trading_status=excluded.trading_status,
    record_hash=excluded.record_hash,
    metadata=excluded.metadata;

with issuer as (select issuer_id from master.issuers where issuer_code='KWEICHOW_MOUTAI'),
rows(metric_code,period_start,period_end,value_numeric,unit,currency,available_at,record_hash,metadata) as (
    values
    ('shares_outstanding_inferred',null::date,'2020-12-31'::date,1256316530.2612321::numeric,'shares',null,'2021-03-31 00:00:00+08'::timestamptz,'74b6c7ef463fd636a0a18975d549faf41513c345c0308f6a5d26d90a01bea5c1','{"formula":"net_income_parent_2020 / basic_eps_2020"}'::jsonb),
    ('owner_earnings_per_share','2021-01-01','2021-06-30',38.5177842,'CNY/share','CNY','2021-08-02 09:30:00+08','3f07ced3ced89ee1786050056e477957da209610169c9cb65190841560c7585c','{"formula":"basic_eps_2020 * (1 + net_income_parent_yoy_growth_h1_2021) * 0.95","maintenance_reserve_factor":0.95,"ocf_use":"diagnostic_only","data_quality":"provisional"}'::jsonb),
    ('growth_anchor','2021-01-01','2021-06-30',0.1038,'ratio',null,'2021-08-02 09:30:00+08','86f00df1681137c2062a53a9c94e2649697067b918bb5e86d178b05ff3e88d65','{"formula":"(revenue_yoy_growth + net_income_parent_yoy_growth) / 2"}'::jsonb),
    ('cash_conversion_ratio','2020-01-01','2020-12-31',1.106468357153073,'ratio',null,'2021-03-31 00:00:00+08','b8c43d080c52ee00cb9ae19f9788d9ca8359e4507fb1cdf8abc6e08e8a9b8c09','{"formula":"operating_cash_flow_2020 / net_income_parent_2020","use_in_model":"diagnostic_only"}'::jsonb),
    ('cash_conversion_ratio','2021-01-01','2021-06-30',0.8809719908178523,'ratio',null,'2021-08-02 09:30:00+08','e828effd82ef64e1b29298b6e018b0fe8801f49bcc15f4878364a733581822cc','{"formula":"operating_cash_flow_h1_2021 / net_income_parent_h1_2021","use_in_model":"diagnostic_only"}'::jsonb)
)
insert into fundamentals.normalized_facts (
    issuer_id,metric_code,period_start,period_end,value_numeric,unit,currency,
    normalization_version,available_at,record_hash,metadata
)
select issuer.issuer_id,rows.metric_code,rows.period_start,rows.period_end,
       rows.value_numeric,rows.unit,rows.currency,
       'moutai_owner_earnings_normalization_v1',rows.available_at,
       rows.record_hash,rows.metadata
from issuer cross join rows
on conflict (record_hash) where record_hash is not null do nothing;

-- Lineage is rebuilt from stable hashes and business keys.
insert into fundamentals.fact_lineage (normalized_fact_id,source_fact_id,lineage_role)
select nf.normalized_fact_id,pf.fact_id,
       case
         when nf.metric_code='shares_outstanding_inferred' and pf.metric_code='net_income_parent' then 'numerator'
         when nf.metric_code='shares_outstanding_inferred' and pf.metric_code='basic_eps' then 'denominator'
         when nf.metric_code='owner_earnings_per_share' and pf.metric_code='basic_eps' then 'base_eps'
         when nf.metric_code='owner_earnings_per_share' then 'growth_input'
         when nf.metric_code='growth_anchor' then 'growth_input'
         when nf.metric_code='cash_conversion_ratio' and pf.metric_code='operating_cash_flow' then 'numerator'
         else 'denominator'
       end
from fundamentals.normalized_facts nf
join pit.financial_facts pf on pf.issuer_id=nf.issuer_id
where nf.normalization_version='moutai_owner_earnings_normalization_v1'
  and (
    (nf.metric_code='shares_outstanding_inferred' and nf.period_end='2020-12-31' and pf.period_end='2020-12-31' and pf.metric_code in ('net_income_parent','basic_eps'))
    or (nf.metric_code='owner_earnings_per_share' and pf.metric_code='basic_eps' and pf.period_end='2020-12-31')
    or (nf.metric_code='owner_earnings_per_share' and pf.metric_code='net_income_parent_yoy_growth' and pf.period_end='2021-06-30')
    or (nf.metric_code='growth_anchor' and pf.period_end='2021-06-30' and pf.metric_code in ('revenue_yoy_growth','net_income_parent_yoy_growth'))
    or (nf.metric_code='cash_conversion_ratio' and nf.period_end=pf.period_end and pf.metric_code in ('operating_cash_flow','net_income_parent'))
  )
on conflict do nothing;

commit;
