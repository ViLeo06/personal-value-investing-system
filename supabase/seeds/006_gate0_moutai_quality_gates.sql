begin;

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select x.severity,x.domain,x.table_name,x.record_key,x.rule_code,x.description,'open',x.details
from (values
  ('high'::text,'fundamentals','fundamentals.normalized_facts','KWEICHOW_MOUTAI|2020-12-31','OE_PROXY_MISSING_MAINTENANCE_CAPEX',
   'Owner earnings currently uses the lower of parent net income and operating cash flow because maintenance capital expenditure is not yet separated.',
   jsonb_build_object('blocks','investment_ready','required_next','load capex history and define maintenance versus growth capex')),
  ('critical','market_data','pit.market_bars','600519.SH|2021-04-01','DECISION_PRICE_NOT_LOADED',
   'The unadjusted market close at the historical decision timestamp is not yet source-verified; Reverse DCF, market expectations and expected IRR remain blocked.',
   jsonb_build_object('blocks',jsonb_build_array('reverse_dcf','market_expectations','decision'))),
  ('high','corporate_actions','pit.corporate_actions','600519.SH|2021-2026','CORPORATE_ACTION_LEDGER_INCOMPLETE',
   'Cash dividends and other corporate actions required for exact five-year total return are not yet loaded.',
   jsonb_build_object('blocks','phase_b_total_return')),
  ('medium','fundamentals','pit.financial_facts','KWEICHOW_MOUTAI|history','HISTORY_DEPTH_INSUFFICIENT',
   'Only a six-fact 2020 annual-report prototype is frozen; the multi-year history and restatement chain are incomplete.',
   jsonb_build_object('required_years','at least 10 where available','blocks','base_rate_calibration')),
  ('medium','evidence','raw.documents','KWEICHOW_MOUTAI|2020_ANNUAL_REPORT','SOURCE_BINARY_NOT_ARCHIVED',
   'The numeric Gate-0 extract is registered, but the exact official report binary and byte hash must be archived before evidence-complete status.',
   jsonb_build_object('blocks','evidence_complete','required_next','archive official PDF and replace provisional content hash'))
) x(severity,domain,table_name,record_key,rule_code,description,details)
where not exists (
  select 1 from audit.data_quality_issues d
  where d.rule_code=x.rule_code and d.record_key=x.record_key and d.status='open'
);

commit;
