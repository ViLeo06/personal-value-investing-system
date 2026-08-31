begin;

with fact_evidence as (
    select
        f.metric_code as assertion_code,
        'issuer_period_fact'::text as subject_type,
        concat_ws('|','KWEICHOW_MOUTAI',f.period_end::text,f.metric_code) as subject_id,
        '2021-03-31T16:00:00Z'::timestamptz as as_of_at,
        case
            when s.source_type in ('official_disclosure','official_exchange')
                 and d.content_hash is not null then 3
            when s.source_type in ('official_disclosure','official_exchange') then 2
            when s.source_id is not null then 1
            else 0
        end::smallint as evidence_grade,
        array_remove(array[s.source_code],null)::text[] as source_codes,
        array_remove(array[d.content_hash,f.record_hash],null)::text[] as content_hashes,
        jsonb_build_object(
            'fact_id',f.fact_id,
            'source_document_id',f.source_document_id,
            'source_type',s.source_type,
            'published_at',f.published_at,
            'available_at',f.available_at,
            'revision_no',f.revision_no
        ) as details
    from pit.financial_facts f
    join master.issuers i on i.issuer_id=f.issuer_id
    left join raw.documents d on d.document_id=f.source_document_id
    left join raw.data_sources s on s.source_id=d.source_id
    where i.issuer_code='KWEICHOW_MOUTAI'
      and f.period_end='2020-12-31'::date
      and f.metric_code in (
          'revenue','net_income_parent','operating_cash_flow',
          'total_assets','equity_parent','basic_eps'
      )
      and f.available_at <= '2021-03-31T16:00:00Z'::timestamptz
)
insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    f.assertion_code,f.subject_type,f.subject_id,f.as_of_at,f.evidence_grade,
    'active',f.source_codes,f.content_hashes,false,f.details,'gate0-evidence-grader-v1'
from fact_evidence f
where not exists (
    select 1 from audit.evidence_assertions e
    where e.assertion_code=f.assertion_code
      and e.subject_type=f.subject_type
      and e.subject_id=f.subject_id
      and e.as_of_at=f.as_of_at
      and e.status='active'
);

with market_evidence as (
    select
        a.assumption_key as assertion_code,
        'valuation_run_input'::text as subject_type,
        concat_ws('|',a.run_id::text,a.assumption_key) as subject_id,
        vr.as_of_at,
        1::smallint as evidence_grade,
        array[a.provenance->>'source_code']::text[] as source_codes,
        array[a.provenance->>'record_hash']::text[] as content_hashes,
        a.provenance || jsonb_build_object(
            'quality_reason','single derived source pending independent reconciliation'
        ) as details
    from model.run_assumptions a
    join model.valuation_runs vr on vr.run_id=a.run_id
    where a.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and a.scenario='control'
      and a.assumption_key in ('reference_close_price','execution_open_price')
)
insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    m.assertion_code,m.subject_type,m.subject_id,m.as_of_at,m.evidence_grade,
    'active',m.source_codes,m.content_hashes,false,m.details,'gate0-evidence-grader-v1'
from market_evidence m
where not exists (
    select 1 from audit.evidence_assertions e
    where e.assertion_code=m.assertion_code
      and e.subject_type=m.subject_type
      and e.subject_id=m.subject_id
      and e.as_of_at=m.as_of_at
      and e.status='active'
);

commit;
