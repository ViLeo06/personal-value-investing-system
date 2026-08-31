begin;

with source_rows as (
    select
        r.record_id,
        r.document_id,
        r.security_id,
        r.dataset_code,
        r.payload,
        r.record_hash,
        coalesce(
            nullif(r.payload->>'NOTICE_DATE',''),
            nullif(r.payload->>'ANNOUNCE_DATE',''),
            nullif(r.payload->>'ANNOUNCEMENT_DATE','')
        ) as notice_date_raw,
        coalesce(
            nullif(r.payload->>'EX_DIVIDEND_DATE',''),
            nullif(r.payload->>'EX_DATE',''),
            nullif(r.payload->>'EX_RIGHT_DATE',''),
            nullif(r.payload->>'EX_DIVIDEND_DAY','')
        ) as ex_date_raw,
        coalesce(
            nullif(r.payload->>'EQUITY_RECORD_DATE',''),
            nullif(r.payload->>'RECORD_DATE','')
        ) as record_date_raw,
        coalesce(
            nullif(r.payload->>'CASH_DIVIDEND_DATE',''),
            nullif(r.payload->>'PAY_CASH_DATE',''),
            nullif(r.payload->>'PAYMENT_DATE',''),
            nullif(r.payload->>'DIVIDEND_DATE','')
        ) as payment_date_raw,
        nullif(r.payload->>'PRETAX_BONUS_RMB','') as cash_per_ten_raw
    from raw.records r
    join master.securities s on s.security_id=r.security_id
    where s.security_code='600519.SH'
      and r.dataset_code in (
          'eastmoney_sharebonus_det',
          'eastmoney_f10_dividend',
          'eastmoney_f10_bonusfinance'
      )
), parsed as (
    select
        *,
        case when notice_date_raw ~ '^\d{4}-\d{2}-\d{2}'
             then left(notice_date_raw,10)::date end as notice_date,
        case when ex_date_raw ~ '^\d{4}-\d{2}-\d{2}'
             then left(ex_date_raw,10)::date end as ex_date,
        case when record_date_raw ~ '^\d{4}-\d{2}-\d{2}'
             then left(record_date_raw,10)::date end as record_date,
        case when payment_date_raw ~ '^\d{4}-\d{2}-\d{2}'
             then left(payment_date_raw,10)::date end as payment_date,
        case when cash_per_ten_raw ~ '^-?[0-9]+(\.[0-9]+)?$'
             then cash_per_ten_raw::numeric end as cash_per_ten
    from source_rows
), eligible as (
    select *
    from parsed
    where ex_date between '2021-04-01'::date and '2026-04-01'::date
      and cash_per_ten > 0
      and cash_per_ten <= 1000
), inserted as (
    insert into pit.corporate_actions
        (security_id,action_type,announced_at,available_at,ex_date,record_date,
         payment_date,effective_date,cash_amount_per_share,currency,
         source_document_id,record_hash,metadata)
    select
        e.security_id,
        'cash_dividend',
        case when e.notice_date is null then null
             else (e.notice_date::timestamp at time zone 'Asia/Shanghai') end,
        case when e.notice_date is null
             then ((e.ex_date-1)::timestamp at time zone 'Asia/Shanghai')
             else ((e.notice_date+1)::timestamp at time zone 'Asia/Shanghai') end,
        e.ex_date,
        e.record_date,
        e.payment_date,
        e.ex_date,
        e.cash_per_ten/10.0,
        'CNY',
        e.document_id,
        encode(
            extensions.digest(
                convert_to(
                    concat_ws('|','600519.SH','cash_dividend',e.ex_date::text,
                              (e.cash_per_ten/10.0)::text,
                              coalesce(e.record_date::text,''),
                              coalesce(e.payment_date::text,''),e.record_hash),
                    'UTF8'
                ),'sha256'
            ),'hex'
        ),
        jsonb_build_object(
            'source_record_id',e.record_id,
            'dataset_code',e.dataset_code,
            'source_field_cash','PRETAX_BONUS_RMB',
            'source_unit','CNY per 10 shares',
            'normalization','divide by 10',
            'methodology_quality','candidate_requires_official_announcement',
            'evidence_grade',1
        )
    from eligible e
    where not exists (
        select 1 from pit.corporate_actions existing
        where existing.security_id=e.security_id
          and existing.action_type='cash_dividend'
          and existing.ex_date=e.ex_date
          and existing.cash_amount_per_share=e.cash_per_ten/10.0
    )
    returning action_id,security_id,ex_date,cash_amount_per_share,source_document_id,record_hash
)
insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    'cash_dividend',
    'corporate_action',
    i.action_id::text,
    ((i.ex_date-1)::timestamp at time zone 'Asia/Shanghai'),
    1,
    'active',
    array['AKSHARE_EASTMONEY_FINANCIAL'],
    array_remove(array[d.content_hash,i.record_hash],null),
    false,
    jsonb_build_object(
        'ex_date',i.ex_date,
        'cash_amount_per_share',i.cash_amount_per_share,
        'quality_reason','single derived source; official implementation announcement required'
    ),
    'eastmoney-dividend-candidate-v1'
from inserted i
left join raw.documents d on d.document_id=i.source_document_id;

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'warning','corporate_actions','pit.corporate_actions',
    '600519.SH|2021-2026|CASH_DIVIDENDS',
    'CORPORATE_ACTION_SECOND_SOURCE_REQUIRED',
    'Candidate cash dividends were normalized from a free derived source; each event requires official implementation-announcement reconciliation.',
    'open',
    jsonb_build_object(
        'candidate_action_count',count(*),
        'evidence_grade',1,
        'formal_use_allowed',false
    )
from pit.corporate_actions ca
join master.securities s on s.security_id=ca.security_id
where s.security_code='600519.SH'
  and ca.action_type='cash_dividend'
  and ca.ex_date between '2021-04-01'::date and '2026-04-01'::date
having count(*)>0
   and not exists (
       select 1 from audit.data_quality_issues q
       where q.rule_code='CORPORATE_ACTION_SECOND_SOURCE_REQUIRED'
         and q.record_key='600519.SH|2021-2026|CASH_DIVIDENDS'
         and q.status='open'
   );

commit;
