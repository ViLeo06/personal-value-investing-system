begin;

insert into fundamentals.accounting_field_rules
    (model_family,input_key,component_code,source_field_regex,
     expected_keywords,sign,aggregation_group,priority,auto_promote,notes)
values
    ('owner_earnings_dcf','depreciation_amortization','d_and_a_total',
     '(DEPR.*AMORT|DEPRECIATION.*AMORTIZATION|D_A_TOTAL)',
     array['折旧','摊销'],1,'d_and_a',10,false,
     'A total field is preferred only when it reconciles to the official cash-flow supplement.'),
    ('owner_earnings_dcf','depreciation_amortization','fixed_asset_depreciation',
     '(DEPR.*(FIX|FA)|FIX.*DEPR|DEPRECIATION.*FIX)',
     array['固定资产折旧','折旧'],1,'d_and_a',20,false,
     'Fixed-asset depreciation component.'),
    ('owner_earnings_dcf','depreciation_amortization','intangible_amortization',
     '(AMORT.*(INTANG|IA)|INTANG.*AMORT)',
     array['无形资产摊销','摊销'],1,'d_and_a',30,false,
     'Intangible-asset amortization component.'),
    ('owner_earnings_dcf','depreciation_amortization','deferred_expense_amortization',
     '(AMORT.*(DEFER|LONG_TERM_PREPAID|LPE)|DEFER.*AMORT)',
     array['长期待摊费用摊销','摊销'],1,'d_and_a',40,false,
     'Long-term deferred-expense amortization component.'),
    ('owner_earnings_dcf','maintenance_capex_upper_bound','qualifying_long_asset_cash_spend',
     '(CONSTRUCT.*LONG.*ASSET|PURCHASE.*FIXED.*INTANG|CASH.*PAID.*(FIXED|LONG).*ASSET|CAPEX)',
     array['购建固定资产、无形资产和其他长期资产支付的现金','资本开支'],1,
     'maintenance_capex_upper_bound',10,false,
     'Total qualifying long-asset cash spending is an upper bound, not automatically maintenance capex.'),
    ('owner_earnings_dcf','shares_outstanding','common_shares_outstanding',
     '(TOTAL_SHARE|TOTAL_SHARES|SHARES_OUTSTANDING|SHARE_TOTAL|END_SHARE_NUM)',
     array['股份总数','总股本','股本'],1,'shares_outstanding',10,true,
     'May auto-promote only when all page-matched candidates imply one identical share count.'),
    ('owner_earnings_dcf','net_cash_component','cash_and_equivalents',
     '(MONETARY.*FUND|CASH.*EQUIV|CASH_EQUIVALENT|MONEY_FUNDS)',
     array['货币资金'],1,'net_cash',10,false,
     'Cash candidate; operating/restricted cash review is still required.'),
    ('owner_earnings_dcf','net_cash_component','trading_financial_assets',
     '(TRADING.*FINANCIAL.*ASSET|TRADE.*FINASSET)',
     array['交易性金融资产'],1,'net_cash',20,false,
     'Liquid financial-asset candidate; liquidity and non-operating classification required.'),
    ('owner_earnings_dcf','net_cash_component','short_term_borrowings',
     '(SHORT.*(LOAN|BORROW)|ST_BORROW)',
     array['短期借款'],-1,'net_cash',30,false,
     'Interest-bearing short-term debt.'),
    ('owner_earnings_dcf','net_cash_component','long_term_borrowings',
     '(LONG.*(LOAN|BORROW)|LT_BORROW)',
     array['长期借款'],-1,'net_cash',40,false,
     'Interest-bearing long-term debt.'),
    ('owner_earnings_dcf','net_cash_component','bonds_payable',
     '(BOND.*PAYABLE|PAYABLE.*BOND)',
     array['应付债券'],-1,'net_cash',50,false,
     'Bonds payable.'),
    ('owner_earnings_dcf','net_cash_component','lease_liabilities',
     '(LEASE.*LIABIL)',
     array['租赁负债'],-1,'net_cash',60,false,
     'Lease liabilities require debt-like-obligation review.'),
    ('owner_earnings_dcf','working_capital_component','inventory',
     '(^|_)INVENTOR(Y|IES)($|_)',array['存货'],1,'operating_nwc',10,false,
     'Operating current asset.'),
    ('owner_earnings_dcf','working_capital_component','accounts_receivable',
     '(ACCOUNT.*RECEIV|ACCOUNTS_RECEIVABLE)',array['应收账款'],1,'operating_nwc',20,false,
     'Operating receivable.'),
    ('owner_earnings_dcf','working_capital_component','notes_receivable',
     '(NOTE.*RECEIV|BILL.*RECEIV)',array['应收票据'],1,'operating_nwc',30,false,
     'Operating notes receivable.'),
    ('owner_earnings_dcf','working_capital_component','other_receivables',
     '(OTHER.*RECEIV)',array['其他应收款'],1,'operating_nwc',40,false,
     'Requires removal of financing/non-operating balances.'),
    ('owner_earnings_dcf','working_capital_component','accounts_payable',
     '(ACCOUNT.*PAYABLE|ACCOUNTS_PAYABLE)',array['应付账款'],-1,'operating_nwc',50,false,
     'Operating payable.'),
    ('owner_earnings_dcf','working_capital_component','notes_payable',
     '(NOTE.*PAYABLE|BILL.*PAYABLE)',array['应付票据'],-1,'operating_nwc',60,false,
     'Operating notes payable.'),
    ('owner_earnings_dcf','working_capital_component','other_payables',
     '(OTHER.*PAYABLE)',array['其他应付款'],-1,'operating_nwc',70,false,
     'Requires removal of financing/non-operating balances.'),
    ('owner_earnings_dcf','working_capital_component','contract_liabilities',
     '(CONTRACT.*LIABIL)',array['合同负债'],-1,'operating_nwc',80,false,
     'Operating customer advances under the current accounting standard.'),
    ('owner_earnings_dcf','working_capital_component','advance_receipts',
     '(ADVANCE.*RECEIP|RECEIPT.*ADVANCE|UNEARNED.*REVENUE)',
     array['预收款项'],-1,'operating_nwc',90,false,
     'Operating customer advances under the prior presentation.' )
