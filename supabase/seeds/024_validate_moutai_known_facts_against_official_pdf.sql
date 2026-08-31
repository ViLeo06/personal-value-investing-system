begin;

create temporary table _known_fact_matches on commit drop as
with ranked_facts as (
    select
        f.*,
        row_number() over(
            partition by f.metric_code
            order by f.available_at desc,f.revision_no desc,f.fact_id desc
        ) as rn
    from pit.financial_facts f
    join master.issuers i on i.issuer_id=f.issuer_id
    where i.issuer_code='KWEICHOW_MOUTAI'
      and f.period_end='2020-12-31'::date
      and f.available_at<='2021-03-31T16:00:00Z'::timestamptz
      and f.metric_code in (
          'revenue','net_income_parent','operating_cash_flow',
          'total_assets','equity_parent','basic_eps'
      )
      and f.value_numeric is not null
), facts as (
    select * from ranked_facts where rn=1
), keyword_map(metric_code,keyword) as (
    values
        ('revenue'::text,'营业收入'::text),
        ('revenue','营业总收入'),
        ('net_income_parent','归属于母公司股东的净利润'),
        ('net_income_parent','归属于母公司所有者的净利润'),
        ('operating_cash_flow','经营活动产生的现金流量净额'),
        ('total_assets','资产总计'),
        ('equity_parent','归属于母公司所有者权益合计'),
        ('equity_parent','归属于母公司股东权益'),
        ('basic_eps','基本每股收益')
), extraction as (
    select d.*
    from raw.documents d
    join master.issuers i on i.issuer_id=d.issuer_id
    where i.issuer_code='KWEICHOW_MOUTAI'
      and d.document_type='official_annual_report_extraction_v2'
      and length(coalesce(d.content_hash,''))=64
    order by d.retrieved_at desc,d.document_id desc
    limit 1
), hits as (
    select
        r.record_id,r.document_id,r.record_hash,r.payload,r.published_at,
        (r.payload->>'page')::integer as page_number,
        r.payload->>'keyword' as keyword
    from raw.records r
    join extraction e on e.document_id=r.document_id
    where r.dataset_code='cninfo_annual_report_page_hit_v2'
      and jsonb_typeof(r.payload->'candidate_numbers')='array'
), numbers as (
    select
        h.*,
        number_text,
        audit.parse_report_number(number_text) as parsed_number
    from hits h
    cross join lateral jsonb_array_elements_text(h.payload->'candidate_numbers') n(number_text)
), candidates as (
    select
        e.document_id as extraction_document_id,
        n.record_id as page_hit_record_id,
        f.fact_id,
        f.metric_code,
        n.page_number,
        n.keyword,
        n.number_text as source_number_text,
        n.parsed_number,
        s.scale,
        n.parsed_number*s.scale as normalized_value,
        f.value_numeric as target_value,
        abs(n.parsed_number*s.scale-f.value_numeric) as absolute_difference,
        case when f.value_numeric=0 then null
             else abs(n.parsed_number*s.scale-f.value_numeric)/abs(f.value_numeric) end
             as relative_difference,
        greatest(
            0.05::numeric,
            s.scale*0.011::numeric,
            abs(f.value_numeric)*0.000000001::numeric
        ) as tolerance,
        n.record_hash as page_hit_record_hash,
        f.record_hash as fact_record_hash,
        e.content_hash as extraction_hash,
        e.metadata->>'official_pdf_hash' as official_pdf_hash,
        n.payload->>'snippet' as snippet
    from facts f
    join keyword_map km on km.metric_code=f.metric_code
    join numbers n on n.keyword=km.keyword and n.parsed_number is not null
    cross join extraction e
    cross join lateral (values
        (1::numeric),(1000::numeric),(10000::numeric),(1000000::numeric)
    ) s(scale)
    where (f.metric_code<>'basic_eps' or s.scale=1)
      and abs(n.parsed_number*s.scale-f.value_numeric)<=greatest(
          0.05::numeric,
          s.scale*0.011::numeric,
          abs(f.value_numeric)*0.000000001::numeric
      )
), inserted as (
    insert into audit.page_value_matches
        (extraction_document_id,page_hit_record_id,fact_id,metric_code,
         page_number,keyword,source_number_text,parsed_number,scale,
         normalized_value,target_value,absolute_difference,relative_difference,
         status,metadata)
    select
        c.extraction_document_id,c.page_hit_record_id,c.fact_id,c.metric_code,
        c.page_number,c.keyword,c.source_number_text,c.parsed_number,c.scale,
        c.normalized_value,c.target_value,c.absolute_difference,c.relative_difference,
        'candidate',
        jsonb_build_object(
            'tolerance',c.tolerance,
            'page_hit_record_hash',c.page_hit_record_hash,
            'fact_record_hash',c.fact_record_hash,
            'extraction_hash',c.extraction_hash,
            'official_pdf_hash',c.official_pdf_hash,
            'snippet',c.snippet,
            'matching_policy','keyword plus numeric equality under explicit scale',
            'matching_version','official-page-value-match-v1'
        )
    from candidates c
    on conflict (
        extraction_document_id,page_hit_record_id,metric_code,
        source_number_text,scale,target_value
    ) do update
    set fact_id=excluded.fact_id,
        page_number=excluded.page_number,
        keyword=excluded.keyword,
        parsed_number=excluded.parsed_number,
        normalized_value=excluded.normalized_value,
        absolute_difference=excluded.absolute_difference,
        relative_difference=excluded.relative_difference,
        metadata=excluded.metadata
    returning *
)
select * from inserted;

