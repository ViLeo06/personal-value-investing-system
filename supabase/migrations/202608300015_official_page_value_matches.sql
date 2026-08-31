begin;

create table if not exists audit.page_value_matches (
    match_id bigint generated always as identity primary key,
    extraction_document_id uuid not null references raw.documents(document_id),
    page_hit_record_id bigint not null references raw.records(record_id),
    fact_id bigint references pit.financial_facts(fact_id),
    metric_code text not null,
    page_number integer,
    keyword text not null,
    source_number_text text not null,
    parsed_number numeric not null,
    scale numeric not null,
    normalized_value numeric not null,
    target_value numeric not null,
    absolute_difference numeric not null,
    relative_difference numeric,
    status text not null default 'candidate'
        check (status in ('candidate','validated','rejected','superseded')),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    validated_at timestamptz,
    unique (
        extraction_document_id,page_hit_record_id,metric_code,
        source_number_text,scale,target_value
    ),
    check (scale > 0),
    check (absolute_difference >= 0),
    check (jsonb_typeof(metadata)='object')
);

create index if not exists page_value_matches_metric_status_idx
    on audit.page_value_matches(metric_code,status,relative_difference);
create index if not exists page_value_matches_fact_idx
    on audit.page_value_matches(fact_id);
create index if not exists page_value_matches_document_page_idx
    on audit.page_value_matches(extraction_document_id,page_number);

create or replace function audit.parse_report_number(p_value text)
returns numeric
language plpgsql
immutable
strict
security invoker
set search_path=''
as $$
declare
    v_text text := btrim(p_value);
    v_negative boolean := false;
begin
    if v_text ~ '^\(.*\)$' then
        v_negative := true;
    end if;
    v_text := regexp_replace(v_text,'[(),，（）[:space:]]','','g');
    if v_text !~ '^-?[0-9]+(\.[0-9]+)?$' then
        return null;
    end if;
    if v_negative and left(v_text,1) <> '-' then
        return -v_text::numeric;
    end if;
    return v_text::numeric;
exception
    when numeric_value_out_of_range or invalid_text_representation then
        return null;
end;
$$;

revoke all on audit.page_value_matches from public,anon,authenticated;
revoke all on function audit.parse_report_number(text)
    from public,anon,authenticated;
grant execute on function audit.parse_report_number(text)
    to service_role;

commit;
