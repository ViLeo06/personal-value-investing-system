begin;

create table if not exists audit.gate_check_catalog (
    gate_code text not null,
    check_code text not null,
    ordinal integer not null,
    severity text not null check (severity in ('critical','warning','info')),
    description text not null,
    enabled boolean not null default true,
    primary key (gate_code,check_code),
    unique (gate_code,ordinal)
);

create table if not exists audit.gate_input_requirements (
    gate_code text not null,
    run_id uuid not null,
    input_key text not null,
    scenario text not null default 'control',
    description text not null,
    primary key (gate_code,run_id,scenario,input_key)
);

create table if not exists audit.gate_evidence_requirements (
    gate_code text not null,
    requirement_code text not null,
    assertion_code text not null,
    subject_type text not null,
    subject_id_pattern text,
    as_of_at timestamptz,
    minimum_grade smallint not null default 2
        check (minimum_grade between 0 and 3),
    required_count integer not null default 1 check (required_count > 0),
    require_content_hash boolean not null default true,
    description text not null,
    primary key (gate_code,requirement_code)
);

create table if not exists audit.golden_baselines (
    baseline_id uuid primary key default gen_random_uuid(),
    case_code text not null,
    workbook_name text not null,
    workbook_sha256 text not null,
    config_sha256 text not null,
    baseline_sha256 text not null,
    baseline_payload jsonb not null,
    status text not null default 'candidate'
        check (status in ('candidate','validated','deprecated','rejected')),
    created_at timestamptz not null default now(),
    unique (case_code,workbook_sha256,baseline_sha256),
    check (length(workbook_sha256)=64),
    check (length(config_sha256)=64),
    check (length(baseline_sha256)=64),
    check (jsonb_typeof(baseline_payload)='object')
);

create table if not exists audit.golden_test_results (
    result_id uuid primary key default gen_random_uuid(),
    baseline_id uuid not null references audit.golden_baselines(baseline_id),
    model_run_id uuid,
    code_commit_sha text,
    actual_output_hash text not null,
    relative_tolerance numeric not null,
    absolute_tolerance numeric not null,
    passed boolean not null,
    differences jsonb not null default '[]'::jsonb,
    tested_at timestamptz not null default now(),
    check (length(actual_output_hash)=64),
    check (jsonb_typeof(differences)='array')
);

create index if not exists gate_input_requirements_run_idx
    on audit.gate_input_requirements(run_id,scenario);
create index if not exists gate_evidence_requirements_assertion_idx
    on audit.gate_evidence_requirements(assertion_code,subject_type);
create index if not exists golden_baselines_case_status_idx
    on audit.golden_baselines(case_code,status);
create index if not exists golden_test_results_baseline_time_idx
    on audit.golden_test_results(baseline_id,tested_at desc);

insert into audit.gate_check_catalog
    (gate_code,check_code,ordinal,severity,description)
