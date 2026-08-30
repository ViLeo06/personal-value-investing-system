begin;

-- Defensive data-quality constraints for point-in-time facts.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'financial_facts_exactly_one_value_chk'
      and conrelid = 'pit.financial_facts'::regclass
  ) then
    alter table pit.financial_facts
      add constraint financial_facts_exactly_one_value_chk
      check (num_nonnulls(value_numeric, value_text) = 1) not valid;
    alter table pit.financial_facts
      validate constraint financial_facts_exactly_one_value_chk;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'financial_facts_available_after_publish_chk'
      and conrelid = 'pit.financial_facts'::regclass
  ) then
    alter table pit.financial_facts
      add constraint financial_facts_available_after_publish_chk
      check (published_at is null or available_at >= published_at) not valid;
    alter table pit.financial_facts
      validate constraint financial_facts_available_after_publish_chk;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'market_bars_nonnegative_chk'
      and conrelid = 'pit.market_bars'::regclass
  ) then
    alter table pit.market_bars
      add constraint market_bars_nonnegative_chk
      check (
        (open_price is null or open_price >= 0) and
        (high_price is null or high_price >= 0) and
        (low_price is null or low_price >= 0) and
        (close_price is null or close_price >= 0) and
        (previous_close is null or previous_close >= 0) and
        (volume is null or volume >= 0) and
        (turnover is null or turnover >= 0)
      ) not valid;
    alter table pit.market_bars
      validate constraint market_bars_nonnegative_chk;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'corporate_actions_available_after_announce_chk'
      and conrelid = 'pit.corporate_actions'::regclass
  ) then
    alter table pit.corporate_actions
      add constraint corporate_actions_available_after_announce_chk
      check (announced_at is null or available_at >= announced_at) not valid;
    alter table pit.corporate_actions
      validate constraint corporate_actions_available_after_announce_chk;
  end if;
end
$$;

create index if not exists financial_facts_latest_lookup_idx
  on pit.financial_facts (
    issuer_id,
    statement_type,
    period_end,
    metric_code,
    available_at desc,
    revision_no desc,
    fact_id desc
  );

create index if not exists market_bars_asof_lookup_idx
  on pit.market_bars (
    security_id,
    trade_date,
    available_at desc,
    bar_id desc
  );

create index if not exists corporate_actions_asof_lookup_idx
  on pit.corporate_actions (
    security_id,
    available_at desc,
    ex_date,
    effective_date
  );

create unique index if not exists data_snapshots_snapshot_hash_uq
  on audit.data_snapshots(snapshot_hash);

create or replace function pit.financial_facts_as_of(
  p_issuer_id uuid,
  p_as_of_at timestamptz,
  p_statement_type text default null,
  p_period_end date default null
)
returns setof pit.financial_facts
language sql
stable
security invoker
set search_path = ''
as $$
  with ranked as (
    select
      ff.fact_id,
      row_number() over (
        partition by
          ff.issuer_id,
          ff.statement_scope,
          ff.statement_type,
          ff.metric_code,
          ff.period_start,
          ff.period_end,
          ff.fiscal_period,
          ff.fact_kind,
          coalesce(ff.metadata ->> 'dimension_key', '')
        order by
          coalesce(ds.priority, 32767) asc,
          ff.is_preliminary asc,
          ff.available_at desc,
          ff.revision_no desc,
          ff.ingested_at desc,
          ff.fact_id desc
      ) as rn
    from pit.financial_facts ff
    left join raw.documents d
      on d.document_id = ff.source_document_id
    left join raw.data_sources ds
      on ds.source_id = d.source_id
    where ff.issuer_id = p_issuer_id
      and ff.available_at <= p_as_of_at
      and (p_statement_type is null or ff.statement_type = p_statement_type)
      and (p_period_end is null or ff.period_end = p_period_end)
  )
  select ff.*
  from pit.financial_facts ff
  join ranked r on r.fact_id = ff.fact_id
  where r.rn = 1
  order by ff.period_end, ff.statement_type, ff.metric_code;
$$;

create or replace function pit.market_bars_as_of(
  p_security_id uuid,
  p_as_of_at timestamptz,
  p_start_date date default null,
  p_end_date date default null
)
returns setof pit.market_bars
language sql
stable
security invoker
set search_path = ''
as $$
  with ranked as (
    select
      mb.bar_id,
      row_number() over (
        partition by mb.security_id, mb.trade_date
        order by
          coalesce(ds.priority, 32767) asc,
          mb.available_at desc,
          mb.ingested_at desc,
          mb.bar_id desc
      ) as rn
    from pit.market_bars mb
    left join raw.data_sources ds
      on ds.source_id = mb.source_id
    where mb.security_id = p_security_id
      and mb.available_at <= p_as_of_at
      and (p_start_date is null or mb.trade_date >= p_start_date)
      and (p_end_date is null or mb.trade_date <= p_end_date)
  )
  select mb.*
  from pit.market_bars mb
  join ranked r on r.bar_id = mb.bar_id
  where r.rn = 1
  order by mb.trade_date;
$$;

create or replace function pit.corporate_actions_as_of(
  p_security_id uuid,
  p_as_of_at timestamptz,
  p_start_date date default null,
  p_end_date date default null
)
returns setof pit.corporate_actions
language sql
stable
security invoker
set search_path = ''
as $$
  select ca.*
  from pit.corporate_actions ca
  where ca.security_id = p_security_id
    and ca.available_at <= p_as_of_at
    and (
      p_start_date is null or
      coalesce(ca.ex_date, ca.effective_date, ca.record_date, ca.payment_date) >= p_start_date
    )
    and (
      p_end_date is null or
      coalesce(ca.ex_date, ca.effective_date, ca.record_date, ca.payment_date) <= p_end_date
    )
  order by
    coalesce(ca.ex_date, ca.effective_date, ca.record_date, ca.payment_date),
    ca.action_type,
    ca.action_id;
$$;

-- Internal research schemas stay non-public. Functions are invoker-rights and not callable by API roles.
revoke all on function pit.financial_facts_as_of(uuid, timestamptz, text, date)
  from public, anon, authenticated;
revoke all on function pit.market_bars_as_of(uuid, timestamptz, date, date)
  from public, anon, authenticated;
revoke all on function pit.corporate_actions_as_of(uuid, timestamptz, date, date)
  from public, anon, authenticated;

commit;
