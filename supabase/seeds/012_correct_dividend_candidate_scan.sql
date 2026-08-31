begin;

with fields as (
    select distinct
        r.dataset_code,
        e.key as source_field
    from raw.records r
    join master.securities s on s.security_id = r.security_id
    cross join lateral jsonb_each(r.payload) e
    where s.security_code = '600519.SH'
      and (
          r.dataset_code like 'eastmoney_%dividend%'
          or r.dataset_code = 'eastmoney_sharebonus_det'
          or r.dataset_code = 'eastmoney_f10_bonusfinance'
      )
      and e.key ~* '(DIVIDEND|BONUS|CASH|EX_|RECORD|PAY|DATE|RATIO|TAX|IMPLEMENT|PLAN)'
), packed as (
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'dataset_code', dataset_code,
                'source_field', source_field
            ) order by dataset_code, source_field
        ),
        '[]'::jsonb
    ) as candidates
    from fields
)
update audit.data_quality_issues q
set details = jsonb_set(
        q.details,
        '{field_candidates}',
        packed.candidates,
        true
    ),
    detected_at = now()
from packed
where q.rule_code = 'CORPORATE_ACTION_FIELD_MAPPING_REVIEW_REQUIRED'
  and q.record_key = '600519.SH|DIVIDEND_FIELDS'
  and q.status = 'open';

commit;
