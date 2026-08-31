begin;

insert into fundamentals.accounting_field_rules
    (model_family,input_key,component_code,source_field_regex,
     expected_keywords,sign,aggregation_group,priority,auto_promote,notes)
values
    ('owner_earnings_dcf','depreciation_amortization','d_and_a_total',
     '(DEPR.*AMORT|DEPRECIATION.*AMORTIZATION|D_A_TOTAL)',
     array['折旧','摊销'],1,'d_and_a',10,false,
     'Total D&A candidate; official cash-flow supplement reconciliation required.'),
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
     array['购建固定资产、无形资产和其他长期资产支付的现金','资本开支'],
     1,'maintenance_capex_upper_bound',10,false,
     'Upper bound only; project-level maintenance/growth classification remains mandatory.'),
    ('owner_earnings_dcf','shares_outstanding','common_shares_outstanding',
     '(TOTAL_SHARE|TOTAL_SHARES|SHARES_OUTSTANDING|SHARE_TOTAL|END_SHARE_NUM)',
     array['股份总数','总股本','股本'],1,'shares_outstanding',10,true,
     'Auto-promote only if every page-matched candidate implies one identical value.'),
    ('owner_earnings_dcf','net_cash_component','cash_and_equivalents',
     '(MONETARY.*FUND|CASH.*EQUIV|CASH_EQUIVALENT|MONEY_FUNDS)',
     array['货币资金'],1,'net_cash',10,false,
     'Cash candidate; operating/restricted cash review required.'),
    ('owner_earnings_dcf','net_cash_component','trading_financial_assets',
     '(TRADING.*FINANCIAL.*ASSET|TRADE.*FINASSET)',
     array['交易性金融资产'],1,'net_cash',20,false,
     'Liquidity/non-operating classification required.'),
    ('owner_earnings_dcf','net_cash_component','short_term_borrowings',
     '(SHORT.*(LOAN|BORROW)|ST_BORROW)',array['短期借款'],-1,'net_cash',30,false,
     'Interest-bearing short-term debt.'),
    ('owner_earnings_dcf','net_cash_component','long_term_borrowings',
     '(LONG.*(LOAN|BORROW)|LT_BORROW)',array['长期借款'],-1,'net_cash',40,false,
     'Interest-bearing long-term debt.'),
    ('owner_earnings_dcf','net_cash_component','bonds_payable',
     '(BOND.*PAYABLE|PAYABLE.*BOND)',array['应付债券'],-1,'net_cash',50,false,
     'Bonds payable.'),
    ('owner_earnings_dcf','net_cash_component','lease_liabilities',
     '(LEASE.*LIABIL)',array['租赁负债'],-1,'net_cash',60,false,
     'Debt-like classification review required.'),
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
     'Remove financing/non-operating balances.'),
    ('owner_earnings_dcf','working_capital_component','accounts_payable',
     '(ACCOUNT.*PAYABLE|ACCOUNTS_PAYABLE)',array['应付账款'],-1,'operating_nwc',50,false,
     'Operating payable.'),
    ('owner_earnings_dcf','working_capital_component','notes_payable',
     '(NOTE.*PAYABLE|BILL.*PAYABLE)',array['应付票据'],-1,'operating_nwc',60,false,
     'Operating notes payable.'),
    ('owner_earnings_dcf','working_capital_component','other_payables',
     '(OTHER.*PAYABLE)',array['其他应付款'],-1,'operating_nwc',70,false,
     'Remove financing/non-operating balances.'),
    ('owner_earnings_dcf','working_capital_component','contract_liabilities',
     '(CONTRACT.*LIABIL)',array['合同负债'],-1,'operating_nwc',80,false,
     'Operating customer advances.'),
    ('owner_earnings_dcf','working_capital_component','advance_receipts',
     '(ADVANCE.*RECEIP|RECEIPT.*ADVANCE|UNEARNED.*REVENUE)',
     array['预收款项'],-1,'operating_nwc',90,false,
     'Operating customer advances under prior presentation.')
on conflict (model_family,input_key,component_code,source_field_regex) do update
set expected_keywords=excluded.expected_keywords,
    sign=excluded.sign,
    aggregation_group=excluded.aggregation_group,
    priority=excluded.priority,
    auto_promote=excluded.auto_promote,
    notes=excluded.notes,
    enabled=true;

