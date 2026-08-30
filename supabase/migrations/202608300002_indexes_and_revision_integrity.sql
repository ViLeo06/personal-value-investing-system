begin;

-- Preserve source corrections/revisions instead of forcing destructive updates.
alter table pit.market_bars
    drop constraint if exists market_bars_security_id_trade_date_source_id_key;
create unique index if not exists market_bars_source_version_uq
    on pit.market_bars(security_id, trade_date, source_id, available_at);

alter table pit.fx_rates
    drop constraint if exists fx_rates_base_currency_quote_currency_rate_date_rate_type_source_id_key;
create unique index if not exists fx_rates_source_version_uq
    on pit.fx_rates(base_currency, quote_currency, rate_date, rate_type, source_id, available_at);

-- Cover foreign keys used by joins, deletes and lineage lookups.
create index if not exists security_identifiers_security_idx
    on master.security_identifiers(security_id);

create index if not exists ingestion_batches_source_idx
    on raw.ingestion_batches(source_id);
create index if not exists documents_source_idx
    on raw.documents(source_id);
create index if not exists documents_batch_idx
    on raw.documents(batch_id);

create index if not exists financial_facts_source_document_idx
    on pit.financial_facts(source_document_id);
create index if not exists market_bars_source_idx
    on pit.market_bars(source_id);
create index if not exists market_bars_batch_idx
    on pit.market_bars(batch_id);
create index if not exists corporate_actions_source_document_idx
    on pit.corporate_actions(source_document_id);
create index if not exists fx_rates_source_idx
    on pit.fx_rates(source_id);
create index if not exists fx_rates_batch_idx
    on pit.fx_rates(batch_id);
create index if not exists macro_observations_source_idx
    on pit.macro_observations(source_id);
create index if not exists macro_observations_batch_idx
    on pit.macro_observations(batch_id);

create index if not exists normalized_facts_metric_idx
    on fundamentals.normalized_facts(metric_code);
create index if not exists fact_lineage_source_fact_idx
    on fundamentals.fact_lineage(source_fact_id);
create index if not exists adjustments_issuer_idx
    on fundamentals.adjustments(issuer_id);
create index if not exists adjustments_source_document_idx
    on fundamentals.adjustments(source_document_id);

create index if not exists valuation_runs_security_idx
    on model.valuation_runs(security_id);
create index if not exists valuation_runs_snapshot_idx
    on model.valuation_runs(snapshot_id);
create index if not exists valuation_runs_model_version_idx
    on model.valuation_runs(model_version_id);
create index if not exists reverse_dcf_results_run_idx
    on model.reverse_dcf_results(run_id);

create index if not exists universes_benchmark_security_idx
    on backtest.universes(benchmark_security_id);
create index if not exists universe_memberships_security_idx
    on backtest.universe_memberships(security_id);
create index if not exists universe_memberships_source_document_idx
    on backtest.universe_memberships(source_document_id);
create index if not exists backtest_runs_universe_idx
    on backtest.backtest_runs(universe_id);
create index if not exists backtest_runs_model_version_idx
    on backtest.backtest_runs(model_version_id);
create index if not exists decision_events_issuer_idx
    on backtest.decision_events(issuer_id);
create index if not exists decision_events_security_idx
    on backtest.decision_events(security_id);
create index if not exists decision_events_valuation_run_idx
    on backtest.decision_events(valuation_run_id);
create index if not exists transactions_run_idx
    on backtest.transactions(backtest_run_id);
create index if not exists transactions_decision_idx
    on backtest.transactions(decision_id);
create index if not exists transactions_security_idx
    on backtest.transactions(security_id);
create index if not exists position_snapshots_security_idx
    on backtest.position_snapshots(security_id);

commit;