on conflict (model_family,input_key,component_code,source_field_regex) do update
set expected_keywords=excluded.expected_keywords,
    sign=excluded.sign,
    aggregation_group=excluded.aggregation_group,
    priority=excluded.priority,
    auto_promote=excluded.auto_promote,
    notes=excluded.notes,
    enabled=true;

create temporary table _structured_candidates on commit drop as
with source_records as (
    select
        r.*,
        coalesce(
            case when coalesce(
                r.payload->>'REPORT_DATE',r.payload->>'REPORTDATE',
                r.payload->>'END_DATE',r.payload->>'ENDDATE',
                r.payload->>'REPORT_END_DATE'
            ) ~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}'
            then left(coalesce(
                r.payload->>'REPORT_DATE',r.payload->>'REPORTDATE',
                r.payload->>'END_DATE',r.payload->>'ENDDATE',
                r.payload->>'REPORT_END_DATE'
            ),10)::date end,
            case when coalesce(
                r.payload->>'REPORT_DATE',r.payload->>'REPORTDATE',
                r.payload->>'END_DATE',r.payload->>'ENDDATE',
                r.payload->>'REPORT_END_DATE'
            ) ~ '^20[0-9]{6}$'
            then to_date(coalesce(
                r.payload->>'REPORT_DATE',r.payload->>'REPORTDATE',
                r.payload->>'END_DATE',r.payload->>'ENDDATE',
                r.payload->>'REPORT_END_DATE'
            ),'YYYYMMDD') end,
            case when r.source_record_key ~ '20[0-9]{2}-[0-9]{2}-[0-9]{2}'
                 then substring(r.source_record_key from '(20[0-9]{2}-[0-9]{2}-[0-9]{2})')::date end
        ) as period_end
    from raw.records r
    join master.issuers i on i.issuer_id=r.issuer_id
    where i.issuer_code='KWEICHOW_MOUTAI'
      and jsonb_typeof(r.payload)='object'
      and r.dataset_code like 'eastmoney_%'
      and r.dataset_code not like '%dividend%'
      and r.dataset_code not like '%sharebonus%'
      and r.dataset_code not like '%market%'
      and r.dataset_code not like '%price%'
), fields as (
    select
        sr.record_id,sr.document_id,sr.issuer_id,sr.dataset_code,
        sr.record_hash,sr.period_end,
        f.key as source_field,f.value as source_value_text,
        audit.parse_report_number(f.value) as value_numeric
    from source_records sr
    cross join lateral jsonb_each_text(sr.payload) f
    where sr.period_end in ('2019-12-31'::date,'2020-12-31'::date)
      and f.key !~* '(YOY|RATIO|RATE|PERCENT|PCT|GROWTH|NOTE|NAME|DATE|TYPE|CODE|ID|RANK)'
), matched as (
    select
        '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid as run_id,
        f.issuer_id,r.rule_id,r.input_key,r.component_code,f.period_end,
        f.record_id as source_record_id,f.document_id as source_document_id,
        f.dataset_code,f.source_field,f.source_value_text,f.value_numeric,
        r.sign,f.value_numeric*r.sign as signed_value,f.record_hash,
        r.priority,r.auto_promote,r.expected_keywords,r.notes
    from fields f
    join fundamentals.accounting_field_rules r
      on r.model_family='owner_earnings_dcf'
     and r.enabled
     and f.source_field ~* r.source_field_regex
    where f.value_numeric is not null
      and abs(f.value_numeric)<1000000000000000::numeric
), inserted as (
    insert into fundamentals.accounting_input_candidates
        (run_id,issuer_id,rule_id,input_key,component_code,period_end,
         source_record_id,source_document_id,dataset_code,source_field,
         source_value_text,value_numeric,sign,signed_value,source_record_hash,
         status,metadata)
    select
        m.run_id,m.issuer_id,m.rule_id,m.input_key,m.component_code,m.period_end,
        m.source_record_id,m.source_document_id,m.dataset_code,m.source_field,
        m.source_value_text,m.value_numeric,m.sign,m.signed_value,m.record_hash,
        'candidate',
        jsonb_build_object(
            'rule_priority',m.priority,
            'auto_promote',m.auto_promote,
            'expected_keywords',m.expected_keywords,
            'rule_notes',m.notes,
            'candidate_version','accounting-field-candidate-v1'
        )
    from matched m
    on conflict (run_id,rule_id,period_end,source_record_id,source_field) do update
    set source_value_text=excluded.source_value_text,
        value_numeric=excluded.value_numeric,
        sign=excluded.sign,
        signed_value=excluded.signed_value,
        source_record_hash=excluded.source_record_hash,
        metadata=excluded.metadata
    returning *
)
select * from inserted;

