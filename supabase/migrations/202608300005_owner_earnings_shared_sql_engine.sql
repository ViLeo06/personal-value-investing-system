begin;

create or replace function model.owner_earnings_dcf_components(
    p_base_owner_earnings numeric,
    p_shares_outstanding numeric,
    p_stage1_growth numeric,
    p_discount_rate numeric,
    p_terminal_growth numeric,
    p_forecast_horizon_years integer default 10,
    p_stage1_years integer default 5,
    p_required_return_hurdle numeric default 0.15
)
returns table (
    year1_owner_earnings numeric,
    stage1_end_owner_earnings numeric,
    horizon_end_owner_earnings numeric,
    pv_explicit_period numeric,
    pv_terminal numeric,
    equity_value numeric,
    intrinsic_value_per_share numeric,
    terminal_value_share numeric,
    hurdle_value numeric,
    hurdle_value_per_share numeric
)
language plpgsql
immutable
strict
security invoker
set search_path=pg_catalog
as $$
begin
    if p_base_owner_earnings<=0 then raise exception 'base owner earnings must be positive'; end if;
    if p_shares_outstanding<=0 then raise exception 'shares outstanding must be positive'; end if;
    if p_forecast_horizon_years<1 or p_stage1_years<1
       or p_stage1_years>p_forecast_horizon_years then
        raise exception 'invalid forecast horizon';
    end if;
    if p_stage1_growth<=-1 or p_terminal_growth<=-1 then
        raise exception 'growth must be greater than -100%%';
    end if;
    if p_discount_rate<=p_terminal_growth then
        raise exception 'discount rate must exceed terminal growth';
    end if;
    if p_required_return_hurdle<=p_terminal_growth then
        raise exception 'required return hurdle must exceed terminal growth';
    end if;

    return query
    with recursive cash_flows as (
      select 1 as forecast_year,
             p_base_owner_earnings*(1+p_stage1_growth) as cash_flow
      union all
      select c.forecast_year+1,
             c.cash_flow*(1+case
               when c.forecast_year+1<=p_stage1_years
                    or p_forecast_horizon_years=p_stage1_years then p_stage1_growth
               else p_stage1_growth+(p_terminal_growth-p_stage1_growth)
                    *((c.forecast_year+1)-p_stage1_years)::numeric
                    /(p_forecast_horizon_years-p_stage1_years)::numeric end)
      from cash_flows c where c.forecast_year<p_forecast_horizon_years
    ), aggregated as (
      select
        max(cash_flow) filter(where forecast_year=1) as y1,
        max(cash_flow) filter(where forecast_year=p_stage1_years) as y_stage1,
        max(cash_flow) filter(where forecast_year=p_forecast_horizon_years) as y_horizon,
        sum(cash_flow/power(1+p_discount_rate,forecast_year)) as explicit_pv,
        max(cash_flow) filter(where forecast_year=p_forecast_horizon_years)
          *(1+p_terminal_growth)/(p_discount_rate-p_terminal_growth)
          /power(1+p_discount_rate,p_forecast_horizon_years) as terminal_pv,
        sum(cash_flow/power(1+p_required_return_hurdle,forecast_year))
          +(max(cash_flow) filter(where forecast_year=p_forecast_horizon_years)
            *(1+p_terminal_growth)/(p_required_return_hurdle-p_terminal_growth)
            /power(1+p_required_return_hurdle,p_forecast_horizon_years)) as hurdle_pv
      from cash_flows
    )
    select y1,y_stage1,y_horizon,explicit_pv,terminal_pv,
           explicit_pv+terminal_pv,(explicit_pv+terminal_pv)/p_shares_outstanding,
           terminal_pv/(explicit_pv+terminal_pv),hurdle_pv,hurdle_pv/p_shares_outstanding
    from aggregated;
end;
$$;

create or replace function model.solve_owner_earnings_stage1_growth(
    p_target_price numeric,
    p_base_owner_earnings numeric,
    p_shares_outstanding numeric,
    p_discount_rate numeric,
    p_terminal_growth numeric,
    p_lower_bound numeric default -0.20,
    p_upper_bound numeric default 0.40,
    p_tolerance numeric default 0.00000001,
    p_max_iterations integer default 200,
    p_forecast_horizon_years integer default 10,
    p_stage1_years integer default 5,
    p_required_return_hurdle numeric default 0.15
)
returns table (
    solution_value numeric,residual numeric,iterations integer,converged boolean,
    lower_bound numeric,upper_bound numeric
)
language plpgsql
immutable
strict
security invoker
set search_path=pg_catalog
as $$
declare
    v_low numeric:=p_lower_bound;
    v_high numeric:=p_upper_bound;
    v_mid numeric;
    v_low_residual numeric;
    v_high_residual numeric;
    v_mid_residual numeric;
    v_iteration integer;
begin
    if p_target_price<=0 then raise exception 'target price must be positive'; end if;
    if p_lower_bound>=p_upper_bound then raise exception 'invalid solver bounds'; end if;
    if p_tolerance<=0 or p_max_iterations<1 then raise exception 'invalid solver controls'; end if;

    select d.intrinsic_value_per_share-p_target_price into v_low_residual
    from model.owner_earnings_dcf_components(
      p_base_owner_earnings,p_shares_outstanding,v_low,p_discount_rate,p_terminal_growth,
      p_forecast_horizon_years,p_stage1_years,p_required_return_hurdle) d;
    select d.intrinsic_value_per_share-p_target_price into v_high_residual
    from model.owner_earnings_dcf_components(
      p_base_owner_earnings,p_shares_outstanding,v_high,p_discount_rate,p_terminal_growth,
      p_forecast_horizon_years,p_stage1_years,p_required_return_hurdle) d;

    if v_low_residual=0 then
      return query select v_low,0::numeric,0,true,p_lower_bound,p_upper_bound; return;
    end if;
    if v_high_residual=0 then
      return query select v_high,0::numeric,0,true,p_lower_bound,p_upper_bound; return;
    end if;
    if v_low_residual*v_high_residual>0 then
      return query select null::numeric,null::numeric,0,false,p_lower_bound,p_upper_bound; return;
    end if;

    for v_iteration in 1..p_max_iterations loop
      v_mid:=(v_low+v_high)/2;
      select d.intrinsic_value_per_share-p_target_price into v_mid_residual
      from model.owner_earnings_dcf_components(
        p_base_owner_earnings,p_shares_outstanding,v_mid,p_discount_rate,p_terminal_growth,
        p_forecast_horizon_years,p_stage1_years,p_required_return_hurdle) d;
      if abs(v_mid_residual)<=p_tolerance or (v_high-v_low)/2<=p_tolerance then
        return query select v_mid,v_mid_residual,v_iteration,true,p_lower_bound,p_upper_bound;
        return;
      end if;
      if v_low_residual*v_mid_residual<=0 then
        v_high:=v_mid; v_high_residual:=v_mid_residual;
      else
        v_low:=v_mid; v_low_residual:=v_mid_residual;
      end if;
    end loop;

    return query select v_mid,v_mid_residual,p_max_iterations,false,p_lower_bound,p_upper_bound;
end;
$$;

revoke all on function model.owner_earnings_dcf_components(numeric,numeric,numeric,numeric,numeric,integer,integer,numeric)
  from public,anon,authenticated;
revoke all on function model.solve_owner_earnings_stage1_growth(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,integer,integer,integer,numeric)
  from public,anon,authenticated;

commit;
