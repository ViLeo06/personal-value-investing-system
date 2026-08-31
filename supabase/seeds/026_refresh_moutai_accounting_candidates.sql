begin;

create temporary table _accounting_refresh_results on commit drop as
select
    fundamentals.refresh_accounting_input_candidates(
        '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
        '2019-12-31'::date
    ) as refreshed_2019,
    fundamentals.refresh_accounting_input_candidates(
        '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
        '2020-12-31'::date
    ) as refreshed_2020;

create temporary table _accounting_match_results on commit drop as
select
    audit.match_accounting_candidates_to_official_pages(
        '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
        '2019-12-31'::date,
        'official_annual_report_extraction_v2'
    ) as matched_2019,
    audit.match_accounting_candidates_to_official_pages(
        '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
        '2020-12-31'::date,
        'official_annual_report_extraction_v2'
    ) as matched_2020;

create temporary table _share_promotion on commit drop as
select model.promote_shares_outstanding(
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
    '2020-12-31'::date,
    '2021-03-31T16:00:00Z'::timestamptz
) as promoted;

with grouped as (
    select
        input_key,
        period_end,
        count(*)::integer as candidate_count,
        count(*) filter(where status='page_matched')::integer as page_matched_count,
        array_agg(distinct component_code order by component_code) as components,
        array_agg(distinct source_field order by source_field) as source_fields
    from fundamentals.accounting_input_candidates
    where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and period_end in ('2019-12-31'::date,'2020-12-31'::date)
    group by input_key,period_end
), summary as (
    select
        coalesce(sum(candidate_count),0)::integer as candidate_count,
        coalesce(sum(page_matched_count),0)::integer as page_matched_count,
        count(*)::integer as input_period_count,
        coalesce(jsonb_agg(
            jsonb_build_object(
                'input_key',input_key,
                'period_end',period_end,
                'candidate_count',candidate_count,
                'page_matched_count',page_matched_count,
                'components',components,
                'source_fields',source_fields
            ) order by input_key,period_end
        ),'[]'::jsonb) as breakdown
    from grouped
), execution as (
    select
        r.refreshed_2019,r.refreshed_2020,
        m.matched_2019,m.matched_2020,
        p.promoted
    from _accounting_refresh_results r
    cross join _accounting_match_results m
    cross join _share_promotion p
)
update audit.data_quality_issues q
set severity='info',
    status='open',
    detected_at=now(),
    description='Structured accounting candidates are inventoried and page-matched where possible; non-share inputs remain policy-gated.',
    details=jsonb_build_object(
        'refreshed_2019',e.refreshed_2019,
        'refreshed_2020',e.refreshed_2020,
        'validated_page_matches_2019',e.matched_2019,
        'validated_page_matches_2020',e.matched_2020,
        'shares_promoted',e.promoted,
        'candidate_count',s.candidate_count,
        'page_matched_count',s.page_matched_count,
        'input_period_count',s.input_period_count,
        'breakdown',s.breakdown,
        'automatic_promotion_scope','shares_outstanding only',
        'refresh_version','accounting-candidate-functions-v3'
    )
from summary s
cross join execution e
where q.rule_code='ACCOUNTING_INPUT_CANDIDATE_REVIEW_REQUIRED'
  and q.record_key='KWEICHOW_MOUTAI|2021-04-01|OWNER_EARNINGS';

with grouped as (
    select
        input_key,period_end,
        count(*)::integer as candidate_count,
        count(*) filter(where status='page_matched')::integer as page_matched_count,
        array_agg(distinct component_code order by component_code) as components,
        array_agg(distinct source_field order by source_field) as source_fields
    from fundamentals.accounting_input_candidates
    where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and period_end in ('2019-12-31'::date,'2020-12-31'::date)
    group by input_key,period_end
), summary as (
    select
        coalesce(sum(candidate_count),0)::integer as candidate_count,
        coalesce(sum(page_matched_count),0)::integer as page_matched_count,
        count(*)::integer as input_period_count,
        coalesce(jsonb_agg(
            jsonb_build_object(
                'input_key',input_key,
                'period_end',period_end,
                'candidate_count',candidate_count,
                'page_matched_count',page_matched_count,
                'components',components,
                'source_fields',source_fields
            ) order by input_key,period_end
        ),'[]'::jsonb) as breakdown
    from grouped
), execution as (
    select r.refreshed_2019,r.refreshed_2020,m.matched_2019,m.matched_2020,p.promoted
    from _accounting_refresh_results r
    cross join _accounting_match_results m
    cross join _share_promotion p
)
insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'info','accounting_input_review','fundamentals.accounting_input_candidates',
    'KWEICHOW_MOUTAI|2021-04-01|OWNER_EARNINGS',
    'ACCOUNTING_INPUT_CANDIDATE_REVIEW_REQUIRED',
    'Structured accounting candidates are inventoried and page-matched where possible; non-share inputs remain policy-gated.',
    'open',
    jsonb_build_object(
        'refreshed_2019',e.refreshed_2019,
        'refreshed_2020',e.refreshed_2020,
        'validated_page_matches_2019',e.matched_2019,
        'validated_page_matches_2020',e.matched_2020,
        'shares_promoted',e.promoted,
        'candidate_count',s.candidate_count,
        'page_matched_count',s.page_matched_count,
        'input_period_count',s.input_period_count,
        'breakdown',s.breakdown,
        'automatic_promotion_scope','shares_outstanding only',
        'refresh_version','accounting-candidate-functions-v3'
    )