create temporary table _candidate_page_matches on commit drop as
with extraction as (
    select d.*
    from raw.documents d
    join master.issuers i on i.issuer_id=d.issuer_id
    where i.issuer_code='KWEICHOW_MOUTAI'
      and d.document_type='official_annual_report_extraction_v2'
      and length(coalesce(d.content_hash,''))=64
    order by d.retrieved_at desc,d.document_id desc
    limit 1
), hits as (
    select
        r.record_id,r.document_id,r.record_hash,r.payload,
        (r.payload->>'page')::integer as page_number,
        r.payload->>'keyword' as keyword
    from raw.records r
    join extraction e on e.document_id=r.document_id
    where r.dataset_code='cninfo_annual_report_page_hit_v2'
      and jsonb_typeof(r.payload->'candidate_numbers')='array'
), numbers as (
    select
        h.*,
        number_text,
        audit.parse_report_number(number_text) as parsed_number
    from hits h
    cross join lateral jsonb_array_elements_text(h.payload->'candidate_numbers') n(number_text)
), candidate_keywords as (
    select
        c.*,r.expected_keywords,
        unnest(r.expected_keywords) as expected_keyword
    from fundamentals.accounting_input_candidates c
    join fundamentals.accounting_field_rules r on r.rule_id=c.rule_id
    where c.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and c.period_end='2020-12-31'::date
      and c.status in ('candidate','page_matched','validated')
), matches as (
    select
        c.candidate_id,e.document_id as extraction_document_id,
        n.record_id as page_hit_record_id,n.page_number,n.keyword,
        n.number_text as source_number_text,n.parsed_number,s.scale,
        n.parsed_number*s.scale as normalized_value,
        c.value_numeric as candidate_value,
        abs(abs(n.parsed_number*s.scale)-abs(c.value_numeric)) as absolute_difference,
        case when c.value_numeric=0 then null
             else abs(abs(n.parsed_number*s.scale)-abs(c.value_numeric))/abs(c.value_numeric) end
             as relative_difference,
        n.record_hash as page_hit_record_hash,
        c.source_record_hash,c.source_field,c.dataset_code,
        e.content_hash as extraction_hash,
        e.metadata->>'official_pdf_hash' as official_pdf_hash,
        n.payload->>'snippet' as snippet
    from candidate_keywords c
    join numbers n on n.keyword=c.expected_keyword and n.parsed_number is not null
    cross join extraction e
    cross join lateral (values
        (1::numeric),(1000::numeric),(10000::numeric),(1000000::numeric)
    ) s(scale)
    where abs(abs(n.parsed_number*s.scale)-abs(c.value_numeric))<=greatest(
        0.05::numeric,
        s.scale*0.011::numeric,
        abs(c.value_numeric)*0.000000001::numeric
    )
), inserted as (
    insert into audit.accounting_candidate_page_matches
        (candidate_id,extraction_document_id,page_hit_record_id,page_number,
         keyword,source_number_text,parsed_number,scale,normalized_value,
         candidate_value,absolute_difference,relative_difference,status,metadata)
    select
        m.candidate_id,m.extraction_document_id,m.page_hit_record_id,m.page_number,
        m.keyword,m.source_number_text,m.parsed_number,m.scale,m.normalized_value,
        m.candidate_value,m.absolute_difference,m.relative_difference,'candidate',
        jsonb_build_object(
            'page_hit_record_hash',m.page_hit_record_hash,
            'source_record_hash',m.source_record_hash,
            'source_field',m.source_field,
            'dataset_code',m.dataset_code,
            'extraction_hash',m.extraction_hash,
            'official_pdf_hash',m.official_pdf_hash,
            'snippet',m.snippet,
            'matching_version','accounting-candidate-page-match-v1'
        )
    from matches m
    on conflict (candidate_id,page_hit_record_id,source_number_text,scale) do update
    set page_number=excluded.page_number,
        keyword=excluded.keyword,
        parsed_number=excluded.parsed_number,
        normalized_value=excluded.normalized_value,
        candidate_value=excluded.candidate_value,
        absolute_difference=excluded.absolute_difference,
        relative_difference=excluded.relative_difference,
        metadata=excluded.metadata
    returning *
)
select * from inserted;

