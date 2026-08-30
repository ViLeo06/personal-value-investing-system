begin;

do $$
declare
    v_model_id uuid;
    v_run_id uuid;
    v_issuer_id uuid;
    v_security_id uuid;
    v_snapshot_id uuid;
    v_membership_hash text;
    v_input_hash text;
    v_output_hash text;
begin
    select model_version_id into v_model_id
    from model.model_versions
    where model_name='owner_earnings_dcf' and semantic_version='0.1.0-gate0'
    order by created_at desc limit 1;

    if v_model_id is null then
        insert into model.model_versions
            (model_name,semantic_version,model_family,status,config_hash,effective_from,notes)
        values
            ('owner_earnings_dcf','0.1.0-gate0','owner_earnings_dcf','development',
             md5('owner_earnings_dcf|0.1.0-gate0|10y|5y-fade|three-scenario|shared-forward-reverse'),
             timestamptz '2021-04-01 00:00:00+08',
             'Gate-0 deterministic equity DCF. Owner earnings is temporarily the lower of parent net income and operating cash flow. Forward and reverse calculations share one cash-flow function.')
        returning model_version_id into v_model_id;
    end if;

    select issuer_id into v_issuer_id from master.issuers where issuer_code='KWEICHOW_MOUTAI';
    select security_id into v_security_id from master.securities where security_code='600519.SH';
    select snapshot_id,manifest->>'membership_hash' into v_snapshot_id,v_membership_hash
    from audit.data_snapshots
    where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
    order by created_at desc limit 1;

    v_input_hash:=md5(concat_ws('|',v_snapshot_id::text,coalesce(v_membership_hash,''),
                                 v_model_id::text,'moutai_gate0_scenarios_v1','gate0_v1'));

    select run_id into v_run_id
    from model.valuation_runs
    where issuer_id=v_issuer_id and security_id=v_security_id
      and as_of_at=timestamptz '2021-04-01 00:00:00+08'
      and model_version_id=v_model_id
      and scenario_set_version='moutai_gate0_scenarios_v1'
      and input_hash=v_input_hash
    order by created_at desc limit 1;

    if v_run_id is null then
        insert into model.valuation_runs
            (issuer_id,security_id,as_of_at,snapshot_id,model_version_id,
             scenario_set_version,status,started_at,input_hash)
        values
            (v_issuer_id,v_security_id,timestamptz '2021-04-01 00:00:00+08',
             v_snapshot_id,v_model_id,'moutai_gate0_scenarios_v1','running',now(),v_input_hash)
        returning run_id into v_run_id;
    else
        delete from model.reverse_dcf_results where run_id=v_run_id;
        delete from model.valuation_outputs where run_id=v_run_id;
        delete from model.run_assumptions where run_id=v_run_id;
        delete from audit.run_lineage where run_type='valuation' and run_id=v_run_id;
        update model.valuation_runs
        set status='running',started_at=now(),completed_at=null,output_hash=null,error_text=null
        where run_id=v_run_id;
    end if;

    insert into model.run_assumptions
        (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
    select v_run_id,'all',n.metric_code,n.value_numeric,n.unit,'normalized_fact',
           jsonb_build_object('normalized_fact_id',n.normalized_fact_id,
                              'normalization_version',n.normalization_version,
                              'available_at',n.available_at,'record_hash',n.record_hash)
    from fundamentals.normalized_facts n
    where n.issuer_id=v_issuer_id and n.period_end=date '2020-12-31'
      and n.normalization_version='gate0_v1'
      and n.metric_code in ('owner_earnings_proxy','shares_outstanding_proxy','owner_earnings_per_share_proxy');

    insert into model.run_assumptions
        (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
    select v_run_id,s.scenario,a.assumption_key,a.value_numeric,a.unit,'model',
           jsonb_build_object('scenario_set','moutai_gate0_scenarios_v1',
                              'status','prototype_not_investment_ready',
                              'rationale','Initial envelope for deterministic replay; requires historical base-rate calibration.')
    from (values
      ('pessimistic'::text,0.25::numeric,0.06::numeric,0.105::numeric,0.025::numeric),
      ('base'::text,0.50::numeric,0.10::numeric,0.090::numeric,0.030::numeric),
      ('optimistic'::text,0.25::numeric,0.13::numeric,0.080::numeric,0.035::numeric)
    ) s(scenario,probability,stage1_growth,discount_rate,terminal_growth)
    cross join lateral (values
      ('scenario_probability'::text,s.probability,'ratio'::text),
      ('stage1_growth',s.stage1_growth,'ratio'),
      ('discount_rate',s.discount_rate,'ratio'),
      ('terminal_growth',s.terminal_growth,'ratio'),
      ('forecast_horizon_years',10::numeric,'years'),
      ('stage1_years',5::numeric,'years'),
      ('required_return_hurdle',0.15::numeric,'ratio')
    ) a(assumption_key,value_numeric,unit);

    create temporary table if not exists _gate0_scenario_outputs (
      scenario text primary key,probability numeric not null,discount_rate numeric not null,
      terminal_growth numeric not null,year1_cf numeric not null,year5_cf numeric not null,
      year10_cf numeric not null,pv_explicit numeric not null,pv_terminal numeric not null,
      equity_value numeric not null,hurdle_value numeric not null,shares numeric not null
    ) on commit drop;
    truncate _gate0_scenario_outputs;

    insert into _gate0_scenario_outputs
    with recursive
    base_metrics as (
      select max(value_numeric) filter(where metric_code='owner_earnings_proxy') as oe0,
             max(value_numeric) filter(where metric_code='shares_outstanding_proxy') as shares
      from fundamentals.normalized_facts
      where issuer_id=v_issuer_id and period_end=date '2020-12-31'
        and normalization_version='gate0_v1'
    ), scenarios as (
      select * from (values
        ('pessimistic'::text,0.25::numeric,0.06::numeric,0.105::numeric,0.025::numeric),
        ('base'::text,0.50::numeric,0.10::numeric,0.090::numeric,0.030::numeric),
        ('optimistic'::text,0.25::numeric,0.13::numeric,0.080::numeric,0.035::numeric)
      ) v(scenario,probability,stage1_growth,discount_rate,terminal_growth)
    ), cf as (
      select s.scenario,s.probability,s.stage1_growth,s.discount_rate,s.terminal_growth,
             1 as forecast_year,b.oe0*(1+s.stage1_growth) as cash_flow,b.shares
      from scenarios s cross join base_metrics b
      union all
      select c.scenario,c.probability,c.stage1_growth,c.discount_rate,c.terminal_growth,
             c.forecast_year+1,
             c.cash_flow*(1+case when c.forecast_year+1<=5 then c.stage1_growth
               else c.stage1_growth+(c.terminal_growth-c.stage1_growth)
                    *((c.forecast_year+1)-5)::numeric/5::numeric end),c.shares
      from cf c where c.forecast_year<10
    ), agg as (
      select scenario,probability,discount_rate,terminal_growth,shares,
             max(cash_flow) filter(where forecast_year=1) as year1_cf,
             max(cash_flow) filter(where forecast_year=5) as year5_cf,
             max(cash_flow) filter(where forecast_year=10) as year10_cf,
             sum(cash_flow/power(1+discount_rate,forecast_year)) as pv_explicit,
             max(cash_flow) filter(where forecast_year=10)*(1+terminal_growth)
               /nullif(discount_rate-terminal_growth,0)/power(1+discount_rate,10) as pv_terminal,
             sum(cash_flow/power(1+0.15::numeric,forecast_year))
               +(max(cash_flow) filter(where forecast_year=10)*(1+terminal_growth)
                 /nullif(0.15::numeric-terminal_growth,0)/power(1+0.15::numeric,10)) as hurdle_value
      from cf group by scenario,probability,discount_rate,terminal_growth,shares
    )
    select scenario,probability,discount_rate,terminal_growth,year1_cf,year5_cf,year10_cf,
           pv_explicit,pv_terminal,pv_explicit+pv_terminal,hurdle_value,shares from agg;

    insert into model.valuation_outputs
        (run_id,scenario,output_key,value_numeric,unit,metadata)
    select v_run_id,o.scenario,x.output_key,x.value_numeric,x.unit,
           jsonb_build_object('model_version','0.1.0-gate0',
                              'scenario_set','moutai_gate0_scenarios_v1',
                              'prototype',true,'uses_shared_cashflow_engine',true)
    from _gate0_scenario_outputs o
    cross join lateral (values
      ('year_1_owner_earnings'::text,o.year1_cf,'CNY'::text),
      ('year_5_owner_earnings',o.year5_cf,'CNY'),
      ('year_10_owner_earnings',o.year10_cf,'CNY'),
      ('pv_explicit_period',o.pv_explicit,'CNY'),
      ('pv_terminal',o.pv_terminal,'CNY'),
      ('equity_value',o.equity_value,'CNY'),
      ('intrinsic_value_per_share',o.equity_value/nullif(o.shares,0),'CNY/share'),
      ('terminal_value_share',o.pv_terminal/nullif(o.equity_value,0),'ratio'),
      ('hurdle_15_value',o.hurdle_value,'CNY'),
      ('hurdle_15_value_per_share',o.hurdle_value/nullif(o.shares,0),'CNY/share')
    ) x(output_key,value_numeric,unit);

    insert into model.valuation_outputs
        (run_id,scenario,output_key,value_numeric,unit,metadata)
    select v_run_id,'probability_weighted',output_key,
           sum(value_numeric*probability),unit,
           jsonb_build_object('method','scenario_probability_weighting','prototype',true)
    from (
      select o.probability,vo.output_key,vo.value_numeric,vo.unit
      from _gate0_scenario_outputs o
      join model.valuation_outputs vo on vo.run_id=v_run_id and vo.scenario=o.scenario
      where vo.output_key in ('intrinsic_value_per_share','hurdle_15_value_per_share','terminal_value_share')
    ) q group by output_key,unit;

    select md5(string_agg(concat_ws('|',scenario,output_key,value_numeric::text,coalesce(unit,'')),
                          '||' order by scenario,output_key))
    into v_output_hash from model.valuation_outputs where run_id=v_run_id;

    update model.valuation_runs
    set status='completed_prototype',completed_at=now(),output_hash=v_output_hash
    where run_id=v_run_id;

    insert into audit.run_lineage
        (run_type,run_id,input_type,input_id,input_hash,metadata)
    values
      ('valuation',v_run_id,'audit.data_snapshots',v_snapshot_id::text,v_membership_hash,
       jsonb_build_object('role','frozen_input_snapshot')),
      ('valuation',v_run_id,'model.model_versions',v_model_id::text,
       md5('owner_earnings_dcf|0.1.0-gate0|10y|5y-fade|three-scenario|shared-forward-reverse'),
       jsonb_build_object('role','calculation_contract'));

    insert into audit.run_lineage
        (run_type,run_id,input_type,input_id,input_hash,metadata)
    select 'valuation',v_run_id,'fundamentals.normalized_facts',n.normalized_fact_id::text,
           n.record_hash,jsonb_build_object('metric_code',n.metric_code,'role','valuation_input')
    from fundamentals.normalized_facts n
    where n.issuer_id=v_issuer_id and n.period_end=date '2020-12-31'
      and n.normalization_version='gate0_v1'
      and n.metric_code in ('owner_earnings_proxy','shares_outstanding_proxy','owner_earnings_per_share_proxy');
end $$;

commit;
