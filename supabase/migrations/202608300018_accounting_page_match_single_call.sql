begin;

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
    v_validated_count integer := 0;
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
    )
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
            'matching_version','accounting-candidate-page-match-v3'
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
        metadata=excluded.metadata;

    with ranked as (
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
    )
    update audit.accounting_candidate_page_matches m
    set status=case when r.rn=1 then 'validated' else 'candidate' end,
        validated_at=case when r.rn=1 then now() else null end
    from ranked r
    where r.match_id=m.match_id;

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
      and c.status in ('candidate','page_matched');

    select count(*)::integer into v_validated_count
    from audit.accounting_candidate_page_matches m
    join fundamentals.accounting_input_candidates c
      on c.candidate_id=m.candidate_id
    where c.run_id=p_run_id
      and c.period_end=p_period_end
      and m.status='validated';

    return v_validated_count;
end;
$$;

revoke all on function audit.match_accounting_candidates_to_official_pages(uuid,date,text)
    from public,anon,authenticated;
grant execute on function audit.match_accounting_candidates_to_official_pages(uuid,date,text)
    to service_role;

commit;