with ranked as (
    select
        m.match_id,
        row_number() over(
            partition by m.candidate_id
            order by m.relative_difference nulls last,m.absolute_difference,
                     m.page_number,m.match_id
        ) as rn
    from audit.accounting_candidate_page_matches m
    join fundamentals.accounting_input_candidates c on c.candidate_id=m.candidate_id
    where c.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and c.period_end='2020-12-31'::date
      and m.status in ('candidate','validated')
)
update audit.accounting_candidate_page_matches m
set status=case when r.rn=1 then 'validated' else 'candidate' end,
    validated_at=case when r.rn=1 then now() else null end
from ranked r
where r.match_id=m.match_id;

update fundamentals.accounting_input_candidates c
set status=case when exists (
        select 1 from audit.accounting_candidate_page_matches m
        where m.candidate_id=c.candidate_id and m.status='validated'
    ) then 'page_matched' else 'candidate' end,
    validated_at=case when exists (
        select 1 from audit.accounting_candidate_page_matches m
        where m.candidate_id=c.candidate_id and m.status='validated'
    ) then now() else null end
where c.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
  and c.period_end='2020-12-31'::date
  and c.status in ('candidate','page_matched');

create temporary table _validated_share on commit drop as
with eligible as (
    select
        c.*,
        m.match_id,m.page_number,m.keyword,m.source_number_text,m.scale,
        m.relative_difference,m.metadata as match_metadata,
        r.priority,
        count(distinct c.value_numeric) over() as distinct_value_count,
        row_number() over(
            order by r.priority,m.relative_difference nulls last,
                     m.absolute_difference,c.candidate_id,m.match_id
        ) as rn
    from fundamentals.accounting_input_candidates c
    join fundamentals.accounting_field_rules r on r.rule_id=c.rule_id
    join audit.accounting_candidate_page_matches m
      on m.candidate_id=c.candidate_id and m.status='validated'
    where c.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and c.input_key='shares_outstanding'
      and c.period_end='2020-12-31'::date
      and c.status='page_matched'
      and c.value_numeric between 100000000::numeric and 10000000000::numeric
)
select * from eligible
where distinct_value_count=1 and rn=1;