values
    ('GATE0','MASTER_DATA_FOUR_COMPANIES',10,'critical','Four validation issuers and their A/H securities are registered.'),
    ('GATE0','VALUATION_MATRIX_TWELVE_CASES',20,'critical','Four companies times three historical snapshots have completed formal valuation runs.'),
    ('GATE0','MOUTAI_REPRODUCIBLE_SNAPSHOT',30,'critical','The first Moutai decision snapshot is content-hashed and reproducible.'),
    ('GATE0','PRIVATE_PIT_FUNCTIONS',40,'critical','Internal PIT and audit functions are not executable by anon/authenticated roles.'),
    ('GATE0','FORMAL_RUN_STATE_VALID',50,'critical','The formal run fails closed while inputs are incomplete and may complete only after the data gate passes.'),
    ('GATE0','PROXY_VALUATION_END_TO_END',60,'warning','Engineering proxy valuation exercises the full valuation storage path.'),
    ('GATE0','PROXY_BACKTEST_END_TO_END',70,'warning','Engineering proxy backtest produces daily ledger, transactions, metrics and attribution.'),
    ('GATE0','PROXY_BACKTEST_INTEGRITY',80,'warning','The proxy backtest independently reconciles accounting identities and hashes.'),
    ('GATE0','DECISION_EXECUTION_PRICE_SEPARATION',90,'critical','The last observable close and later execution open are stored separately.'),
    ('GATE0','OFFICIAL_ANNUAL_REPORT_PDF_HASHED',100,'critical','The official annual report PDF is archived with a SHA-256 content hash.'),
    ('GATE0','FORMAL_OWNER_EARNINGS_INPUTS_COMPLETE',110,'critical','All formal Owner Earnings bridge inputs are persisted on the run.'),
    ('GATE0','MARKET_PRICE_CROSS_VALIDATED',120,'critical','Decision and execution prices are independently validated against an official exchange source.'),
    ('GATE0','CORPORATE_ACTION_LEDGER_READY',130,'critical','Every corporate action in the holding window has qualifying evidence.'),
    ('GATE0','EVIDENCE_MINIMUM_GRADE',140,'critical','Every fixed Gate 0 evidence requirement reaches the configured minimum grade.'),
    ('GATE0','GOLDEN_TESTS_READY',150,'critical','All twelve Gate 0 cases have validated V1.1 baselines and passing Golden Tests.'),
    ('GATE0','RUN_MANIFESTS_FROZEN',160,'critical','Formal valuation and backtest results have immutable run manifests.')
on conflict (gate_code,check_code) do update
set ordinal=excluded.ordinal,
    severity=excluded.severity,
    description=excluded.description,
    enabled=true;

insert into audit.gate_input_requirements
    (gate_code,run_id,input_key,scenario,description)
