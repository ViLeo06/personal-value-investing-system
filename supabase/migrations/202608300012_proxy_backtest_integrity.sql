begin;

create or replace function audit.proxy_backtest_integrity(p_backtest_run_id uuid)
returns table(
    check_code text,
    passed boolean,
    details jsonb
)
language sql
stable
security invoker
set search_path=''
as $$
    with run_row as (
        select *
        from backtest.backtest_runs
        where backtest_run_id=p_backtest_run_id
    ), daily as (
        select
            count(*)::integer as row_count,
            min(trade_date) as first_date,
            max(trade_date) as last_date,
            coalesce(max(abs(nav-(coalesce(cash_value,0)+coalesce(gross_exposure,0)))),0) as max_nav_identity_error,
            coalesce(min(drawdown),0) as minimum_drawdown
        from backtest.daily_performance
        where backtest_run_id=p_backtest_run_id
    ), transactions as (
        select
            count(*)::integer as row_count,
            count(*) filter(where side='buy')::integer as buy_count,
            count(*) filter(where side='sell')::integer as sell_count,
            min(trade_date) filter(where side='buy') as buy_date,
            max(trade_date) filter(where side='sell') as sell_date
        from backtest.transactions
        where backtest_run_id=p_backtest_run_id
    ), metrics as (
        select
            count(*)::integer as metric_count,
            max(value_numeric) filter(where metric_code='entry_price') as entry_price,
            max(value_numeric) filter(where metric_code='exit_price') as exit_price,
            max(value_numeric) filter(where metric_code='dividends_per_share') as dividends,
            max(value_numeric) filter(where metric_code='total_return') as total_return,
            max(value_numeric) filter(where metric_code='max_drawdown') as stored_max_drawdown
        from backtest.performance_metrics
        where backtest_run_id=p_backtest_run_id
    ), attribution as (
        select
            count(*)::integer as effect_count,
            coalesce(sum(effect_value) filter(where effect_code in ('price_effect','dividend_effect','fee_effect')),0) as component_sum,
            max(effect_value) filter(where effect_code='total_return') as attributed_total_return
        from backtest.attribution_results
        where backtest_run_id=p_backtest_run_id
    ), recomputed_hash as (
        select encode(
            extensions.digest(
                convert_to(
                    string_agg(
                        metric_code||'|'||coalesce(value_numeric::text,value_text,''),
                        '||' order by metric_code
                    ),
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        ) as result_hash
        from backtest.performance_metrics
        where backtest_run_id=p_backtest_run_id
    ), tx_prices as (
        select
            max(price) filter(where side='buy') as buy_price,
            max(price) filter(where side='sell') as sell_price
        from backtest.transactions
        where backtest_run_id=p_backtest_run_id
    )
    select
        'RUN_COMPLETED_PROXY',
        coalesce((select status='completed_proxy' from run_row),false),
        jsonb_build_object(
            'status',(select status from run_row),
            'result_hash',(select result_hash from run_row)
        )

    union all
    select
        'DAILY_LEDGER_PRESENT',
        d.row_count>=500 and d.first_date is not null and d.last_date is not null,
        jsonb_build_object(
            'row_count',d.row_count,
            'first_date',d.first_date,
            'last_date',d.last_date
        )
    from daily d

    union all
    select
        'NAV_ACCOUNTING_IDENTITY',
        d.max_nav_identity_error<=0.000001,
        jsonb_build_object('max_absolute_error',d.max_nav_identity_error)
    from daily d

    union all
    select
        'ROUND_TRIP_TRANSACTIONS',
        t.row_count=2 and t.buy_count=1 and t.sell_count=1 and t.buy_date<t.sell_date,
        jsonb_build_object(
            'row_count',t.row_count,
            'buy_count',t.buy_count,
            'sell_count',t.sell_count,
            'buy_date',t.buy_date,
            'sell_date',t.sell_date
        )
    from transactions t

    union all
    select
        'TRANSACTION_PRICE_RECONCILIATION',
        m.entry_price is not null and m.exit_price is not null
            and abs(m.entry_price-p.buy_price)<=0.000001
            and abs(m.exit_price-p.sell_price)<=0.000001,
        jsonb_build_object(
            'metric_entry_price',m.entry_price,
            'transaction_buy_price',p.buy_price,
            'metric_exit_price',m.exit_price,
            'transaction_sell_price',p.sell_price
        )
    from metrics m cross join tx_prices p

    union all
    select
        'TOTAL_RETURN_RECALCULATION',
        m.entry_price>0 and m.total_return is not null
            and abs(m.total_return-((m.exit_price+m.dividends)/m.entry_price-1))<=0.00000001,
        jsonb_build_object(
            'stored_total_return',m.total_return,
            'recalculated_total_return',case when m.entry_price>0
                then (m.exit_price+m.dividends)/m.entry_price-1 end
        )
    from metrics m

    union all
    select
        'DRAWDOWN_RECONCILIATION',
        m.stored_max_drawdown is not null
            and abs(m.stored_max_drawdown-d.minimum_drawdown)<=0.00000001,
        jsonb_build_object(
            'stored_max_drawdown',m.stored_max_drawdown,
            'daily_minimum_drawdown',d.minimum_drawdown
        )
    from metrics m cross join daily d

    union all
    select
        'ATTRIBUTION_RECONCILIATION',
        a.effect_count>=4 and a.attributed_total_return is not null
            and abs(a.attributed_total_return-a.component_sum)<=0.00000001
            and abs(a.attributed_total_return-m.total_return)<=0.00000001,
        jsonb_build_object(
            'effect_count',a.effect_count,
            'component_sum',a.component_sum,
            'attributed_total_return',a.attributed_total_return,
            'performance_total_return',m.total_return
        )
    from attribution a cross join metrics m

    union all
    select
        'RESULT_HASH_REPRODUCIBLE',
        r.result_hash is not null and length(r.result_hash)=64
            and r.result_hash=h.result_hash,
        jsonb_build_object(
            'stored_result_hash',r.result_hash,
            'recomputed_result_hash',h.result_hash
        )
    from run_row r cross join recomputed_hash h;
$$;

revoke all on function audit.proxy_backtest_integrity(uuid)
    from public,anon,authenticated;
grant execute on function audit.proxy_backtest_integrity(uuid)
    to service_role;

commit;