insert into model.run_assumptions
    (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
select
    s.run_id,'control','shares_outstanding',s.value_numeric,'shares',
    'official_document_plus_derived_adapter',
    jsonb_build_object(
        'candidate_id',s.candidate_id,
        'source_record_id',s.source_record_id,
        'source_document_id',s.source_document_id,
        'dataset_code',s.dataset_code,
        'source_field',s.source_field,
        'source_record_hash',s.source_record_hash,
        'period_end',s.period_end,
        'official_page_match_id',s.match_id,
        'official_page',s.page_number,
        'official_keyword',s.keyword,
        'official_source_number_text',s.source_number_text,
        'official_scale',s.scale,
        'official_pdf_hash',s.match_metadata->>'official_pdf_hash',
        'official_extraction_hash',s.match_metadata->>'extraction_hash',
        'timing_role','decision_input',
        'available_at','2021-03-31T16:00:00Z',
        'validation','one distinct page-matched share count across all structured candidates',
        'promotion_version','shares-outstanding-auto-promotion-v1'
    )
from _validated_share s
where not exists (
    select 1 from model.run_assumptions a
    where a.run_id=s.run_id
      and a.scenario='control'
      and a.assumption_key='shares_outstanding'
);

insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    'shares_outstanding','valuation_run_input',
    s.run_id::text||'|shares_outstanding',
    '2021-03-31T16:00:00Z'::timestamptz,
    3,'active',array['CNINFO','AKSHARE_EASTMONEY_FINANCIAL'],
    array_remove(array[
        s.match_metadata->>'official_pdf_hash',
        s.match_metadata->>'extraction_hash',
        s.match_metadata->>'page_hit_record_hash',
        s.source_record_hash
    ],null),
    false,
    jsonb_build_object(
        'value',s.value_numeric,
        'unit','shares',
        'candidate_id',s.candidate_id,
        'source_record_id',s.source_record_id,
        'source_field',s.source_field,
        'dataset_code',s.dataset_code,
        'page',s.page_number,
        'keyword',s.keyword,
        'source_number_text',s.source_number_text,
        'scale',s.scale,
        'quality_reason','one distinct structured candidate exactly reconciled to a hashed official PDF page'
    ),
    'shares-outstanding-auto-promotion-v1'
from _validated_share s
where not exists (
    select 1 from audit.evidence_assertions e
    where e.assertion_code='shares_outstanding'
      and e.subject_type='valuation_run_input'
      and e.subject_id=s.run_id::text||'|shares_outstanding'
      and e.evidence_grade=3
      and e.status='active'
);

with summary as (
    select
        count(*)::integer as candidate_count,
        count(*) filter(where status='page_matched')::integer as page_matched_count,
        count(distinct input_key)::integer as input_key_count,
        count(distinct component_code)::integer as component_count,
        coalesce(jsonb_object_agg(input_key,input_summary order by input_key),'{}'::jsonb)
            as by_input
    from (
        select
            input_key,
            jsonb_build_object(
                'candidate_count',count(*),
                'page_matched_count',count(*) filter(where status='page_matched'),
                'periods',array_agg(distinct period_end order by period_end),
                'components',array_agg(distinct component_code order by component_code)
            ) as input_summary
        from fundamentals.accounting_input_candidates
        where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
        group by input_key
    ) grouped
), flattened as (
    select
        coalesce(sum((value->>'candidate_count')::integer),0)::integer as candidate_count,
        coalesce(sum((value->>'page_matched_count')::integer),0)::integer as page_matched_count,
        count(*)::integer as input_key_count,
        coalesce(sum(jsonb_array_length(value->'components')),0)::integer as component_count,
        jsonb_object_agg(key,value) as by_input
    from summary s
    cross join lateral jsonb_each(s.by_input)
)
update audit.data_quality_issues q
set severity='info',status='open',detected_at=now(),
    description='Structured accounting candidates have been inventoried; non-share inputs require explicit policy-based aggregation and review.',
    details=jsonb_build_object(
        'candidate_count',f.candidate_count,
        'page_matched_count',f.page_matched_count,
        'input_key_count',f.input_key_count,
        'component_count',f.component_count,
        'by_input',f.by_input,
        'automatic_promotion_scope','shares_outstanding only'
    )
from flattened f
where q.rule_code='ACCOUNTING_INPUT_CANDIDATE_REVIEW_REQUIRED'
  and q.record_key='KWEICHOW_MOUTAI|2021-04-01|OWNER_EARNINGS';

with grouped as (
    select input_key,
           jsonb_build_object(
               'candidate_count',count(*),
               'page_matched_count',count(*) filter(where status='page_matched'),
               'periods',array_agg(distinct period_end order by period_end),
               'components',array_agg(distinct component_code order by component_code)
           ) as input_summary
    from fundamentals.accounting_input_candidates
    where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
    group by input_key
), summary as (
    select
        coalesce(sum((input_summary->>'candidate_count')::integer),0)::integer as candidate_count,
        coalesce(sum((input_summary->>'page_matched_count')::integer),0)::integer as page_matched_count,
        count(*)::integer as input_key_count,
        coalesce(sum(jsonb_array_length(input_summary->'components')),0)::integer as component_count,
        coalesce(jsonb_object_agg(input_key,input_summary),'{}'::jsonb) as by_input
    from grouped
)
insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'info','accounting_input_review','fundamentals.accounting_input_candidates',
    'KWEICHOW_MOUTAI|2021-04-01|OWNER_EARNINGS',
    'ACCOUNTING_INPUT_CANDIDATE_REVIEW_REQUIRED',
    'Structured accounting candidates have been inventoried; non-share inputs require explicit policy-based aggregation and review.',
    'open',
    jsonb_build_object(
        'candidate_count',s.candidate_count,
        'page_matched_count',s.page_matched_count,
        'input_key_count',s.input_key_count,
        'component_count',s.component_count,
        'by_input',s.by_input,
        'automatic_promotion_scope','shares_outstanding only'
    )
from summary s
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='ACCOUNTING_INPUT_CANDIDATE_REVIEW_REQUIRED'
      and q.record_key='KWEICHOW_MOUTAI|2021-04-01|OWNER_EARNINGS'
      and q.status='open'
);

