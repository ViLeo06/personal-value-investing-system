begin;

create table master.exchange_cost_rules (
    rule_id uuid primary key default gen_random_uuid(),
    exchange_mic text not null,
    security_type text not null default 'equity',
    valid_from date not null,
    valid_to date,
    settlement_days smallint not null default 1
        check (settlement_days >= 0),
    buy_commission_rate numeric not null default 0
        check (buy_commission_rate >= 0),
    sell_commission_rate numeric not null default 0
        check (sell_commission_rate >= 0),
    minimum_commission numeric not null default 0
        check (minimum_commission >= 0),
    buy_tax_rate numeric not null default 0
        check (buy_tax_rate >= 0),
    sell_tax_rate numeric not null default 0
        check (sell_tax_rate >= 0),
    transfer_fee_rate numeric not null default 0
        check (transfer_fee_rate >= 0),
    currency text not null,
    source_document_id uuid references raw.documents(document_id),
    rule_hash text not null unique,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint exchange_cost_rules_validity_check
        check (valid_to is null or valid_to >= valid_from),
    unique (exchange_mic, security_type, valid_from)
);

create table master.security_trading_terms (
    term_id uuid primary key default gen_random_uuid(),
    security_id uuid not null references master.securities(security_id),
    valid_from date not null,
    valid_to date,
    board_lot numeric not null default 1 check (board_lot > 0),
    minimum_price_increment numeric
        check (minimum_price_increment is null or minimum_price_increment > 0),
    source_document_id uuid references raw.documents(document_id),
    term_hash text not null unique,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint security_trading_terms_validity_check
        check (valid_to is null or valid_to >= valid_from),
    unique (security_id, valid_from)
);

create table backtest.orders (
    order_id uuid primary key default gen_random_uuid(),
    backtest_run_id uuid not null
        references backtest.backtest_runs(backtest_run_id) on delete cascade,
    decision_id uuid references backtest.decision_events(decision_id),
    security_id uuid not null references master.securities(security_id),
    submitted_at timestamptz not null,
    side text not null check (side in ('buy','sell')),
    order_type text not null default 'market'
        check (order_type in ('market','limit','close','open')),
    requested_quantity numeric not null check (requested_quantity >= 0),
    limit_price numeric check (limit_price is null or limit_price >= 0),
    target_weight numeric,
    status text not null default 'submitted'
        check (status in ('submitted','partially_filled','filled','cancelled','rejected')),
    order_payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

alter table backtest.transactions
    add column if not exists order_id uuid references backtest.orders(order_id),
    add column if not exists action_id uuid references pit.corporate_actions(action_id),
    add column if not exists executed_at timestamptz,
    add column if not exists settlement_date date,
    add column if not exists gross_value numeric,
    add column if not exists taxes numeric not null default 0,
    add column if not exists transaction_payload jsonb not null default '{}'::jsonb;

alter table backtest.transactions
    drop constraint if exists transactions_taxes_check,
    add constraint transactions_taxes_check check (taxes >= 0),
    drop constraint if exists transactions_gross_value_check,
    add constraint transactions_gross_value_check
        check (gross_value is null or gross_value >= 0);

create table backtest.cash_ledger (
    cash_entry_id bigint generated always as identity primary key,
    backtest_run_id uuid not null
        references backtest.backtest_runs(backtest_run_id) on delete cascade,
    event_at timestamptz not null,
    settlement_date date,
    entry_type text not null check (entry_type in (
        'initial_capital',
        'trade_principal',
        'fee',
        'tax',
        'dividend',
        'corporate_action',
        'fx_conversion',
        'interest',
        'other'
    )),
    security_id uuid references master.securities(security_id),
    order_id uuid references backtest.orders(order_id),
    transaction_id bigint references backtest.transactions(transaction_id),
    action_id uuid references pit.corporate_actions(action_id),
    currency text not null,
    amount numeric not null,
    entry_hash text not null unique,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index exchange_cost_rules_asof_idx
    on master.exchange_cost_rules(exchange_mic, security_type, valid_from, valid_to);
create index security_trading_terms_asof_idx
    on master.security_trading_terms(security_id, valid_from, valid_to);
create index orders_run_submitted_idx
    on backtest.orders(backtest_run_id, submitted_at);
create index orders_security_submitted_idx
    on backtest.orders(security_id, submitted_at);
create index transactions_order_idx
    on backtest.transactions(order_id);
create index transactions_action_idx
    on backtest.transactions(action_id);
create index cash_ledger_run_event_idx
    on backtest.cash_ledger(backtest_run_id, event_at);
create index cash_ledger_security_event_idx
    on backtest.cash_ledger(security_id, event_at);

revoke all privileges on master.exchange_cost_rules,
    master.security_trading_terms,
    backtest.orders,
    backtest.cash_ledger from anon, authenticated;
revoke all privileges on sequence backtest.cash_ledger_cash_entry_id_seq
    from anon, authenticated;

commit;
