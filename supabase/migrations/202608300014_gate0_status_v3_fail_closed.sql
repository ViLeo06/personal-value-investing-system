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
set search_path=''
as $$
    with catalog as (
        select *
        from audit.gate_check_catalog
        where gate_code='GATE0' and enabled
    ), master_counts as (
        select
            count(*) filter(
                where issuer_code in ('KWEICHOW_MOUTAI','TENCENT','BYD','CMB')
            )::integer as issuer_count,
            (
                select count(*)::integer
                from master.securities s
                join master.issuers i on i.issuer_id=s.issuer_id
                where i.issuer_code in ('KWEICHOW_MOUTAI','TENCENT','BYD','CMB')
            ) as security_count
        from master.issuers
    ), valuation_cases as (
        select
            i.issuer_code,
            count(distinct vr.as_of_at)::integer as completed_cases
        from master.issuers i
        left join model.valuation_runs vr
          on vr.issuer_id=i.issuer_id
         and vr.status in ('completed','completed_formal')
        left join model.model_versions mv
          on mv.model_version_id=vr.model_version_id
        where i.issuer_code in ('KWEICHOW_MOUTAI','TENCENT','BYD','CMB')
          and (
              vr.run_id is null
              or (
                  coalesce(vr.scenario_set_version,'') not ilike '%proxy%'
                  and coalesce(mv.semantic_version,'') not ilike '%proxy%'
              )
          )
        group by i.issuer_code
    ), valuation_matrix as (
        select
            count(*) filter(where completed_cases>=3)::integer as issuers_with_three_cases,
            coalesce(sum(completed_cases),0)::integer as completed_case_count,
            coalesce(jsonb_object_agg(issuer_code,completed_cases order by issuer_code),'{}'::jsonb)
                as cases_by_issuer
        from valuation_cases
    ), snapshot as (
        select
            count(*)::integer as snapshot_count,
            max(snapshot_id::text) as snapshot_id,
            max(snapshot_hash) as snapshot_hash,
            max(coalesce((manifest->>'fact_count')::integer,0)) as fact_count
        from audit.data_snapshots
        where cutoff_policy_version='pit_cutoff_v3_content_hash'
          and as_of_at='2021-03-31T16:00:00Z'::timestamptz
    ), function_leaks as (
        select
            count(*) filter(
                where has_function_privilege('anon',p.oid,'execute')
                   or has_function_privilege('authenticated',p.oid,'execute')
            )::integer as leak_count,
            coalesce(jsonb_agg(
                jsonb_build_object(
                    'schema',n.nspname,
                    'function',p.proname,
                    'anon_execute',has_function_privilege('anon',p.oid,'execute'),
                    'authenticated_execute',has_function_privilege('authenticated',p.oid,'execute')
                ) order by n.nspname,p.proname,p.oid
            ) filter(
                where has_function_privilege('anon',p.oid,'execute')
                   or has_function_privilege('authenticated',p.oid,'execute')
            ),'[]'::jsonb) as leaks
        from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
        where (n.nspname,p.proname) in (
            ('pit','financial_facts_as_of'),
            ('pit','market_bars_as_of'),
            ('pit','corporate_actions_as_of'),
            ('audit','financial_snapshot_manifest'),
            ('audit','gate0_status'),
            ('audit','gate0_overall'),
            ('audit','capture_gate0_status'),
            ('audit','gate_evidence_requirement_status'),
            ('audit','proxy_backtest_integrity')
        )
    ), required_inputs as (
        select
            count(*)::integer as required_count,
            count(*) filter(
                where a.assumption_id is not null
                  and (
                      a.value_numeric is not null
                      or a.value_text is not null
                      or a.value_json is not null
                  )
            )::integer as present_count,
            coalesce(jsonb_agg(r.input_key order by r.input_key) filter(
                where a.assumption_id is null
                   or (
                       a.value_numeric is null
                       and a.value_text is null
                       and a.value_json is null
                   )
            ),'[]'::jsonb) as missing_inputs
        from audit.gate_input_requirements r
        left join model.run_assumptions a
          on a.run_id=r.run_id
         and a.scenario=r.scenario
         and a.assumption_key=r.input_key
        where r.gate_code='GATE0'
    ), formal_run as (
        select
            count(*)::integer as run_count,
            max(status) as status,
            max(input_hash) as input_hash,
            max(output_hash) as output_hash
        from model.valuation_runs
        where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
    ), proxy_valuation as (
        select
            count(distinct vr.run_id)::integer as run_count,
            max(vr.status) as status,
            max(vr.input_hash) as input_hash,
            max(vr.output_hash) as output_hash,
            count(vo.output_id)::integer as output_count
        from model.valuation_runs vr
        left join model.valuation_outputs vo on vo.run_id=vr.run_id
        where vr.run_id='40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
    ), proxy_backtest as (
        select
            count(*)::integer as run_count,
            max(b.status) as status,
            max(b.result_hash) as result_hash,
            (
                select count(*)::integer from backtest.daily_performance d
                where d.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
            ) as daily_rows,
            (
                select count(*)::integer from backtest.transactions t
                where t.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
            ) as transaction_rows,
            (
                select count(*)::integer from backtest.performance_metrics m
                where m.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
            ) as metric_rows,
            (
                select count(*)::integer from backtest.attribution_results a
                where a.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
            ) as attribution_rows
        from backtest.backtest_runs b
        where b.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    ), proxy_integrity as (
        select
            count(*)::integer as check_count,
            count(*) filter(where not passed)::integer as failure_count,
            coalesce(jsonb_agg(
                jsonb_build_object('check_code',check_code,'details',details)
                order by check_code
            ) filter(where not passed),'[]'::jsonb) as failures
        from audit.proxy_backtest_integrity(
            'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
        )
    ), timing_inputs as (
        select
            count(*) filter(
                where assumption_key='reference_close_price'
                  and value_numeric is not null
                  and provenance->>'timing_role'='decision_reference'
                  and provenance->>'trade_date'='2021-03-31'
            )::integer as reference_count,
            count(*) filter(
                where assumption_key='execution_open_price'
                  and value_numeric is not null
                  and provenance->>'timing_role'='execution_outcome'
                  and provenance->>'trade_date'='2021-04-01'
            )::integer as execution_count
        from model.run_assumptions
        where run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
          and scenario='control'
    ), official_pdf as (
        select
            count(*)::integer as catalog_count,
            count(*) filter(
                where d.content_hash is not null
                  and length(d.content_hash)=64
                  and d.mime_type='application/pdf'
            )::integer as hashed_pdf_count,
            coalesce(jsonb_agg(
                jsonb_build_object(
                    'document_id',d.document_id,
                    'title',d.title,
                    'source_url',d.source_url,
                    'content_hash',d.content_hash,
                    'document_type',d.document_type
                ) order by d.retrieved_at,d.document_id
            ),'[]'::jsonb) as documents
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
    ), evidence_requirements as (
        select
            count(*)::integer as requirement_count,
            count(*) filter(where passed)::integer as passed_count,
            coalesce(jsonb_agg(
                jsonb_build_object(
                    'requirement_code',requirement_code,
                    'qualifying_count',qualifying_count,
                    'required_count',required_count,
                    'candidate_count',candidate_count,
                    'below_grade_count',below_grade_count,
                    'missing_hash_count',missing_hash_count,
                    'conflict_count',conflict_count,
                    'details',details
                ) order by requirement_code
            ) filter(where not passed),'[]'::jsonb) as failures
        from audit.gate_evidence_requirement_status('GATE0')
    ), market_evidence as (
        select
            count(*)::integer as requirement_count,
            count(*) filter(where passed)::integer as passed_count
        from audit.gate_evidence_requirement_status('GATE0')
        where requirement_code in (
            'MOUTAI_REFERENCE_CLOSE','MOUTAI_EXECUTION_OPEN'
        )
    ), market_issues as (
        select count(*)::integer as open_count
        from audit.data_quality_issues
        where status='open'
          and rule_code in (
              'MARKET_PRICE_SECOND_SOURCE_REQUIRED',
              'SSE_MARKET_REFERENCE_PARSE_REQUIRED'
          )
          and record_key in (
              '600519.SH|2021-03-31|2021-04-01',
              '600519.SH|SSE_PARSE'
          )
    ), corporate_actions as (
        select
            count(*)::integer as action_count,
            count(*) filter(
                where exists (
                    select 1
                    from audit.evidence_assertions e
                    where e.status='active'
                      and e.assertion_code='cash_dividend'
                      and e.subject_type='corporate_action'
                      and e.subject_id=ca.action_id::text
                      and e.evidence_grade>=2
                      and cardinality(e.content_hashes)>0
                      and not e.unresolved_conflict
                )
            )::integer as qualifying_action_count
        from pit.corporate_actions ca
        join master.securities s on s.security_id=ca.security_id
        where s.security_code='600519.SH'
          and ca.action_type='cash_dividend'
          and ca.ex_date between '2021-04-01'::date and '2026-04-01'::date
    ), corporate_action_issues as (
        select count(*)::integer as open_count
        from audit.data_quality_issues
        where status='open'
          and rule_code in (
              'CORPORATE_ACTION_SECOND_SOURCE_REQUIRED',
              'CORPORATE_ACTION_FIELD_MAPPING_REVIEW_REQUIRED'
          )
          and record_key in (
              '600519.SH|2021-2026|CASH_DIVIDENDS',
              '600519.SH|DIVIDEND_FIELDS'
          )
    ), golden as (
        select
            count(*) filter(where b.status='validated')::integer as validated_baselines,
            count(*) filter(
                where b.status='validated'
                  and exists (
                      select 1
                      from audit.golden_test_results r
                      where r.baseline_id=b.baseline_id and r.passed
                  )
            )::integer as passing_cases,
            coalesce(jsonb_agg(b.case_code order by b.case_code) filter(
                where b.status='validated'
                  and not exists (
                      select 1
                      from audit.golden_test_results r
                      where r.baseline_id=b.baseline_id and r.passed
                  )
            ),'[]'::jsonb) as validated_without_pass
        from audit.golden_baselines b
        where b.case_code like 'GATE0_%'
    ), manifests as (
        with targets(run_type,run_id) as (
            values
                ('valuation'::text,'8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid),
                ('valuation'::text,'40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid),
                ('backtest'::text,'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid)
        )
        select
            count(*)::integer as target_count,
            count(*) filter(
                where exists (
                    select 1
                    from audit.run_manifests m
                    where m.run_type=t.run_type
                      and m.run_id=t.run_id
                      and length(m.manifest_hash)=64
                )
            )::integer as frozen_count,
            coalesce(jsonb_agg(
                jsonb_build_object('run_type',t.run_type,'run_id',t.run_id)
                order by t.run_type,t.run_id
            ) filter(
                where not exists (
                    select 1
                    from audit.run_manifests m
                    where m.run_type=t.run_type
                      and m.run_id=t.run_id
                      and length(m.manifest_hash)=64
                )
            ),'[]'::jsonb) as missing
        from targets t
    ), observed as (
        select
            'MASTER_DATA_FOUR_COMPANIES'::text as check_code,
            m.issuer_count=4 and m.security_count>=6 as passed,
            jsonb_build_object(
                'issuer_count',m.issuer_count,
                'security_count',m.security_count
            ) as details
        from master_counts m

        union all
        select
            'VALUATION_MATRIX_TWELVE_CASES',
            v.issuers_with_three_cases=4 and v.completed_case_count>=12,
            jsonb_build_object(
                'issuers_with_three_cases',v.issuers_with_three_cases,
                'completed_case_count',v.completed_case_count,
                'expected_case_count',12,
                'cases_by_issuer',v.cases_by_issuer
            )
        from valuation_matrix v

        union all
        select
            'MOUTAI_REPRODUCIBLE_SNAPSHOT',
            s.snapshot_count>=1
                and s.fact_count>=6
                and length(coalesce(s.snapshot_hash,''))=64,
            jsonb_build_object(
                'snapshot_count',s.snapshot_count,
                'snapshot_id',s.snapshot_id,
                'snapshot_hash',s.snapshot_hash,
                'fact_count',s.fact_count
            )
        from snapshot s

        union all
        select
            'PRIVATE_PIT_FUNCTIONS',
            f.leak_count=0,
            jsonb_build_object('leak_count',f.leak_count,'leaks',f.leaks)
        from function_leaks f

        union all
        select
            'FORMAL_RUN_STATE_VALID',
            f.run_count=1
              and (
                  (r.present_count<r.required_count and f.status='blocked_data')
                  or (
                      r.present_count=r.required_count
                      and f.status in ('completed','completed_formal')
                      and length(coalesce(f.input_hash,''))=64
                      and length(coalesce(f.output_hash,''))=64
                  )
              ),
            jsonb_build_object(
                'run_count',f.run_count,
                'status',f.status,
                'required_input_count',r.required_count,
                'present_input_count',r.present_count,
                'missing_inputs',r.missing_inputs,
                'input_hash',f.input_hash,
                'output_hash',f.output_hash
            )
        from formal_run f cross join required_inputs r

        union all
        select
            'PROXY_VALUATION_END_TO_END',
            p.run_count=1
              and p.status='completed_proxy'
              and p.output_count>=18
              and length(coalesce(p.input_hash,''))=64
              and length(coalesce(p.output_hash,''))=64,
            jsonb_build_object(
                'run_count',p.run_count,
                'status',p.status,
                'output_count',p.output_count,
                'input_hash',p.input_hash,
                'output_hash',p.output_hash
            )
        from proxy_valuation p

        union all
        select
            'PROXY_BACKTEST_END_TO_END',
            p.run_count=1
              and p.status='completed_proxy'
              and p.daily_rows>=500
              and p.transaction_rows=2
              and p.metric_rows>=9
              and p.attribution_rows>=4
              and length(coalesce(p.result_hash,''))=64,
            jsonb_build_object(
                'run_count',p.run_count,
                'status',p.status,
                'daily_rows',p.daily_rows,
                'transaction_rows',p.transaction_rows,
                'metric_rows',p.metric_rows,
                'attribution_rows',p.attribution_rows,
                'result_hash',p.result_hash
            )
        from proxy_backtest p

        union all
        select
            'PROXY_BACKTEST_INTEGRITY',
            p.check_count>=9 and p.failure_count=0,
            jsonb_build_object(
                'check_count',p.check_count,
                'failure_count',p.failure_count,
                'failures',p.failures
            )
        from proxy_integrity p

        union all
        select
            'DECISION_EXECUTION_PRICE_SEPARATION',
            t.reference_count=1 and t.execution_count=1,
            jsonb_build_object(
                'reference_count',t.reference_count,
                'execution_count',t.execution_count,
                'reference_trade_date','2021-03-31',
                'execution_trade_date','2021-04-01'
            )
        from timing_inputs t

        union all
        select
            'OFFICIAL_ANNUAL_REPORT_PDF_HASHED',
            p.hashed_pdf_count>=1,
            jsonb_build_object(
                'catalog_count',p.catalog_count,
                'hashed_pdf_count',p.hashed_pdf_count,
                'documents',p.documents
            )
        from official_pdf p

        union all
        select
            'FORMAL_OWNER_EARNINGS_INPUTS_COMPLETE',
            r.required_count>0 and r.present_count=r.required_count,
            jsonb_build_object(
                'required_count',r.required_count,
                'present_count',r.present_count,
                'missing_inputs',r.missing_inputs
            )
        from required_inputs r

        union all
        select
            'MARKET_PRICE_CROSS_VALIDATED',
            e.requirement_count=2
              and e.passed_count=2
              and i.open_count=0,
            jsonb_build_object(
                'requirement_count',e.requirement_count,
                'passed_count',e.passed_count,
                'open_quality_issues',i.open_count
            )
        from market_evidence e cross join market_issues i

        union all
        select
            'CORPORATE_ACTION_LEDGER_READY',
            c.action_count>0
              and c.qualifying_action_count=c.action_count
              and i.open_count=0,
            jsonb_build_object(
                'action_count',c.action_count,
                'qualifying_action_count',c.qualifying_action_count,
                'open_quality_issues',i.open_count
            )
        from corporate_actions c cross join corporate_action_issues i

        union all
        select
            'EVIDENCE_MINIMUM_GRADE',
            e.requirement_count>0 and e.passed_count=e.requirement_count,
            jsonb_build_object(
                'requirement_count',e.requirement_count,
                'passed_count',e.passed_count,
                'failures',e.failures
            )
        from evidence_requirements e

        union all
        select
            'GOLDEN_TESTS_READY',
            g.validated_baselines>=12 and g.passing_cases>=12,
            jsonb_build_object(
                'validated_baselines',g.validated_baselines,
                'passing_cases',g.passing_cases,
                'expected_cases',12,
                'validated_without_pass',g.validated_without_pass
            )
        from golden g

        union all
        select
            'RUN_MANIFESTS_FROZEN',
            m.target_count=3 and m.frozen_count=m.target_count,
            jsonb_build_object(
                'target_count',m.target_count,
                'frozen_count',m.frozen_count,
                'missing',m.missing
            )
        from manifests m
    )
    select
        c.check_code,
        coalesce(o.passed,false) as passed,
        c.severity,
        case
            when o.check_code is null then jsonb_build_object(
                'error','check computation returned no row',
                'description',c.description
            )
            else o.details||jsonb_build_object('description',c.description)
        end as details
    from catalog c
    left join observed o using(check_code)
    order by c.ordinal;
$$;

revoke all on function audit.gate0_status()
    from public,anon,authenticated;
grant execute on function audit.gate0_status()
    to service_role;

commit;
