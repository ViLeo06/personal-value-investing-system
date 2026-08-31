begin;

insert into fundamentals.accounting_field_rules
    (model_family,input_key,component_code,source_field_regex,
     expected_keywords,sign,aggregation_group,priority,auto_promote,notes)
values
    ('owner_earnings_dcf','change_working_capital','inventory_cash_effect',
     '(DECR.*INVENT|INVENT.*DECR|DECREASE.*INVENTOR)',
     array['存货的减少'], -1, 'change_working_capital', 10, true,
     'Cash-flow supplement line. The model input is cash use, so the reported cash-flow effect is sign-inverted.'),
    ('owner_earnings_dcf','change_working_capital','operating_receivable_cash_effect',
     '(DECR.*OPERAT.*RECEIV|OPERAT.*RECEIV.*DECR|DECREASE.*OPERAT.*RECEIV)',
     array['经营性应收项目的减少'], -1, 'change_working_capital', 20, true,
     'Cash-flow supplement line. The model input is cash use, so the reported cash-flow effect is sign-inverted.'),
    ('owner_earnings_dcf','change_working_capital','operating_payable_cash_effect',
     '(INCR.*OPERAT.*PAYABLE|OPERAT.*PAYABLE.*INCR|INCREASE.*OPERAT.*PAYABLE)',
     array['经营性应付项目的增加'], -1, 'change_working_capital', 30, true,
     'Cash-flow supplement line. The model input is cash use, so the reported cash-flow effect is sign-inverted.')
on conflict (model_family,input_key,component_code,source_field_regex) do update
set expected_keywords=excluded.expected_keywords,
    sign=excluded.sign,
    aggregation_group=excluded.aggregation_group,
    priority=excluded.priority,
    auto_promote=excluded.auto_promote,
    notes=excluded.notes,
    enabled=true;

