begin;

-- This seed reproduces the deliberately small six-fact Gate-0 evidence set.
-- It is not a substitute for full report parsing or a ten-year history.
with ids as (
    select
      (select source_id from raw.data_sources where source_code='CNINFO') as source_id,
      (select issuer_id from master.issuers where issuer_code='KWEICHOW_MOUTAI') as issuer_id,
      (select security_id from master.securities where security_code='600519.SH') as security_id
)
insert into raw.documents
    (source_id,issuer_id,security_id,document_type,title,mime_type,language,
     published_at,effective_date,content_hash,parser_version,metadata)
select source_id,issuer_id,security_id,'annual_report',
       '贵州茅台酒股份有限公司2020年年度报告','application/pdf','zh-CN',
       timestamptz '2021-03-31 00:00:00+08',date '2020-12-31',
       md5('KWEICHOW_MOUTAI|2020_ANNUAL_REPORT|gate0_manual_fact_set_v1'),
       'gate0_manual_v1',
       jsonb_build_object(
         'evidence_status','manual_numeric_extract_requires_binary_archive',
         'scope','six_fact_gate0_prototype',
         'source_locator_status','official_document_url_to_be_archived'
       )
from ids
where not exists (
    select 1 from raw.documents d
    where d.content_hash=md5('KWEICHOW_MOUTAI|2020_ANNUAL_REPORT|gate0_manual_fact_set_v1')
);

with context as (
    select i.issuer_id,d.document_id
    from master.issuers i
    join raw.documents d on d.issuer_id=i.issuer_id
    where i.issuer_code='KWEICHOW_MOUTAI'
      and d.content_hash=md5('KWEICHOW_MOUTAI|2020_ANNUAL_REPORT|gate0_manual_fact_set_v1')
    order by d.created_at desc limit 1
), facts(metric_code,metric_label,statement_type,period_start,period_end,fact_kind,value_numeric,unit,currency,source_fact_key) as (
    values
      ('revenue','营业收入','income_statement',date '2020-01-01',date '2020-12-31','duration',94915380916.72::numeric,'CNY','CNY','KWEICHOW_MOUTAI|2020FY|revenue|r1'),
      ('net_income_parent','归属于母公司所有者的净利润','income_statement',date '2020-01-01',date '2020-12-31','duration',46697285429.81::numeric,'CNY','CNY','KWEICHOW_MOUTAI|2020FY|net_income_parent|r1'),
      ('operating_cash_flow','经营活动产生的现金流量净额','cash_flow',date '2020-01-01',date '2020-12-31','duration',51669068693.03::numeric,'CNY','CNY','KWEICHOW_MOUTAI|2020FY|operating_cash_flow|r1'),
      ('total_assets','资产总计','balance_sheet',null::date,date '2020-12-31','instant',213395810527.46::numeric,'CNY','CNY','KWEICHOW_MOUTAI|2020FY|total_assets|r1'),
      ('equity_parent','归属于母公司所有者权益合计','balance_sheet',null::date,date '2020-12-31','instant',161322735087.56::numeric,'CNY','CNY','KWEICHOW_MOUTAI|2020FY|equity_parent|r1'),
      ('basic_eps','基本每股收益','income_statement',date '2020-01-01',date '2020-12-31','duration',37.17::numeric,'CNY/share','CNY','KWEICHOW_MOUTAI|2020FY|basic_eps|r1')
)
insert into pit.financial_facts
    (issuer_id,statement_scope,statement_type,metric_code,metric_label,
     period_start,period_end,fiscal_year,fiscal_period,fact_kind,value_numeric,
     unit,currency,published_at,available_at,revision_no,is_preliminary,
     source_document_id,source_fact_key,record_hash,metadata)
select c.issuer_id,'consolidated',f.statement_type,f.metric_code,f.metric_label,
       f.period_start,f.period_end,2020,'FY',f.fact_kind,f.value_numeric,
       f.unit,f.currency,timestamptz '2021-03-31 00:00:00+08',
       timestamptz '2021-03-31 00:00:00+08',1,false,c.document_id,f.source_fact_key,
       md5(concat_ws('|',f.source_fact_key,f.value_numeric::text,'2021-03-31T00:00:00+08')),
       jsonb_build_object('extraction_method','manual_gate0_seed','evidence_scope','prototype')
