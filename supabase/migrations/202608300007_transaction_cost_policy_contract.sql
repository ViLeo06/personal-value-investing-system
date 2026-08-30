begin;

create table if not exists backtest.transaction_cost_policies (
    policy_component_id uuid primary key default gen_random_uuid(),
    policy_version text not null,
    market_code text not null,
    security_type text not null default 'equity',
    side text not null,
    component_code text not null,
    valid_from date not null,
    valid_to date,
    rate numeric not null default 0,
    minimum_amount numeric not null default 0,
    maximum_amount numeric,
    currency text not null,
    source_kind text not null,
    source_document_id uuid references raw.documents(document_id),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint transaction_cost_policies_side_chk
      check (side in ('buy','sell','both')),
    constraint transaction_cost_policies_dates_chk
      check (valid_to is null or valid_to>=valid_from),
    constraint transaction_cost_policies_rates_chk
      check (rate>=0 and minimum_amount>=0
             and (maximum_amount is null or maximum_amount>=minimum_amount)),
    unique(policy_version,market_code,security_type,side,component_code,valid_from)
);

create index if not exists transaction_cost_policy_lookup_idx
  on backtest.transaction_cost_policies(market_code,security_type,valid_from,valid_to,side);

revoke all on table backtest.transaction_cost_policies from anon,authenticated;

commit;