with ranked as (
    select
        m.match_id,
        row_number() over(
            partition by m.metric_code
            order by
                m.relative_difference nulls last,
                m.absolute_difference,
                m.page_number,
                m.match_id
        ) as rn
    from audit.page_value_matches m
    where m.extraction_document_id=(
        select document_id
        from raw.documents d
        join master.issuers i on i.issuer_id=d.issuer_id
        where i.issuer_code='KWEICHOW_MOUTAI'
          and d.document_type='official_annual_report_extraction_v2'
        order by d.retrieved_at desc,d.document_id desc
        limit 1
    )
      and m.metric_code in (
          'revenue','net_income_parent','operating_cash_flow',
          'total_assets','equity_parent','basic_eps'
      )
      and m.status in ('candidate','validated')
)
update audit.page_value_matches m
set status=case when r.rn=1 then 'validated' else 'candidate' end,
    validated_at=case when r.rn=1 then now() else null end
from ranked r
where r.match_id=m.match_id;

update audit.evidence_assertions e
set status='superseded'
where e.status='active'
  and e.evidence_grade<3
  and e.subject_type='issuer_period_fact'
  and e.subject_id in (
      'KWEICHOW_MOUTAI|2020-12-31|revenue',
      'KWEICHOW_MOUTAI|2020-12-31|net_income_parent',
      'KWEICHOW_MOUTAI|2020-12-31|operating_cash_flow',
      'KWEICHOW_MOUTAI|2020-12-31|total_assets',
      'KWEICHOW_MOUTAI|2020-12-31|equity_parent',
      'KWEICHOW_MOUTAI|2020-12-31|basic_eps'
  )
  and exists (
      select 1
      from audit.page_value_matches m
      where m.status='validated'
        and m.metric_code=e.assertion_code
  );

insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    m.metric_code,
    'issuer_period_fact',
    'KWEICHOW_MOUTAI|2020-12-31|'||m.metric_code,
    '2021-03-31T16:00:00Z'::timestamptz,
    3,
    'active',
    array['CNINFO'],
    array_remove(array[
        m.metadata->>'official_pdf_hash',
        m.metadata->>'extraction_hash',
        m.metadata->>'page_hit_record_hash',
        m.metadata->>'fact_record_hash'
    ],null),
    false,
    jsonb_build_object(
        'fact_id',m.fact_id,
        'page',m.page_number,
        'keyword',m.keyword,
        'source_number_text',m.source_number_text,
        'parsed_number',m.parsed_number,
        'scale',m.scale,
        'normalized_value',m.normalized_value,
        'target_value',m.target_value,
        'absolute_difference',m.absolute_difference,
        'relative_difference',m.relative_difference,
        'page_hit_record_id',m.page_hit_record_id,
        'extraction_document_id',m.extraction_document_id,
        'quality_reason','known PIT fact exactly reconciled to a hashed official PDF page under an explicit unit scale'
    ),
    'official-page-value-match-v1'
