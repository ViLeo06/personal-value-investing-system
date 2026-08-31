begin;

create table if not exists audit.gate_status_history (
    capture_id uuid not null,
    captured_at timestamptz not null default now(),
    gate_code text not null,
    check_code text not null,
    passed boolean not null,
    severity text not null,
    details jsonb not null default '{}'::jsonb,
    git_commit_sha text,
    primary key (capture_id,check_code)
);

create index if not exists gate_status_history_gate_time_idx
    on audit.gate_status_history(gate_code,captured_at desc);
create index if not exists gate_status_history_failed_idx
    on audit.gate_status_history(gate_code,severity,passed,captured_at desc);

create or replace function audit.capture_gate0_status(
    p_git_commit_sha text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_capture_id uuid := gen_random_uuid();
begin
    insert into audit.gate_status_history
        (capture_id,captured_at,gate_code,check_code,passed,severity,details,git_commit_sha)
    select
        v_capture_id,
        now(),
        'GATE0',
        s.check_code,
        s.passed,
        s.severity,
        s.details,
        p_git_commit_sha
    from audit.gate0_status() s;
    return v_capture_id;
end;
$$;

create or replace function audit.gate0_overall()
returns table(
    status text,
    critical_passed integer,
    critical_total integer,
    warning_passed integer,
    warning_total integer,
    failed_checks jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
    with checks as (
        select * from audit.gate0_status()
    )
    select
        case
            when count(*) filter(where severity='critical' and not passed)>0
                then 'blocked'
            when count(*) filter(where severity='warning' and not passed)>0
                then 'conditional_pass'
            else 'passed'
        end as status,
        count(*) filter(where severity='critical' and passed)::integer,
        count(*) filter(where severity='critical')::integer,
        count(*) filter(where severity='warning' and passed)::integer,
        count(*) filter(where severity='warning')::integer,
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'check_code',check_code,
                    'severity',severity,
                    'details',details
                ) order by severity,check_code
            ) filter(where not passed),
            '[]'::jsonb
        ) as failed_checks
    from checks;
$$;

revoke all on audit.gate_status_history from public,anon,authenticated;
revoke all on function audit.capture_gate0_status(text) from public,anon,authenticated;
revoke all on function audit.gate0_overall() from public,anon,authenticated;
grant execute on function audit.capture_gate0_status(text) to service_role;
grant execute on function audit.gate0_overall() to service_role;

commit;