with share_state as (
    select
        count(*) filter(
            where a.value_numeric is not null
        )::integer as assumption_count,
        count(*) filter(
            where e.evidence_grade>=3
              and e.status='active'
              and cardinality(e.content_hashes)>0
              and not e.unresolved_conflict
        )::integer as evidence_count
    from model.run_assumptions a
    left join audit.evidence_assertions e
      on e.assertion_code='shares_outstanding'
     and e.subject_type='valuation_run_input'
     and e.subject_id=a.run_id::text||'|shares_outstanding'
    where a.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and a.scenario='control'
      and a.assumption_key='shares_outstanding'
)
insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details,
     resolved_at)
select
    case when assumption_count=1 and evidence_count>=1 then 'info' else 'critical' end,
    'formal_input','model.run_assumptions',
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13|shares_outstanding',
    'SHARES_OUTSTANDING_UNAMBIGUOUS_REQUIRED',
    case when assumption_count=1 and evidence_count>=1
         then 'Point-in-time shares outstanding were released from one unambiguous official-page-matched value.'
         else 'Point-in-time shares outstanding remain blocked because a single official-page-matched value was not established.' end,
    case when assumption_count=1 and evidence_count>=1 then 'resolved' else 'open' end,
    jsonb_build_object(
        'assumption_count',assumption_count,
        'qualifying_evidence_count',evidence_count,
        'promotion_version','shares-outstanding-auto-promotion-v1'
    ),
    case when assumption_count=1 and evidence_count>=1 then now() else null end
from share_state
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='SHARES_OUTSTANDING_UNAMBIGUOUS_REQUIRED'
      and q.record_key='8bcbb9d3-7fdb-529a-9f9a-547043040e13|shares_outstanding'
      and q.status=case when share_state.assumption_count=1 and share_state.evidence_count>=1
                        then 'resolved' else 'open' end
);

commit;