create or replace function model.promote_depreciation_amortization(
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
    v_total_count integer := 0;
    v_total_value numeric;
    v_component_ready integer := 0;
    v_component_value numeric;
    v_value numeric;
    v_method text;
    v_existing numeric;
    v_details jsonb := '[]'::jsonb;
    v_hashes text[] := '{}'::text[];
begin
    select count(distinct c.value_numeric), min(c.value_numeric)
    into v_total_count,v_total_value
    from fundamentals.accounting_input_candidates c
    where c.run_id=p_run_id
      and c.period_end=p_period_end
      and c.component_code='d_and_a_total'
      and c.status='page_matched'
      and c.value_numeric>=0
      and exists (
          select 1 from audit.accounting_candidate_page_matches m
          where m.candidate_id=c.candidate_id and m.status='validated'
      );

    with per_component as (
        select
            c.component_code,
            count(distinct c.value_numeric) as distinct_values,
            min(c.value_numeric) as component_value
        from fundamentals.accounting_input_candidates c
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.component_code in (
              'fixed_asset_depreciation',
              'intangible_amortization',
              'deferred_expense_amortization'
          )
          and c.status='page_matched'
          and c.value_numeric>=0
          and exists (
              select 1 from audit.accounting_candidate_page_matches m
              where m.candidate_id=c.candidate_id and m.status='validated'
          )
        group by c.component_code
    )
    select
        count(*) filter(where distinct_values=1)::integer,
        sum(component_value) filter(where distinct_values=1)
    into v_component_ready,v_component_value
    from per_component;

    if v_total_count=1 then
        if v_component_ready=3
           and abs(v_total_value-v_component_value)>greatest(
               1::numeric,abs(v_total_value)*0.000001::numeric
           ) then
            return false;
        end if;
        v_value:=v_total_value;
        v_method:='official_page_matched_total';
    elsif v_total_count=0 and v_component_ready=3 then
        v_value:=v_component_value;
        v_method:='official_page_matched_component_sum';
    else
        return false;
    end if;

    select a.value_numeric into v_existing
    from model.run_assumptions a
    where a.run_id=p_run_id
      and a.scenario='control'
      and a.assumption_key='depreciation_amortization'
    order by a.assumption_id
    limit 1;
    if v_existing is not null
       and abs(v_existing-v_value)>greatest(1::numeric,abs(v_value)*0.000001::numeric) then
        return false;
    end if;

    with selected as (
        select c.*,m.match_id,m.page_number,m.keyword,m.source_number_text,
               m.scale,m.metadata as match_metadata
        from fundamentals.accounting_input_candidates c
        join audit.accounting_candidate_page_matches m
          on m.candidate_id=c.candidate_id and m.status='validated'
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.status='page_matched'
          and (
              (v_method='official_page_matched_total'
               and c.component_code='d_and_a_total'
               and c.value_numeric=v_value)
              or
              (v_method='official_page_matched_component_sum'
               and c.component_code in (
                   'fixed_asset_depreciation',
                   'intangible_amortization',
                   'deferred_expense_amortization'
               ))
          )
    )
    select
        coalesce(jsonb_agg(jsonb_build_object(
            'candidate_id',candidate_id,
            'component_code',component_code,
            'value_numeric',value_numeric,
            'source_record_id',source_record_id,
            'source_document_id',source_document_id,
            'dataset_code',dataset_code,
            'source_field',source_field,
            'page_match_id',match_id,
            'page',page_number,
            'keyword',keyword,
            'source_number_text',source_number_text,
            'scale',scale
        ) order by component_code,candidate_id),'[]'::jsonb),
        coalesce(array_agg(distinct h) filter(where h is not null),'{}'::text[])
    into v_details,v_hashes
    from selected s
    cross join lateral unnest(array[
        s.source_record_hash,
        s.match_metadata->>'official_pdf_hash',
        s.match_metadata->>'extraction_hash',
        s.match_metadata->>'page_hit_record_hash'
    ]::text[]) hashes(h);

    insert into model.run_assumptions
        (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
    select
        p_run_id,'control','depreciation_amortization',v_value,'CNY',
        'official_document_plus_derived_adapter',
        jsonb_build_object(
            'period_end',p_period_end,
            'available_at',p_as_of_at,
            'method',v_method,
            'components',v_details,
            'promotion_version','owner-earnings-proven-inputs-v1'
        )
    where not exists (
        select 1 from model.run_assumptions a
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='depreciation_amortization'
    );

    insert into audit.evidence_assertions
        (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
         source_codes,content_hashes,unresolved_conflict,details,asserted_by)
    select
        'depreciation_amortization','valuation_run_input',
        p_run_id::text||'|depreciation_amortization',p_as_of_at,3,'active',
        array['CNINFO','AKSHARE_EASTMONEY_FINANCIAL'],v_hashes,false,
        jsonb_build_object(
            'value',v_value,'unit','CNY','period_end',p_period_end,
            'method',v_method,'components',v_details,
            'quality_reason','one official-page-matched total or a complete reconciled component sum'
        ),
        'owner-earnings-proven-inputs-v1'
    where cardinality(v_hashes)>0
      and not exists (
          select 1 from audit.evidence_assertions e
          where e.assertion_code='depreciation_amortization'
            and e.subject_type='valuation_run_input'
            and e.subject_id=p_run_id::text||'|depreciation_amortization'
            and e.evidence_grade=3
            and e.status='active'
      );

    return exists (
        select 1
        from model.run_assumptions a
        join audit.evidence_assertions e
          on e.assertion_code='depreciation_amortization'
         and e.subject_type='valuation_run_input'
         and e.subject_id=a.run_id::text||'|depreciation_amortization'
         and e.evidence_grade=3 and e.status='active'
         and cardinality(e.content_hashes)>0 and not e.unresolved_conflict
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='depreciation_amortization'
          and abs(a.value_numeric-v_value)<=greatest(1::numeric,abs(v_value)*0.000001::numeric)
    );
end;
$$;

create or replace function model.promote_change_working_capital(
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
    v_ready integer := 0;
    v_value numeric;
    v_existing numeric;
    v_details jsonb := '[]'::jsonb;
    v_hashes text[] := '{}'::text[];
begin
    with per_component as (
        select
            c.component_code,
            count(distinct c.signed_value) as distinct_values,
            min(c.signed_value) as component_value
        from fundamentals.accounting_input_candidates c
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.component_code in (
              'inventory_cash_effect',
              'operating_receivable_cash_effect',
              'operating_payable_cash_effect'
          )
          and c.status='page_matched'
          and exists (
              select 1 from audit.accounting_candidate_page_matches m
              where m.candidate_id=c.candidate_id and m.status='validated'
          )
        group by c.component_code
    )
    select
        count(*) filter(where distinct_values=1)::integer,
        sum(component_value) filter(where distinct_values=1)
    into v_ready,v_value
    from per_component;

    if v_ready<>3 or v_value is null then
        return false;
    end if;

    select a.value_numeric into v_existing
    from model.run_assumptions a
    where a.run_id=p_run_id
      and a.scenario='control'
      and a.assumption_key='change_working_capital'
    order by a.assumption_id
    limit 1;
    if v_existing is not null
       and abs(v_existing-v_value)>greatest(1::numeric,abs(v_value)*0.000001::numeric) then
        return false;
    end if;

    with selected as (
        select c.*,m.match_id,m.page_number,m.keyword,m.source_number_text,
               m.scale,m.metadata as match_metadata
        from fundamentals.accounting_input_candidates c
        join audit.accounting_candidate_page_matches m
          on m.candidate_id=c.candidate_id and m.status='validated'
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.status='page_matched'
          and c.component_code in (
              'inventory_cash_effect',
              'operating_receivable_cash_effect',
              'operating_payable_cash_effect'
          )
    )
    select
        coalesce(jsonb_agg(jsonb_build_object(
            'candidate_id',candidate_id,
            'component_code',component_code,
            'reported_value',value_numeric,
            'sign',sign,
            'cash_use_value',signed_value,
            'source_record_id',source_record_id,
            'source_document_id',source_document_id,
            'dataset_code',dataset_code,
            'source_field',source_field,
            'page_match_id',match_id,
            'page',page_number,
            'keyword',keyword,
            'source_number_text',source_number_text,
            'scale',scale
        ) order by component_code,candidate_id),'[]'::jsonb),
        coalesce(array_agg(distinct h) filter(where h is not null),'{}'::text[])
    into v_details,v_hashes
    from selected s
    cross join lateral unnest(array[
        s.source_record_hash,
        s.match_metadata->>'official_pdf_hash',
        s.match_metadata->>'extraction_hash',
        s.match_metadata->>'page_hit_record_hash'
    ]::text[]) hashes(h);

    insert into model.run_assumptions
        (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
    select
        p_run_id,'control','change_working_capital',v_value,'CNY',
        'official_document_plus_derived_adapter',
        jsonb_build_object(
            'period_end',p_period_end,'available_at',p_as_of_at,
            'method','cash_flow_supplement_three_component_cash_use',
            'components',v_details,
            'sign_convention','positive means cash invested in operating working capital',
            'promotion_version','owner-earnings-proven-inputs-v1'
        )
    where not exists (
        select 1 from model.run_assumptions a
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='change_working_capital'
    );

    insert into audit.evidence_assertions
        (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
         source_codes,content_hashes,unresolved_conflict,details,asserted_by)
    select
        'change_working_capital','valuation_run_input',
        p_run_id::text||'|change_working_capital',p_as_of_at,3,'active',
        array['CNINFO','AKSHARE_EASTMONEY_FINANCIAL'],v_hashes,false,
        jsonb_build_object(
            'value',v_value,'unit','CNY','period_end',p_period_end,
            'method','cash_flow_supplement_three_component_cash_use',
            'components',v_details,
            'quality_reason','three required cash-flow supplement components each have one official-page-matched value'
        ),
        'owner-earnings-proven-inputs-v1'
    where cardinality(v_hashes)>0
      and not exists (
          select 1 from audit.evidence_assertions e
          where e.assertion_code='change_working_capital'
            and e.subject_type='valuation_run_input'
            and e.subject_id=p_run_id::text||'|change_working_capital'
            and e.evidence_grade=3
            and e.status='active'
      );

    return exists (
        select 1
        from model.run_assumptions a
        join audit.evidence_assertions e
          on e.assertion_code='change_working_capital'
         and e.subject_type='valuation_run_input'
         and e.subject_id=a.run_id::text||'|change_working_capital'
         and e.evidence_grade=3 and e.status='active'
         and cardinality(e.content_hashes)>0 and not e.unresolved_conflict
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='change_working_capital'
          and abs(a.value_numeric-v_value)<=greatest(1::numeric,abs(v_value)*0.000001::numeric)
    );
end;
$$;

create or replace function model.promote_total_capex_upper_bound(
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
    v_count integer := 0;
    v_value numeric;
    v_existing numeric;
    v_details jsonb := '[]'::jsonb;
    v_hashes text[] := '{}'::text[];
begin
    select count(distinct c.value_numeric),min(c.value_numeric)
    into v_count,v_value
    from fundamentals.accounting_input_candidates c
    where c.run_id=p_run_id
      and c.period_end=p_period_end
      and c.input_key='maintenance_capex_upper_bound'
      and c.status='page_matched'
      and c.value_numeric>=0
      and exists (
          select 1 from audit.accounting_candidate_page_matches m
          where m.candidate_id=c.candidate_id and m.status='validated'
      );
    if v_count<>1 or v_value is null then
        return false;
    end if;

    select a.value_numeric into v_existing
    from model.run_assumptions a
    where a.run_id=p_run_id
      and a.scenario='control'
      and a.assumption_key='total_capex_upper_bound'
    order by a.assumption_id
    limit 1;
    if v_existing is not null
       and abs(v_existing-v_value)>greatest(1::numeric,abs(v_value)*0.000001::numeric) then
        return false;
    end if;

    with selected as (
        select c.*,m.match_id,m.page_number,m.keyword,m.source_number_text,
               m.scale,m.metadata as match_metadata
        from fundamentals.accounting_input_candidates c
        join audit.accounting_candidate_page_matches m
          on m.candidate_id=c.candidate_id and m.status='validated'
        where c.run_id=p_run_id
          and c.period_end=p_period_end
          and c.input_key='maintenance_capex_upper_bound'
          and c.status='page_matched'
          and c.value_numeric=v_value
    )
    select
        coalesce(jsonb_agg(jsonb_build_object(
            'candidate_id',candidate_id,'value_numeric',value_numeric,
            'source_record_id',source_record_id,'source_document_id',source_document_id,
            'dataset_code',dataset_code,'source_field',source_field,
            'page_match_id',match_id,'page',page_number,'keyword',keyword,
            'source_number_text',source_number_text,'scale',scale
        ) order by candidate_id),'[]'::jsonb),
        coalesce(array_agg(distinct h) filter(where h is not null),'{}'::text[])
    into v_details,v_hashes
    from selected s
    cross join lateral unnest(array[
        s.source_record_hash,
        s.match_metadata->>'official_pdf_hash',
        s.match_metadata->>'extraction_hash',
        s.match_metadata->>'page_hit_record_hash'
    ]::text[]) hashes(h);

    insert into model.run_assumptions
        (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
    select
        p_run_id,'control','total_capex_upper_bound',v_value,'CNY',
        'official_document_plus_derived_adapter',
        jsonb_build_object(
            'period_end',p_period_end,'available_at',p_as_of_at,
            'method','total_qualifying_long_asset_cash_spend',
            'components',v_details,
            'formal_maintenance_capex_input',false,
            'policy_warning','This is only an upper bound and must not fill maintenance_capex.',
            'promotion_version','owner-earnings-proven-inputs-v1'
        )
    where not exists (
        select 1 from model.run_assumptions a
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='total_capex_upper_bound'
    );

    insert into audit.evidence_assertions
        (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
         source_codes,content_hashes,unresolved_conflict,details,asserted_by)
    select
        'total_capex_upper_bound','valuation_run_diagnostic',
        p_run_id::text||'|total_capex_upper_bound',p_as_of_at,3,'active',
        array['CNINFO','AKSHARE_EASTMONEY_FINANCIAL'],v_hashes,false,
        jsonb_build_object(
            'value',v_value,'unit','CNY','period_end',p_period_end,
            'components',v_details,'formal_maintenance_capex_input',false,
            'quality_reason','one official-page-matched total qualifying long-asset cash-spend value'
        ),
        'owner-earnings-proven-inputs-v1'
    where cardinality(v_hashes)>0
      and not exists (
          select 1 from audit.evidence_assertions e
          where e.assertion_code='total_capex_upper_bound'
            and e.subject_type='valuation_run_diagnostic'
            and e.subject_id=p_run_id::text||'|total_capex_upper_bound'
            and e.evidence_grade=3 and e.status='active'
      );

    return exists (
        select 1 from model.run_assumptions a
        where a.run_id=p_run_id
          and a.scenario='control'
          and a.assumption_key='total_capex_upper_bound'
          and abs(a.value_numeric-v_value)<=greatest(1::numeric,abs(v_value)*0.000001::numeric)
    );
end;
$$;

revoke all on function model.promote_depreciation_amortization(uuid,date,timestamptz)
    from public,anon,authenticated;
revoke all on function model.promote_change_working_capital(uuid,date,timestamptz)
    from public,anon,authenticated;
revoke all on function model.promote_total_capex_upper_bound(uuid,date,timestamptz)
    from public,anon,authenticated;
grant execute on function model.promote_depreciation_amortization(uuid,date,timestamptz)
    to service_role;
grant execute on function model.promote_change_working_capital(uuid,date,timestamptz)
    to service_role;
grant execute on function model.promote_total_capex_upper_bound(uuid,date,timestamptz)
    to service_role;

commit;
