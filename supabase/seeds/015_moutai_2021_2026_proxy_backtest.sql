begin;

insert into backtest.universes
    (universe_id,universe_code,name,description,construction_policy_version)
values
    ('eb2b9070-2860-4a2f-b780-2d3c2f0f0101'::uuid,
     'GATE0_MOUTAI_SINGLE',
     'Gate 0 Moutai single-security validation universe',
     'Engineering validation only. Not a strategy-performance claim.',
     'gate0-single-security-v1')
on conflict (universe_id) do nothing;

insert into backtest.universe_memberships
    (universe_id,security_id,valid_from,valid_to,eligibility_reason)
select
    'eb2b9070-2860-4a2f-b780-2d3c2f0f0101'::uuid,
    s.security_id,
    '2021-04-01'::date,
    '2026-04-01'::date,
    jsonb_build_object(
        'purpose','Gate 0 replay validation',
        'selection','predefined validation company',
        'not_strategy_universe',true
    )
from master.securities s
where s.security_code='600519.SH'
  and not exists (
      select 1 from backtest.universe_memberships m
      where m.universe_id='eb2b9070-2860-4a2f-b780-2d3c2f0f0101'::uuid
        and m.security_id=s.security_id
        and m.valid_from='2021-04-01'::date
  );

with prerequisites as (
    select
        i.issuer_id,
        s.security_id,
        mv.model_version_id,
        vr.run_id as valuation_run_id,
        max(a.value_numeric) filter(where a.assumption_key='execution_open_price') as entry_price,
        (select count(*)
         from pit.market_bars mb
         where mb.security_id=s.security_id
           and mb.trade_date between '2021-04-01'::date and '2026-04-01'::date) as bar_count,
        (select count(*)
         from pit.corporate_actions ca
         where ca.security_id=s.security_id
           and ca.action_type='cash_dividend'
           and ca.ex_date between '2021-04-01'::date and '2026-04-01'::date) as action_count
    from master.issuers i
    join master.securities s on s.issuer_id=i.issuer_id and s.security_code='600519.SH'
    join model.valuation_runs vr on vr.run_id='40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
    join model.model_versions mv on mv.model_version_id=vr.model_version_id
    left join model.run_assumptions a
      on a.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
     and a.scenario='control'
     and a.assumption_key='execution_open_price'
    where i.issuer_code='KWEICHOW_MOUTAI'
    group by i.issuer_id,s.security_id,mv.model_version_id,vr.run_id
), inserted_run as (
    insert into backtest.backtest_runs
        (backtest_run_id,universe_id,model_version_id,start_date,end_date,
         holding_horizon_months,configuration,status,started_at)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        'eb2b9070-2860-4a2f-b780-2d3c2f0f0101'::uuid,
        p.model_version_id,
        '2021-04-01'::date,
        '2026-04-01'::date,
        60,
        jsonb_build_object(
            'methodology_quality','prototype_only',
            'entry','2021-04-01 open from derived unadjusted bars',
            'exit','last close on or before 2026-04-01',
            'quantity',1,
            'dividend_treatment','receivable at ex-date; included in NAV',
            'fees',0,
            'slippage',0,
            'market_data_quality','derived_requires_reconciliation',
            'corporate_action_quality','candidate_requires_official_announcement'
        ),
        'running',
        now()
    from prerequisites p
    where p.entry_price is not null
      and p.bar_count>=500
      and p.action_count>0
      and not exists (
          select 1 from backtest.backtest_runs
          where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
      )
    returning backtest_run_id
), decision_row as (
    insert into backtest.decision_events
        (decision_id,backtest_run_id,decision_at,issuer_id,security_id,
         valuation_run_id,signal,rank_value,target_weight,decision_payload,frozen_at)
    select
        '4ddfbf2c-fc60-4ff2-8569-78fc53b93d01'::uuid,
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        '2021-03-31T16:00:00Z'::timestamptz,
        p.issuer_id,p.security_id,p.valuation_run_id,
        'proxy_hold_for_measurement',null,1.0,
        jsonb_build_object(
            'investment_decision',false,
            'purpose','validate event ledger and five-year outcome pipeline',
            'formal_valuation_run_status','blocked_data'
        ),
        now()
    from prerequisites p
    where exists (
        select 1 from backtest.backtest_runs
        where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    )
      and not exists (
          select 1 from backtest.decision_events
          where decision_id='4ddfbf2c-fc60-4ff2-8569-78fc53b93d01'::uuid
      )
    returning decision_id
), bars as (
    select m.*
    from master.securities s
    cross join lateral pit.market_bars_as_of(
        s.security_id,
        '2026-04-01T08:30:00Z'::timestamptz,
        '2021-04-01'::date,
        '2026-04-01'::date
    ) m
    where s.security_code='600519.SH'
), exit_bar as (
    select * from bars order by trade_date desc limit 1
), dividends as (
    select
        b.trade_date,
        coalesce((
            select sum(ca.cash_amount_per_share)
            from pit.corporate_actions ca
            join master.securities s on s.security_id=ca.security_id
            where s.security_code='600519.SH'
              and ca.action_type='cash_dividend'
              and ca.ex_date between '2021-04-01'::date and b.trade_date
        ),0) as cumulative_dividends
    from bars b
), nav_base as (
    select
        b.trade_date,b.close_price,d.cumulative_dividends,
        b.close_price+d.cumulative_dividends as nav,
        p.entry_price,
        e.trade_date as exit_date,
        e.close_price as exit_price
    from bars b
    join dividends d using(trade_date)
    cross join prerequisites p
    cross join exit_bar e
), nav_lagged as (
    select
        n.*,
        lag(n.nav) over(order by n.trade_date) as previous_nav,
        greatest(
            n.entry_price,
            max(n.nav) over(order by n.trade_date rows between unbounded preceding and current row)
        ) as running_peak
    from nav_base n
), inserted_performance as (
    insert into backtest.daily_performance
        (backtest_run_id,trade_date,nav,daily_return,benchmark_return,
         cash_value,gross_exposure,drawdown)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        n.trade_date,
        n.nav,
        case when n.previous_nav is null
             then n.nav/n.entry_price-1
             else n.nav/n.previous_nav-1 end,
        null,
        n.cumulative_dividends + case when n.trade_date=n.exit_date then n.exit_price else 0 end,
        case when n.trade_date=n.exit_date then 0 else n.close_price end,
        n.nav/n.running_peak-1
    from nav_lagged n
    where exists (
        select 1 from backtest.backtest_runs
        where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    )
    on conflict (backtest_run_id,trade_date) do update
    set nav=excluded.nav,
        daily_return=excluded.daily_return,
        benchmark_return=excluded.benchmark_return,
        cash_value=excluded.cash_value,
        gross_exposure=excluded.gross_exposure,
        drawdown=excluded.drawdown
    returning trade_date
), inserted_positions as (
    insert into backtest.position_snapshots
        (backtest_run_id,trade_date,security_id,quantity,market_value,weight,currency)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        n.trade_date,
        p.security_id,
        case when n.trade_date=n.exit_date then 0 else 1 end,
        case when n.trade_date=n.exit_date then 0 else n.close_price end,
        case when n.trade_date=n.exit_date then 0 else n.close_price/n.nav end,
        'CNY'
    from nav_base n
    cross join prerequisites p
    where exists (
        select 1 from backtest.backtest_runs
        where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    )
    on conflict (backtest_run_id,trade_date,security_id) do update
    set quantity=excluded.quantity,
        market_value=excluded.market_value,
        weight=excluded.weight,
        currency=excluded.currency
    returning trade_date
), buy_tx as (
    insert into backtest.transactions
        (backtest_run_id,decision_id,security_id,trade_date,side,quantity,price,
         fees,slippage,currency)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        '4ddfbf2c-fc60-4ff2-8569-78fc53b93d01'::uuid,
        p.security_id,'2021-04-01'::date,'buy',1,p.entry_price,0,0,'CNY'
    from prerequisites p
    where exists (
        select 1 from backtest.backtest_runs
        where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    )
      and not exists (
          select 1 from backtest.transactions
          where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
            and trade_date='2021-04-01'::date and side='buy'
      )
    returning transaction_id
), sell_tx as (
    insert into backtest.transactions
        (backtest_run_id,decision_id,security_id,trade_date,side,quantity,price,
         fees,slippage,currency)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        '4ddfbf2c-fc60-4ff2-8569-78fc53b93d01'::uuid,
        p.security_id,e.trade_date,'sell',1,e.close_price,0,0,'CNY'
    from prerequisites p
    cross join exit_bar e
    where exists (
        select 1 from backtest.backtest_runs
        where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    )
      and not exists (
          select 1 from backtest.transactions
          where backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
            and trade_date=e.trade_date and side='sell'
      )
    returning transaction_id
), summary as (
    select
        p.entry_price,
        e.trade_date as exit_date,
        e.close_price as exit_price,
        coalesce((
            select sum(ca.cash_amount_per_share)
            from pit.corporate_actions ca
            where ca.security_id=p.security_id
              and ca.action_type='cash_dividend'
              and ca.ex_date between '2021-04-01'::date and e.trade_date
        ),0) as dividends,
        min(dp.drawdown) as max_drawdown,
        count(dp.trade_date) as trading_days
    from prerequisites p
    cross join exit_bar e
    join backtest.daily_performance dp
      on dp.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
    group by p.entry_price,p.security_id,e.trade_date,e.close_price
), metrics as (
    select * from (select
        entry_price,exit_date,exit_price,dividends,max_drawdown,trading_days,
        exit_price+dividends as ending_nav,
        (exit_price+dividends)/entry_price-1 as total_return,
        power((exit_price+dividends)/entry_price,1.0/5.0)-1 as cagr
    from summary) x
), inserted_metrics as (
    insert into backtest.performance_metrics
        (backtest_run_id,metric_code,value_numeric,value_text,unit,metadata)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        v.metric_code,v.value_numeric,v.value_text,v.unit,
        jsonb_build_object(
            'methodology_quality','prototype_only',
            'market_data_quality','derived_requires_reconciliation',
            'corporate_action_quality','candidate_requires_official_announcement'
        )
    from metrics m
    cross join lateral (values
        ('entry_price',m.entry_price,null::text,'CNY/share'),
        ('exit_price',m.exit_price,null::text,'CNY/share'),
        ('dividends_per_share',m.dividends,null::text,'CNY/share'),
        ('ending_nav_per_share',m.ending_nav,null::text,'CNY/share'),
        ('total_return',m.total_return,null::text,'ratio'),
        ('cagr_5y',m.cagr,null::text,'ratio'),
        ('max_drawdown',m.max_drawdown,null::text,'ratio'),
        ('trading_days',m.trading_days::numeric,null::text,'days'),
        ('exit_date',null::numeric,m.exit_date::text,'date')
    ) v(metric_code,value_numeric,value_text,unit)
    on conflict (backtest_run_id,metric_code) do update
    set value_numeric=excluded.value_numeric,
        value_text=excluded.value_text,
        unit=excluded.unit,
        metadata=excluded.metadata
    returning metric_code
), inserted_attribution as (
    insert into backtest.attribution_results
        (backtest_run_id,attribution_date,dimension_type,dimension_value,
         effect_code,effect_value,unit,metadata)
    select
        'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid,
        m.exit_date,
        'security','600519.SH',v.effect_code,v.effect_value,'ratio',
        jsonb_build_object('methodology_quality','prototype_only')
    from metrics m
    cross join lateral (values
        ('price_effect',(m.exit_price-m.entry_price)/m.entry_price),
        ('dividend_effect',m.dividends/m.entry_price),
        ('fee_effect',0::numeric),
        ('total_return',(m.exit_price+m.dividends)/m.entry_price-1)
    ) v(effect_code,effect_value)
    on conflict (backtest_run_id,attribution_date,dimension_type,dimension_value,effect_code)
    do update set effect_value=excluded.effect_value,metadata=excluded.metadata
    returning effect_code
)
update backtest.backtest_runs b
set status='completed_proxy',
    completed_at=now(),
    result_hash=(
        select encode(
            extensions.digest(
                convert_to(
                    string_agg(
                        pm.metric_code||'|'||coalesce(pm.value_numeric::text,pm.value_text,''),
                        '||' order by pm.metric_code
                    ),'UTF8'
                ),'sha256'
            ),'hex'
        )
        from backtest.performance_metrics pm
        where pm.backtest_run_id=b.backtest_run_id
    )
where b.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid;

insert into audit.run_lineage
    (run_type,run_id,input_type,input_id,input_hash,metadata)
select
    'backtest_proxy',
    b.backtest_run_id,
    'valuation_run',
    '40c77d91-6827-4ed0-b683-7a0fa355ca71',
    vr.output_hash,
    jsonb_build_object(
        'market_source','AKSHARE_EASTMONEY_DERIVED',
        'corporate_action_source','AKSHARE_EASTMONEY_FINANCIAL',
        'formal_use_allowed',false
    )
from backtest.backtest_runs b
join model.valuation_runs vr
  on vr.run_id='40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
where b.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
  and not exists (
      select 1 from audit.run_lineage rl
      where rl.run_type='backtest_proxy'
        and rl.run_id=b.backtest_run_id
        and rl.input_type='valuation_run'
  );

commit;