from summary s
cross join execution e
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='ACCOUNTING_INPUT_CANDIDATE_REVIEW_REQUIRED'
      and q.record_key='KWEICHOW_MOUTAI|2021-04-01|OWNER_EARNINGS'
      and q.status='open'
);

with share_state as (
    select
        count(*) filter(where a.value_numeric is not null)::integer as assumption_count,
        count(*) filter(
            where e.evidence_grade>=3
              and e.status='active'
              and cardinality(e.content_hashes)>0
              and not e.unresolved_conflict
        )::integer as evidence_count,
        max(a.value_numeric) as value_numeric
    from model.run_assumptions a
    left join audit.evidence_assertions e
      on e.assertion_code='shares_outstanding'
     and e.subject_type='valuation_run_input'
     and e.subject_id=a.run_id::text||'|shares_outstanding'
    where a.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and a.scenario='control'
      and a.assumption_key='shares_outstanding'
)
update audit.data_quality_issues q
set severity=case when s.assumption_count=1 and s.evidence_count>=1
                  then 'info' else 'critical' end,
    status=case when s.assumption_count=1 and s.evidence_count>=1
                then 'resolved' else 'open' end,
    resolved_at=case when s.assumption_count=1 and s.evidence_count>=1
                     then now() else null end,
    detected_at=now(),
    description=case when s.assumption_count=1 and s.evidence_count>=1
        then 'Point-in-time shares outstanding were released from one unambiguous official-page-matched value.'
        else 'Point-in-time shares outstanding remain blocked because one official-page-matched value was not established.' end,
    details=jsonb_build_object(
        'assumption_count',s.assumption_count,
        'qualifying_evidence_count',s.evidence_count,
        'value_numeric',s.value_numeric,
        'promotion_version','shares-outstanding-auto-promotion-v2'
    )
from share_state s
where q.rule_code='SHARES_OUTSTANDING_UNAMBIGUOUS_REQUIRED'
  and q.record_key='8bcbb9d3-7fdb-529a-9f9a-547043040e13|shares_outstanding';

with share_state as (
    select
        count(*) filter(where a.value_numeric is not null)::integer as assumption_count,
        count(*) filter(
            where e.evidence_grade>=3
              and e.status='active'
              and cardinality(e.content_hashes)>0
              and not e.unresolved_conflict
        )::integer as evidence_count,
        max(a.value_numeric) as value_numeric
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
    case when s.assumption_count=1 and s.evidence_count>=1 then 'info' else 'critical' end,
    'formal_input','model.run_assumptions',
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13|shares_outstanding',
    'SHARES_OUTSTANDING_UNAMBIGUOUS_REQUIRED',
    case when s.assumption_count=1 and s.evidence_count>=1
        then 'Point-in-time shares outstanding were released from one unambiguous official-page-matched value.'
        else 'Point-in-time shares outstanding remain blocked because one official-page-matched value was not established.' end,
    case when s.assumption_count=1 and s.evidence_count>=1 then 'resolved' else 'open' end,
    jsonb_build_object(
        'assumption_count',s.assumption_count,
        'qualifying_evidence_count',s.evidence_count,
        'value_numeric',s.value_numeric,
        'promotion_version','shares-outstanding-auto-promotion-v2'
    ),
    case when s.assumption_count=1 and s.evidence_count>=1 then now() else null end
from share_state s
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='SHARES_OUTSTANDING_UNAMBIGUOUS_REQUIRED'
      and q.record_key='8bcbb9d3-7fdb-529a-9f9a-547043040e13|shares_outstanding'
  );

commit;