create or replace function fundamentals.refresh_accounting_input_candidates(
    p_run_id uuid,
    p_period_end date
)
returns integer
language plpgsql
security invoker
set search_path=''
as $$
declare
    v_count integer := 0;
begin
    with run_context as (
        select vr.run_id,vr.issuer_id,mv.model_family
        from model.valuation_runs vr
        join model.model_versions mv on mv.model_version_id=vr.model_version_id
        where vr.run_id=p_run_id
    ), source_records as (
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
        join run_context c on c.issuer_id=r.issuer_id
        where jsonb_typeof(r.payload)='object'
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
        where sr.period_end=p_period_end
          and f.key !~* '(YOY|RATIO|RATE|PERCENT|PCT|GROWTH|NOTE|NAME|DATE|TYPE|CODE|ID|RANK)'
    ), matched as (
        select
            c.run_id,f.issuer_id,r.rule_id,r.input_key,r.component_code,
            f.period_end,f.record_id,f.document_id,f.dataset_code,
            f.source_field,f.source_value_text,f.value_numeric,r.sign,
            f.value_numeric*r.sign as signed_value,f.record_hash,
            r.priority,r.auto_promote,r.expected_keywords,r.notes
        from fields f
        cross join run_context c
        join fundamentals.accounting_field_rules r
          on r.model_family=c.model_family
         and r.enabled
         and f.source_field ~* r.source_field_regex
        where f.value_numeric is not null
          and abs(f.value_numeric)<1000000000000000::numeric
    ), inserted as (
        insert into fundamentals.accounting_input_candidates
            (run_id,issuer_id,rule_id,input_key,component_code,period_end,
             source_record_id,source_document_id,dataset_code,source_field,
             source_value_text,value_numeric,sign,signed_value,
             source_record_hash,status,metadata)
        select
            m.run_id,m.issuer_id,m.rule_id,m.input_key,m.component_code,m.period_end,
            m.record_id,m.document_id,m.dataset_code,m.source_field,
            m.source_value_text,m.value_numeric,m.sign,m.signed_value,
            m.record_hash,'candidate',
            jsonb_build_object(
                'rule_priority',m.priority,
                'auto_promote',m.auto_promote,
                'expected_keywords',m.expected_keywords,
                'rule_notes',m.notes,
                'candidate_version','accounting-field-candidate-v2'
            )
        from matched m
        on conflict (run_id,rule_id,period_end,source_record_id,source_field) do update
        set source_value_text=excluded.source_value_text,
            value_numeric=excluded.value_numeric,
            sign=excluded.sign,
            signed_value=excluded.signed_value,
            source_record_hash=excluded.source_record_hash,
            metadata=excluded.metadata
        returning 1
    )
    select count(*)::integer into v_count from inserted;
    return v_count;
end;
$$;

create or replace function audit.match_accounting_candidates_to_official_pages(
    p_run_id uuid,
    p_period_end date,
    p_extraction_document_type text default 'official_annual_report_extraction_v2'
)
returns integer
language plpgsql
security invoker
set search_path=''
as $$
declare
    v_count integer := 0;
