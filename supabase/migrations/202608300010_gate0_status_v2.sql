begin;

create or replace function audit.gate0_status()
returns table(
    check_code text,
    passed boolean,
    severity text,
    details jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
    with master_counts as (
        select
            (select count(*) from master.issuers
             where issuer_code in ('KWEICHOW_MOUTAI','TENCENT','BYD','CMB')) as issuers,
            (select count(*) from master.securities s
             join master.issuers i on i.issuer_id=s.issuer_id
             where i.issuer_code in ('KWEICHOW_MOUTAI','TENCENT','BYD','CMB')) as securities
    ), snapshot as (
        select snapshot_id,snapshot_hash,
               coalesce((manifest->>'fact_count')::int,0) as fact_count
        from audit.data_snapshots
        where cutoff_policy_version='pit_cutoff_v3_content_hash'
          and as_of_at='2021-03-31T16:00:00Z'::timestamptz
        order by created_at desc
        limit 1
    ), function_leaks as (
        select count(*) as leak_count
        from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
        where (n.nspname,p.proname) in (
            ('pit','financial_facts_as_of'),
            ('pit','market_bars_as_of'),
            ('pit','corporate_actions_as_of'),
            ('audit','financial_snapshot_manifest'),
            ('audit','gate0_status'),
            ('audit','gate0_overall'),
            ('audit','capture_gate0_status')
        )
          and (
              has_function_privilege('anon',p.oid,'execute')
              or has_function_privilege('authenticated',p.oid,'execute')
          )
    ), formal_run as (
        select status,input_hash,snapshot_id
        from model.valuation_runs
        where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
    ), proxy_run as (
        select vr.status,vr.input_hash,vr.output_hash,count(vo.output_id) as outputs
        from model.valuation_runs vr
        left join model.valuation_outputs vo on vo.run_id=vr.run_id
        where vr.run_id='40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
        group by vr.status,vr.input_hash,vr.output_hash
    ), proxy_backtest as (
        select
            b.status,b.result_hash,
            (select count(*) from backtest.daily_performance d
             where d.backtest_run_id=b.backtest_run_id) as daily_rows,
            (select count(*) from backtest.transactions t
             where t.backtest_run_id=b.backtest_run_id) as transaction_rows,
            (select count(*) from backtest.performance_metrics m
             where m.backtest_run_id=b.backtest_run_id) as metric_rows,
            (select count(*) from backtest.attribution_results a
             where a.backtest_run_id=b.backtest_run_id) as attribution_rows
        from backtest.backtest_runs b
        where b.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    ), price_inputs as (
        select count(*) as input_count
        from model.run_assumptions
        where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
          and scenario='control'
          and assumption_key in ('reference_close_price','execution_open_price')
          and value_numeric is not null
    ), formal_gap as (
        select
            coalesce(jsonb_array_length(details->'missing'),0) as missing_count,
            details->'missing' as missing
        from audit.data_quality_issues
        where record_key='KWEICHOW_MOUTAI|2021-04-01'
          and rule_code='GATE0_REQUIRED_INPUT_MISSING'
          and status='open'
        order by detected_at desc
        limit 1
    ), market_reconciliation as (
        select count(*) as open_count
        from audit.data_quality_issues
        where rule_code='MARKET_PRICE_SECOND_SOURCE_REQUIRED'
          and record_key='600519.SH|2021-03-31|2021-04-01'
          and status='open'
    ), corporate_actions as (
        select
            count(*) as action_count,
            count(*) filter(
                where coalesce((ca.metadata->>'evidence_grade')::int,0)>=2
            ) as formal_grade_count
        from pit.corporate_actions ca
        join master.securities s on s.security_id=ca.security_id
        where s.security_code='600519.SH'
          and ca.action_type='cash_dividend'
          and ca.ex_date between '2021-04-01'::date and '2026-04-01'::date
    ), evidence as (
        select
            count(*) filter(where evidence_grade>=2 and unresolved_conflict=false) as formal_grade_count,
            count(*) as total_count
        from audit.evidence_assertions
        where status='active'
          and (
              as_of_at='2021-03-31T16:00:00Z'::timestamptz
              or subject_type='corporate_action'
              or assertion_code='annual_report_publication'
          )
    ), official_pdf as (
        select
            count(*) filter(where content_hash is not null and length(content_hash)=64) as hashed_pdf_count,
            count(*) as catalog_count
        from raw.documents d
        join raw.data_sources s on s.source_id=d.source_id
        join master.issuers i on i.issuer_id=d.issuer_id
        where s.source_code='CNINFO'
          and i.issuer_code='KWEICHOW_MOUTAI'
          and d.document_type in (
              'official_annual_report_catalog_record',
              'official_annual_report_pdf'
          )
          and d.title like '%2020%年度报告%'
    )
    select 'MASTER_DATA_FOUR_COMPANIES',
           m.issuers=4 and m.securities>=6,
           'critical',
           jsonb_build_object('issuers',m.issuers,'securities',m.securities)
    from master_counts m

    union all
    select 'MOUTAI_REPRODUCIBLE_SNAPSHOT',
           s.snapshot_id is not null and s.fact_count>=6 and length(s.snapshot_hash)=64,
           'critical',
           jsonb_build_object(
               'snapshot_id',s.snapshot_id,
               'snapshot_hash',s.snapshot_hash,
               'fact_count',s.fact_count
           )
    from snapshot s

    union all
    select 'PRIVATE_PIT_FUNCTIONS',
           f.leak_count=0,
           'critical',
           jsonb_build_object('anon_or_authenticated_execute_leaks',f.leak_count)
    from function_leaks f

    union all
    select 'FORMAL_RUN_FAILS_CLOSED',
           r.status='blocked_data',
           'critical',
           jsonb_build_object('status',r.status,'input_hash',r.input_hash)
    from formal_run r

    union all
    select 'PROXY_VALUATION_END_TO_END',
           r.status='completed_proxy' and r.outputs>=18
               and length(r.input_hash)=64 and length(r.output_hash)=64,
           'warning',
           jsonb_build_object(
               'status',r.status,'outputs',r.outputs,
               'input_hash',r.input_hash,'output_hash',r.output_hash
           )
    from proxy_run r

    union all
    select 'PROXY_BACKTEST_END_TO_END',
           r.status='completed_proxy'
               and r.daily_rows>=500
               and r.transaction_rows=2
               and r.metric_rows>=9
               and r.attribution_rows>=4
               and length(r.result_hash)=64,
           'warning',
           jsonb_build_object(
               'status',r.status,
               'daily_rows',r.daily_rows,
               'transaction_rows',r.transaction_rows,
               'metric_rows',r.metric_rows,
               'attribution_rows',r.attribution_rows,
               'result_hash',r.result_hash
           )
    from proxy_backtest r

    union all
    select 'DECISION_EXECUTION_PRICE_SEPARATION',
           p.input_count=2,
           'critical',
           jsonb_build_object('loaded_price_inputs',p.input_count)
    from price_inputs p

    union all
    select 'OFFICIAL_ANNUAL_REPORT_PDF_HASHED',
           p.hashed_pdf_count>0,
           'critical',
           jsonb_build_object(
               'catalog_records',p.catalog_count,
               'hashed_pdf_records',p.hashed_pdf_count
           )
    from official_pdf p

    union all
    select 'FORMAL_OWNER_EARNINGS_INPUTS_COMPLETE',
           coalesce(g.missing_count,0)=0,
           'critical',
           jsonb_build_object(
               'missing_count',coalesce(g.missing_count,0),
               'missing',coalesce(g.missing,'[]'::jsonb)
           )
    from formal_gap g

    union all
    select 'MARKET_PRICE_CROSS_VALIDATED',
           m.open_count=0,
           'critical',
           jsonb_build_object('open_reconciliation_issues',m.open_count)
    from market_reconciliation m

    union all
    select 'CORPORATE_ACTION_LEDGER_READY',
           c.action_count>0 and c.formal_grade_count=c.action_count,
           'critical',
           jsonb_build_object(
               'actions_in_five_year_window',c.action_count,
               'formal_grade_actions',c.formal_grade_count
           )
    from corporate_actions c

    union all
    select 'EVIDENCE_MINIMUM_GRADE',
           e.total_count>0 and e.formal_grade_count=e.total_count,
           'critical',
           jsonb_build_object(
               'formal_grade_count',e.formal_grade_count,
               'total_assertions',e.total_count
           )
    from evidence e;
$$;

revoke all on function audit.gate0_status() from public,anon,authenticated;
grant execute on function audit.gate0_status() to service_role;

commit;