values
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'depreciation_amortization','control','Audited D&A used in the Owner Earnings bridge.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'other_non_cash_adjustments','control','Itemized non-cash adjustments; zero is allowed when explicitly supported.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'maintenance_capex','control','Maintenance capital expenditure under the frozen accounting policy.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'change_working_capital','control','Incremental operating working-capital cash use.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'shares_outstanding','control','Point-in-time common shares outstanding.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'net_cash','control','Net cash under the frozen account-inclusion policy.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'reference_close_price','control','Latest market close observable at decision time.'),
    ('GATE0','8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,'execution_open_price','control','First later-session execution open.')
on conflict (gate_code,run_id,scenario,input_key) do update
set description=excluded.description;

insert into audit.gate_evidence_requirements
    (gate_code,requirement_code,assertion_code,subject_type,subject_id_pattern,
     as_of_at,minimum_grade,required_count,require_content_hash,description)
values
    ('GATE0','MOUTAI_REVENUE_2020','revenue','issuer_period_fact','KWEICHOW_MOUTAI|2020-12-31|revenue','2021-03-31T16:00:00Z',3,1,true,'Audited 2020 revenue.'),
    ('GATE0','MOUTAI_NET_INCOME_2020','net_income_parent','issuer_period_fact','KWEICHOW_MOUTAI|2020-12-31|net_income_parent','2021-03-31T16:00:00Z',3,1,true,'Audited 2020 parent net income.'),
    ('GATE0','MOUTAI_OCF_2020','operating_cash_flow','issuer_period_fact','KWEICHOW_MOUTAI|2020-12-31|operating_cash_flow','2021-03-31T16:00:00Z',3,1,true,'Audited 2020 operating cash flow.'),
    ('GATE0','MOUTAI_TOTAL_ASSETS_2020','total_assets','issuer_period_fact','KWEICHOW_MOUTAI|2020-12-31|total_assets','2021-03-31T16:00:00Z',3,1,true,'Audited 2020 total assets.'),
    ('GATE0','MOUTAI_EQUITY_2020','equity_parent','issuer_period_fact','KWEICHOW_MOUTAI|2020-12-31|equity_parent','2021-03-31T16:00:00Z',3,1,true,'Audited 2020 parent equity.'),
    ('GATE0','MOUTAI_EPS_2020','basic_eps','issuer_period_fact','KWEICHOW_MOUTAI|2020-12-31|basic_eps','2021-03-31T16:00:00Z',3,1,true,'Audited 2020 basic EPS.'),
    ('GATE0','MOUTAI_REFERENCE_CLOSE','reference_close_price','valuation_run_input','8bcbb9d3-7fdb-529a-9f9a-547043040e13|reference_close_price','2021-03-31T16:00:00Z',3,1,true,'Officially validated last observable close.'),
    ('GATE0','MOUTAI_EXECUTION_OPEN','execution_open_price','valuation_run_input','8bcbb9d3-7fdb-529a-9f9a-547043040e13|execution_open_price','2021-03-31T16:00:00Z',3,1,true,'Officially validated later execution open.'),
    ('GATE0','MOUTAI_OFFICIAL_ANNUAL_REPORT','annual_report_publication','official_document',null,null,3,1,true,'Official annual-report PDF with content hash.')
on conflict (gate_code,requirement_code) do update
set assertion_code=excluded.assertion_code,
    subject_type=excluded.subject_type,
    subject_id_pattern=excluded.subject_id_pattern,
    as_of_at=excluded.as_of_at,
    minimum_grade=excluded.minimum_grade,
    required_count=excluded.required_count,
    require_content_hash=excluded.require_content_hash,
    description=excluded.description;

create or replace function audit.gate_evidence_requirement_status(p_gate_code text)
returns table(
    requirement_code text,
    passed boolean,
    qualifying_count integer,
    required_count integer,
    candidate_count integer,
    below_grade_count integer,
    missing_hash_count integer,
    conflict_count integer,
    details jsonb
)
language sql
stable
security invoker
set search_path=''
as $$
    with requirements as (
        select *
        from audit.gate_evidence_requirements
        where gate_code=p_gate_code
    ), evaluated as (
        select
            r.requirement_code,
            r.required_count,
            count(e.evidence_id)::integer as candidate_count,
            count(e.evidence_id) filter(
                where e.evidence_grade>=r.minimum_grade
                  and not e.unresolved_conflict
                  and (
                      not r.require_content_hash
                      or cardinality(e.content_hashes)>0
                  )
            )::integer as qualifying_count,
            count(e.evidence_id) filter(
                where e.evidence_grade<r.minimum_grade
            )::integer as below_grade_count,
            count(e.evidence_id) filter(
                where r.require_content_hash
                  and cardinality(e.content_hashes)=0
            )::integer as missing_hash_count,
            count(e.evidence_id) filter(
                where e.unresolved_conflict
            )::integer as conflict_count,
            jsonb_build_object(
                'assertion_code',r.assertion_code,
                'subject_type',r.subject_type,
                'subject_id_pattern',r.subject_id_pattern,
                'as_of_at',r.as_of_at,
                'minimum_grade',r.minimum_grade,
                'require_content_hash',r.require_content_hash,
                'description',r.description
            ) as details
        from requirements r
        left join audit.evidence_assertions e
          on e.status='active'
         and e.assertion_code=r.assertion_code
         and e.subject_type=r.subject_type
         and (r.subject_id_pattern is null or e.subject_id like r.subject_id_pattern)
         and (r.as_of_at is null or e.as_of_at=r.as_of_at)
        group by
            r.requirement_code,r.required_count,r.assertion_code,r.subject_type,
            r.subject_id_pattern,r.as_of_at,r.minimum_grade,
            r.require_content_hash,r.description
    )
    select
        requirement_code,
        qualifying_count>=required_count as passed,
        qualifying_count,
        required_count,
        candidate_count,
        below_grade_count,
        missing_hash_count,
        conflict_count,
        details
    from evaluated
    order by requirement_code;
$$;

revoke all on audit.gate_check_catalog from public,anon,authenticated;
revoke all on audit.gate_input_requirements from public,anon,authenticated;
revoke all on audit.gate_evidence_requirements from public,anon,authenticated;
revoke all on audit.golden_baselines from public,anon,authenticated;
revoke all on audit.golden_test_results from public,anon,authenticated;
revoke all on function audit.gate_evidence_requirement_status(text)
    from public,anon,authenticated;
grant execute on function audit.gate_evidence_requirement_status(text)
    to service_role;

commit;