begin
    with run_context as (
        select vr.issuer_id
        from model.valuation_runs vr
        where vr.run_id=p_run_id
    ), extraction as (
        select d.*
        from raw.documents d
        join run_context c on c.issuer_id=d.issuer_id
        where d.document_type=p_extraction_document_type
          and length(coalesce(d.content_hash,''))=64
        order by d.retrieved_at desc,d.document_id desc
        limit 1
    ), hits as (
        select
            r.record_id,r.record_hash,r.payload,
            (r.payload->>'page')::integer as page_number,
            r.payload->>'keyword' as keyword
        from raw.records r
        join extraction e on e.document_id=r.document_id
        where r.dataset_code in (
            'cninfo_annual_report_page_hit_v2',
            'cninfo_annual_report_page_hit'
        )
          and jsonb_typeof(r.payload->'candidate_numbers')='array'
    ), numbers as (
        select
            h.*,
            n.number_text,
            audit.parse_report_number(n.number_text) as parsed_number
        from hits h
        cross join lateral jsonb_array_elements_text(h.payload->'candidate_numbers')
            n(number_text)
    ), candidate_keywords as (
        select c.*,unnest(r.expected_keywords) as expected_keyword
        from fundamentals.accounting_input_candidates c
        join fundamentals.accounting_field_rules r on r.rule_id=c.rule_id
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.status in ('candidate','page_matched','validated')
    ), matches as (
        select
            c.candidate_id,e.document_id as extraction_document_id,
            n.record_id as page_hit_record_id,n.page_number,n.keyword,
            n.number_text,n.parsed_number,s.scale,
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
        join numbers n
          on n.keyword=c.expected_keyword
         and n.parsed_number is not null
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
            m.candidate_id,m.extraction_document_id,m.page_hit_record_id,
            m.page_number,m.keyword,m.number_text,m.parsed_number,m.scale,
            m.normalized_value,m.candidate_value,m.absolute_difference,
            m.relative_difference,'candidate',
            jsonb_build_object(
                'page_hit_record_hash',m.page_hit_record_hash,
                'source_record_hash',m.source_record_hash,
                'source_field',m.source_field,
                'dataset_code',m.dataset_code,
                'extraction_hash',m.extraction_hash,
                'official_pdf_hash',m.official_pdf_hash,
                'snippet',m.snippet,
                'matching_version','accounting-candidate-page-match-v2'
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
        returning 1
    ), ranked as (
        select
            m.match_id,
            row_number() over(
                partition by m.candidate_id
                order by m.relative_difference nulls last,m.absolute_difference,
                         m.page_number,m.match_id
            ) as rn
        from audit.accounting_candidate_page_matches m
        join fundamentals.accounting_input_candidates c
          on c.candidate_id=m.candidate_id
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and m.status in ('candidate','validated')
    ), updated_matches as (
        update audit.accounting_candidate_page_matches m
        set status=case when r.rn=1 then 'validated' else 'candidate' end,
            validated_at=case when r.rn=1 then now() else null end
        from ranked r
        where r.match_id=m.match_id
        returning m.candidate_id,m.status
    ), updated_candidates as (
        update fundamentals.accounting_input_candidates c
        set status=case when exists (
                select 1
                from audit.accounting_candidate_page_matches m
                where m.candidate_id=c.candidate_id and m.status='validated'
            ) then 'page_matched' else 'candidate' end,
            validated_at=case when exists (
                select 1
                from audit.accounting_candidate_page_matches m
                where m.candidate_id=c.candidate_id and m.status='validated'
            ) then now() else null end
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.status in ('candidate','page_matched')
        returning c.candidate_id,c.status
    )
    select count(*)::integer into v_count
    from updated_matches
    where status='validated';
    return v_count;
end;
$$;

create or replace function model.promote_shares_outstanding(
    p_run_id uuid,
    p_period_end date,
    p_as_of_at timestamptz
)
returns boolean
language plpgsql
security invoker
set search_path=''
as $$
declare
    v_distinct_values integer := 0;
    v_value numeric;
    v_existing numeric;
    v_best record;
begin
    select count(distinct c.value_numeric),min(c.value_numeric)
    into v_distinct_values,v_value
    from fundamentals.accounting_input_candidates c
    where c.run_id=p_run_id
      and c.input_key='shares_outstanding'
      and c.period_end=p_period_end
      and c.status='page_matched'
      and c.value_numeric between 100000000::numeric and 10000000000::numeric
      and exists (
          select 1
          from audit.accounting_candidate_page_matches m
          where m.candidate_id=c.candidate_id and m.status='validated'
      );

    if v_distinct_values<>1 or v_value is null then
        return false;
    end if;

    select
        c.*,m.match_id,m.page_number,m.keyword,m.source_number_text,m.scale,
        m.relative_difference,m.metadata as match_metadata,r.priority,
        ds.source_code
    into v_best
    from fundamentals.accounting_input_candidates c
    join fundamentals.accounting_field_rules r on r.rule_id=c.rule_id
    join audit.accounting_candidate_page_matches m
      on m.candidate_id=c.candidate_id and m.status='validated'
    join raw.documents d on d.document_id=c.source_document_id
    join raw.data_sources ds on ds.source_id=d.source_id
    where c.run_id=p_run_id
      and c.input_key='shares_outstanding'
      and c.period_end=p_period_end
      and c.status='page_matched'
      and c.value_numeric=v_value
    order by r.priority,m.relative_difference nulls last,m.absolute_difference,
             c.candidate_id,m.match_id
    limit 1;

    select a.value_numeric into v_existing
    from model.run_assumptions a
    where a.run_id=p_run_id
      and a.scenario='control'
      and a.assumption_key='shares_outstanding'
    order by a.assumption_id
    limit 1;

    if v_existing is not null and v_existing<>v_value then
        return false;
    end if;

    insert into model.run_assumptions
        (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
    select
        p_run_id,'control','shares_outstanding',v_value,'shares',
        'official_document_plus_derived_adapter',
        jsonb_build_object(
            'candidate_id',v_best.candidate_id,
            'source_record_id',v_best.source_record_id,
            'source_document_id',v_best.source_document_id,
            'dataset_code',v_best.dataset_code,
            'source_field',v_best.source_field,
            'source_record_hash',v_best.source_record_hash,
            'period_end',v_best.period_end,
            'official_page_match_id',v_best.match_id,
            'official_page',v_best.page_number,
            'official_keyword',v_best.keyword,
            'official_source_number_text',v_best.source_number_text,
            'official_scale',v_best.scale,
            'official_pdf_hash',v_best.match_metadata->>'official_pdf_hash',
            'official_extraction_hash',v_best.match_metadata->>'extraction_hash',
            'timing_role','decision_input',
            'available_at',p_as_of_at,
            'validation','one distinct page-matched share count across all structured candidates',
            'promotion_version','shares-outstanding-auto-promotion-v2'
        )
    where not exists (
        select 1 from model.run_assumptions a
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='shares_outstanding'
    );

    insert into audit.evidence_assertions
        (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
         source_codes,content_hashes,unresolved_conflict,details,asserted_by)
    select
        'shares_outstanding','valuation_run_input',
        p_run_id::text||'|shares_outstanding',p_as_of_at,3,'active',
        array_remove(array['CNINFO',v_best.source_code],null),
        array_remove(array[
            v_best.match_metadata->>'official_pdf_hash',
            v_best.match_metadata->>'extraction_hash',
            v_best.match_metadata->>'page_hit_record_hash',
            v_best.source_record_hash
        ],null),
        false,
        jsonb_build_object(
            'value',v_value,'unit','shares',
            'candidate_id',v_best.candidate_id,
            'source_record_id',v_best.source_record_id,
            'source_field',v_best.source_field,
            'dataset_code',v_best.dataset_code,
            'page',v_best.page_number,
            'keyword',v_best.keyword,
            'source_number_text',v_best.source_number_text,
            'scale',v_best.scale,
            'quality_reason','one distinct structured candidate exactly reconciled to a hashed official PDF page'
        ),
        'shares-outstanding-auto-promotion-v2'
    where not exists (
        select 1 from audit.evidence_assertions e
        where e.assertion_code='shares_outstanding'
          and e.subject_type='valuation_run_input'
          and e.subject_id=p_run_id::text||'|shares_outstanding'
          and e.evidence_grade=3
          and e.status='active'
    );

    return exists (
        select 1
        from model.run_assumptions a
        join audit.evidence_assertions e
          on e.assertion_code='shares_outstanding'
         and e.subject_type='valuation_run_input'
         and e.subject_id=a.run_id::text||'|shares_outstanding'
         and e.status='active'
         and e.evidence_grade=3
         and cardinality(e.content_hashes)>0
         and not e.unresolved_conflict
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='shares_outstanding'
          and a.value_numeric=v_value
    );
end;
$$;

revoke all on function fundamentals.refresh_accounting_input_candidates(uuid,date)
    from public,anon,authenticated;
revoke all on function audit.match_accounting_candidates_to_official_pages(uuid,date,text)
    from public,anon,authenticated;
revoke all on function model.promote_shares_outstanding(uuid,date,timestamptz)
    from public,anon,authenticated;
grant execute on function fundamentals.refresh_accounting_input_candidates(uuid,date)
    to service_role;
grant execute on function audit.match_accounting_candidates_to_official_pages(uuid,date,text)
    to service_role;
grant execute on function model.promote_shares_outstanding(uuid,date,timestamptz)
    to service_role;

commit;
