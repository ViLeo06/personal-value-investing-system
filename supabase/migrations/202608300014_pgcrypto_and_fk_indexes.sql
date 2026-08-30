begin;

-- The clean-room PostgreSQL bootstrap must provide the same hashing primitive
-- used by Supabase.  Supabase projects normally have pgcrypto available, while
-- a stock postgres:17 image does not.
create extension if not exists pgcrypto;

-- Cover foreign keys used by audit lineage, execution and segment queries.
create index if not exists experiment_plan_decisions_security_idx
    on audit.experiment_plan_decisions(security_id);
create index if not exists experiment_plans_supersedes_idx
    on audit.experiment_plans(supersedes_plan_id);
create index if not exists run_quality_results_rule_set_idx
    on audit.run_quality_results(quality_rule_set_id);
create index if not exists run_readiness_rule_set_idx
    on audit.run_readiness(quality_rule_set_id);

create index if not exists cash_ledger_action_idx
    on backtest.cash_ledger(action_id);
create index if not exists cash_ledger_order_idx
    on backtest.cash_ledger(order_id);
create index if not exists cash_ledger_transaction_idx
    on backtest.cash_ledger(transaction_id);
create index if not exists orders_decision_idx
    on backtest.orders(decision_id);
create index if not exists outcome_revisions_supersedes_idx
    on backtest.outcome_revisions(supersedes_revision_id);

create index if not exists normalized_segment_facts_segment_idx
    on fundamentals.normalized_segment_facts(segment_id);

create index if not exists business_segments_parent_idx
    on master.business_segments(parent_segment_id);
create index if not exists business_segments_source_document_idx
    on master.business_segments(source_document_id);
create index if not exists exchange_cost_rules_source_document_idx
    on master.exchange_cost_rules(source_document_id);
create index if not exists security_trading_terms_source_document_idx
    on master.security_trading_terms(source_document_id);

create index if not exists segment_facts_segment_idx
    on pit.segment_facts(segment_id);
create index if not exists segment_facts_source_document_idx
    on pit.segment_facts(source_document_id);
create index if not exists share_class_facts_source_document_idx
    on pit.share_class_facts(source_document_id);

commit;
