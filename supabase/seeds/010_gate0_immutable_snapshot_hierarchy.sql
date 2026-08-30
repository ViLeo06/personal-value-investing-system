begin;

do $$
declare
  v_financial_snapshot_id uuid;
  v_phase_a_snapshot_id uuid;
  v_phase_a_hash text:=md5('KWEICHOW_MOUTAI|600519.SH|2021-04-01T00:00:00+08:00|phase_a_full|v1');
  v_market_bar_id bigint;
  v_membership_hash text;
  v_item_count integer;
begin
  select snapshot_id into v_financial_snapshot_id
  from audit.data_snapshots
  where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
  order by created_at desc limit 1;
  if v_financial_snapshot_id is null then raise exception 'financial snapshot missing'; end if;
  if (select is_frozen from audit.data_snapshots where snapshot_id=v_financial_snapshot_id) then
    return;
  end if;

  delete from audit.snapshot_items
  where snapshot_id=v_financial_snapshot_id and input_type='pit.market_bars';

  select count(*)::int,
         md5(string_agg(concat_ws('|',input_type,input_key,coalesce(input_hash,'')),
                        '||' order by input_type,input_key))
    into v_item_count,v_membership_hash
  from audit.snapshot_items where snapshot_id=v_financial_snapshot_id;
  if v_item_count<>7 then raise exception 'financial snapshot expected 7 items, found %',v_item_count; end if;

  update audit.data_snapshots
  set snapshot_kind='financial_evidence',parent_snapshot_id=null,
      manifest=manifest || jsonb_build_object(
        'scope','prototype_financial_evidence_only','snapshot_item_count',v_item_count,
        'membership_hash',v_membership_hash,'membership_hash_version','stable_input_key_v1',
        'membership_materialized',true,'immutable_snapshot_contract','v1'),
      notes='One annual-report evidence record plus six 2020 financial facts.'
  where snapshot_id=v_financial_snapshot_id;

  select snapshot_id into v_phase_a_snapshot_id
  from audit.data_snapshots where snapshot_hash=v_phase_a_hash
  order by created_at desc limit 1;
  if v_phase_a_snapshot_id is null then
    insert into audit.data_snapshots
      (as_of_at,cutoff_policy_version,manifest,snapshot_hash,snapshot_kind,parent_snapshot_id,
       is_frozen,notes)
    select as_of_at,cutoff_policy_version,
           jsonb_build_object(
             'issuer_code','KWEICHOW_MOUTAI','security_code','600519.SH',
             'decision_cutoff','2021-04-01T00:00:00+08:00',
             'eligible_rule','available_at <= decision_cutoff','scope','prototype_phase_a_inputs',
             'parent_snapshot_hash','9950df576f62d3a87aac8b7ee276a173',
             'market_price_policy','last completed unadjusted close available at signal cutoff',
             'market_price_trade_date','2021-03-31'),
           v_phase_a_hash,'phase_a_full',v_financial_snapshot_id,false,
           'Financial evidence snapshot plus the frozen market-expectation target price.'
    from audit.data_snapshots where snapshot_id=v_financial_snapshot_id
    returning snapshot_id into v_phase_a_snapshot_id;
  end if;

  delete from audit.snapshot_items where snapshot_id=v_phase_a_snapshot_id;
  insert into audit.snapshot_items
    (snapshot_id,input_type,input_id,input_key,input_hash,source_available_at,metadata)
  select v_phase_a_snapshot_id,input_type,input_id,input_key,input_hash,source_available_at,
         metadata || jsonb_build_object('inherited_from_snapshot_id',v_financial_snapshot_id)
  from audit.snapshot_items where snapshot_id=v_financial_snapshot_id;

  select mb.bar_id into v_market_bar_id
  from pit.market_bars mb join master.securities s using(security_id)
  join raw.data_sources src on src.source_id=mb.source_id
  where s.security_code='600519.SH' and mb.trade_date=date '2021-03-31'
    and src.source_code='EASTMONEY_PUBLIC_API'
    and mb.available_at<=timestamptz '2021-04-01 00:00:00+08'
  order by mb.ingested_at desc limit 1;
  if v_market_bar_id is null then raise exception 'Phase-A target market bar missing'; end if;

  insert into audit.snapshot_items
    (snapshot_id,input_type,input_id,input_key,input_hash,source_available_at,metadata)
  select v_phase_a_snapshot_id,'pit.market_bars',mb.bar_id::text,
         '600519.SH|2021-03-31|unadjusted|EASTMONEY_PUBLIC_API',mb.record_hash,mb.available_at,
         jsonb_build_object('role','market_expectation_target','price_field','close_price',
                            'trade_date',mb.trade_date,'adjustment','unadjusted')
  from pit.market_bars mb where mb.bar_id=v_market_bar_id;

  select count(*)::int,
         md5(string_agg(concat_ws('|',input_type,input_key,coalesce(input_hash,'')),
                        '||' order by input_type,input_key))
    into v_item_count,v_membership_hash
  from audit.snapshot_items where snapshot_id=v_phase_a_snapshot_id;
  if v_item_count<>8 then raise exception 'full Phase-A snapshot expected 8 items, found %',v_item_count; end if;

  update audit.data_snapshots
  set manifest=manifest || jsonb_build_object(
        'snapshot_item_count',v_item_count,'membership_hash',v_membership_hash,
        'membership_hash_version','stable_input_key_v1','membership_materialized',true,
        'immutable_snapshot_contract','v1')
  where snapshot_id=v_phase_a_snapshot_id;

  update model.valuation_runs vr
  set snapshot_id=v_phase_a_snapshot_id,
      input_hash=md5(concat_ws('|',v_phase_a_snapshot_id::text,v_membership_hash,
                               vr.model_version_id::text,vr.scenario_set_version,'gate0_v1'))
  from master.issuers i
  where vr.issuer_id=i.issuer_id and i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1';

  update audit.run_lineage rl
  set input_id=v_phase_a_snapshot_id::text,input_hash=v_membership_hash,
      metadata=rl.metadata || jsonb_build_object(
        'role','frozen_phase_a_snapshot','snapshot_kind','phase_a_full',
        'membership_hash_version','stable_input_key_v1')
  from model.valuation_runs vr join master.issuers i on i.issuer_id=vr.issuer_id
  where rl.run_type='valuation' and rl.run_id=vr.run_id
    and rl.input_type='audit.data_snapshots'
    and i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1';

  update audit.data_snapshots set is_frozen=true,frozen_at=now()
  where snapshot_id in (v_financial_snapshot_id,v_phase_a_snapshot_id);
end $$;

commit;
