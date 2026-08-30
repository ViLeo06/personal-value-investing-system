begin;

insert into backtest.transaction_cost_policies
  (policy_version,market_code,security_type,side,component_code,valid_from,valid_to,
   rate,minimum_amount,currency,source_kind,metadata)
values
  ('a_share_cash_equity_v1','XSHG','equity','both','broker_commission',date '2000-01-01',null,
   0.0003,5,'CNY','model_assumption',
   jsonb_build_object('status','configurable_default','requires_user_broker_override',true)),
  ('a_share_cash_equity_v1','XSHG','equity','both','transfer_fee',date '2008-09-19',date '2022-04-28',
   0.00002,0,'CNY','regulatory_rule',
   jsonb_build_object('verification_status','official_source_archive_pending')),
  ('a_share_cash_equity_v1','XSHG','equity','both','transfer_fee',date '2022-04-29',null,
   0.00001,0,'CNY','regulatory_rule',
   jsonb_build_object('verification_status','official_source_archive_pending')),
  ('a_share_cash_equity_v1','XSHG','equity','sell','stamp_duty',date '2008-09-19',date '2023-08-27',
   0.001,0,'CNY','regulatory_rule',
   jsonb_build_object('verification_status','official_source_archive_pending')),
  ('a_share_cash_equity_v1','XSHG','equity','sell','stamp_duty',date '2023-08-28',null,
   0.0005,0,'CNY','regulatory_rule',
   jsonb_build_object('verification_status','official_source_archive_pending')),
  ('a_share_etf_v1','XSHG','etf','both','broker_commission',date '2000-01-01',null,
   0.0003,5,'CNY','model_assumption',
   jsonb_build_object('status','configurable_default','requires_user_broker_override',true,
                      'stamp_duty_assumption','not applicable to exchange-traded fund units'))
on conflict (policy_version,market_code,security_type,side,component_code,valid_from) do update
set valid_to=excluded.valid_to,rate=excluded.rate,minimum_amount=excluded.minimum_amount,
    currency=excluded.currency,source_kind=excluded.source_kind,metadata=excluded.metadata;

commit;