from context c cross join facts f
where not exists (
    select 1 from pit.financial_facts existing
    where existing.source_fact_key=f.source_fact_key
      and existing.revision_no=1
      and existing.available_at=timestamptz '2021-03-31 00:00:00+08'
);

-- Stable logical snapshot identity. Membership is materialized below.
insert into audit.data_snapshots
    (as_of_at,cutoff_policy_version,manifest,snapshot_hash)
select timestamptz '2021-04-01 00:00:00+08','pit_cutoff_v1',
       jsonb_build_object(
          'issuer_code','KWEICHOW_MOUTAI',
          'security_code','600519.SH',
          'decision_cutoff','2021-04-01T00:00:00+08:00',
          'eligible_rule','available_at <= decision_cutoff',
          'scope','prototype_financial_evidence_only'
       ),
       '9950df576f62d3a87aac8b7ee276a173'
where not exists (
    select 1 from audit.data_snapshots
    where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
);

-- Freeze both the evidence document and every financial fact using portable keys.
with s as (
    select snapshot_id,as_of_at from audit.data_snapshots
    where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
    order by created_at desc limit 1
), d as (
    select d.* from raw.documents d
    join master.issuers i using(issuer_id)
    where i.issuer_code='KWEICHOW_MOUTAI'
      and d.content_hash=md5('KWEICHOW_MOUTAI|2020_ANNUAL_REPORT|gate0_manual_fact_set_v1')
    order by d.created_at desc limit 1
)
insert into audit.snapshot_items
    (snapshot_id,input_type,input_id,input_key,input_hash,source_available_at,metadata)
select s.snapshot_id,'raw.documents',d.document_id::text,
       'CNINFO|KWEICHOW_MOUTAI|2020_ANNUAL_REPORT|2021-03-31',d.content_hash,
       d.published_at,jsonb_build_object('role','evidence_document','document_type',d.document_type)
from s cross join d
on conflict (snapshot_id,input_type,input_id) do update
set input_key=excluded.input_key,input_hash=excluded.input_hash,
    source_available_at=excluded.source_available_at,metadata=excluded.metadata;

with s as (
    select snapshot_id,as_of_at from audit.data_snapshots
    where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
    order by created_at desc limit 1
), eligible as (
    select f.* from pit.financial_facts f
    join master.issuers i using(issuer_id)
    cross join s
    where i.issuer_code='KWEICHOW_MOUTAI'
      and f.period_end=date '2020-12-31'
      and f.available_at<=s.as_of_at
      and f.source_fact_key like 'KWEICHOW_MOUTAI|2020FY|%'
)
insert into audit.snapshot_items
    (snapshot_id,input_type,input_id,input_key,input_hash,source_available_at,metadata)
select s.snapshot_id,'pit.financial_facts',e.fact_id::text,e.source_fact_key,
       e.record_hash,e.available_at,
       jsonb_build_object('metric_code',e.metric_code,'period_end',e.period_end,
                          'revision_no',e.revision_no,'source_document_id',e.source_document_id)
from eligible e cross join s
on conflict (snapshot_id,input_type,input_id) do update
set input_key=excluded.input_key,input_hash=excluded.input_hash,
    source_available_at=excluded.source_available_at,metadata=excluded.metadata;

with digest as (
    select snapshot_id,count(*)::int as item_count,
           md5(string_agg(concat_ws('|',input_type,input_key,coalesce(input_hash,'')),
                          '||' order by input_type,input_key)) as membership_hash
    from audit.snapshot_items
    group by snapshot_id
)
update audit.data_snapshots ds
set manifest=ds.manifest || jsonb_build_object(
      'snapshot_item_count',d.item_count,
      'membership_hash',d.membership_hash,
      'membership_hash_version','stable_input_key_v1',
      'membership_materialized',true
    )
from digest d
where ds.snapshot_id=d.snapshot_id
  and ds.snapshot_hash='9950df576f62d3a87aac8b7ee276a173';

commit;