from audit.page_value_matches m
where m.status='validated'
  and m.metric_code in (
      'revenue','net_income_parent','operating_cash_flow',
      'total_assets','equity_parent','basic_eps'
  )
  and not exists (
      select 1 from audit.evidence_assertions e
      where e.assertion_code=m.metric_code
        and e.subject_type='issuer_period_fact'
        and e.subject_id='KWEICHOW_MOUTAI|2020-12-31|'||m.metric_code
        and e.evidence_grade=3
        and e.status='active'
  );

with summary as (
    select
        count(distinct metric_code) filter(where status='validated')::integer
            as matched_metric_count,
        coalesce(jsonb_agg(metric_code order by metric_code) filter(
            where metric_code not in (
                select metric_code
                from audit.page_value_matches
                where status='validated'
            )
        ),'[]'::jsonb) as missing_metrics
    from (values
        ('revenue'::text),('net_income_parent'),('operating_cash_flow'),
        ('total_assets'),('equity_parent'),('basic_eps')
    ) required(metric_code)
)
update audit.data_quality_issues q
set severity=case when s.matched_metric_count=6 then 'info' else 'critical' end,
    status=case when s.matched_metric_count=6 then 'resolved' else 'open' end,
    resolved_at=case when s.matched_metric_count=6 then now() else null end,
    detected_at=now(),
    description=case when s.matched_metric_count=6
        then 'All six known 2020 Moutai PIT facts reconcile to hashed official PDF pages.'
        else 'One or more known 2020 Moutai PIT facts do not yet reconcile to a hashed official PDF page.' end,
    details=jsonb_build_object(
        'required_metric_count',6,
        'matched_metric_count',s.matched_metric_count,
        'missing_metrics',s.missing_metrics,
        'matching_version','official-page-value-match-v1'
    )
from summary s
where q.rule_code='OFFICIAL_KNOWN_FACT_PAGE_MATCH_REQUIRED'
  and q.record_key='KWEICHOW_MOUTAI|2020_KNOWN_FACTS';

with summary as (
    select
        count(distinct metric_code) filter(where status='validated')::integer
            as matched_metric_count,
        coalesce(jsonb_agg(metric_code order by metric_code) filter(
            where metric_code not in (
                select metric_code
                from audit.page_value_matches
                where status='validated'
            )
        ),'[]'::jsonb) as missing_metrics
    from (values
        ('revenue'::text),('net_income_parent'),('operating_cash_flow'),
        ('total_assets'),('equity_parent'),('basic_eps')
    ) required(metric_code)
)
insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details,
     resolved_at)
select
    case when s.matched_metric_count=6 then 'info' else 'critical' end,
    'official_fact_reconciliation','audit.page_value_matches',
    'KWEICHOW_MOUTAI|2020_KNOWN_FACTS',
    'OFFICIAL_KNOWN_FACT_PAGE_MATCH_REQUIRED',
    case when s.matched_metric_count=6
        then 'All six known 2020 Moutai PIT facts reconcile to hashed official PDF pages.'
        else 'One or more known 2020 Moutai PIT facts do not yet reconcile to a hashed official PDF page.' end,
    case when s.matched_metric_count=6 then 'resolved' else 'open' end,
    jsonb_build_object(
        'required_metric_count',6,
        'matched_metric_count',s.matched_metric_count,
        'missing_metrics',s.missing_metrics,
        'matching_version','official-page-value-match-v1'
    ),
    case when s.matched_metric_count=6 then now() else null end
from summary s
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='OFFICIAL_KNOWN_FACT_PAGE_MATCH_REQUIRED'
      and q.record_key='KWEICHOW_MOUTAI|2020_KNOWN_FACTS'
  );

commit;
