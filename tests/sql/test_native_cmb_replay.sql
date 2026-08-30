-- End-to-end database contract for the native CMB 2021-08-30 replay.

do $$
declare
    actual bigint;
    numeric_value numeric;
    text_value text;
    run_uuid uuid;
    decision_uuid uuid;
begin
    select vr.run_id into run_uuid
    from model.valuation_runs vr
    join master.issuers i on i.issuer_id = vr.issuer_id
    join master.securities s on s.security_id = vr.security_id
    join model.model_versions mv on mv.model_version_id = vr.model_version_id
    where i.issuer_code = 'CMB'
      and s.security_code = '600036.SH'
      and mv.model_name = 'cmb_residual_income_native'
      and mv.semantic_version = '1.0.0'
      and vr.input_hash = '58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683';
    if run_uuid is null then raise exception 'native CMB valuation run is missing'; end if;

    select count(*) into actual
    from raw.documents d
    join master.issuers i on i.issuer_id = d.issuer_id
    where i.issuer_code = 'CMB'
      and d.source_url = 'https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF';
    if actual <> 1 then raise exception 'expected one CMB official-report reference, got %', actual; end if;

    select count(*) into actual
    from pit.financial_facts f
    join master.issuers i on i.issuer_id = f.issuer_id
    where i.issuer_code = 'CMB'
      and f.available_at <= '2021-08-30T15:00:00+08:00'::timestamptz
      and f.period_end <= date '2021-06-30';
    if actual <> 12 then raise exception 'expected 12 eligible CMB PIT facts, got %', actual; end if;

    select count(*) into actual
    from pit.financial_facts f
    join master.issuers i on i.issuer_id = f.issuer_id
    where i.issuer_code = 'CMB'
      and f.period_end <= date '2021-06-30'
      and f.available_at > '2021-08-30T15:00:00+08:00'::timestamptz;
    if actual <> 0 then raise exception 'native CMB future-fact leakage detected: % rows', actual; end if;

    select count(*) into actual
    from fundamentals.normalized_facts n
    join master.issuers i on i.issuer_id = n.issuer_id
    where i.issuer_code = 'CMB'
      and n.normalization_version = 'cmb_residual_income_normalization_v1';
    if actual <> 8 then raise exception 'expected 8 normalized CMB facts, got %', actual; end if;

    select count(*) into actual from model.run_assumptions where run_id = run_uuid;
    if actual <> 21 then raise exception 'expected 21 CMB run assumptions, got %', actual; end if;

    select count(*) into actual from model.valuation_outputs where run_id = run_uuid;
    if actual <> 23 then raise exception 'expected 23 CMB valuation outputs, got %', actual; end if;

    select value_numeric into numeric_value
    from model.valuation_outputs
    where run_id = run_uuid and scenario = 'base'
      and output_key = 'intrinsic_value_per_share';
    if abs(numeric_value - 36.135509092814395) > 0.000000001 then
        raise exception 'unexpected CMB base intrinsic value: %', numeric_value;
    end if;

    select value_numeric into numeric_value
    from model.valuation_outputs
    where run_id = run_uuid and scenario = 'base'
      and output_key = 'predicted_5y_irr';
    if abs(numeric_value - 0.03755026696155135) > 0.000000001 then
        raise exception 'unexpected CMB base IRR: %', numeric_value;
    end if;

    select value_numeric into numeric_value
    from model.valuation_outputs
    where run_id = run_uuid and scenario = 'market_expectations'
      and output_key = 'implied_uniform_roe';
    if abs(numeric_value - 0.17671456246762313) > 0.000000001 then
        raise exception 'unexpected CMB implied ROE: %', numeric_value;
    end if;

    select value_text into text_value
    from model.valuation_outputs
    where run_id = run_uuid and scenario = 'decision'
      and output_key = 'signal';
    if text_value <> 'avoid_at_price' then
        raise exception 'unexpected CMB decision signal: %', text_value;
    end if;

    select count(*) into actual
    from model.reverse_dcf_results
    where run_id = run_uuid and solved_variable = 'uniform_explicit_roe'
      and converged;
    if actual <> 1 then raise exception 'expected one converged CMB reverse solve, got %', actual; end if;

    select count(*) into actual
    from audit.run_lineage
    where run_type = 'valuation' and run_id = run_uuid;
    if actual <> 14 then raise exception 'expected 14 CMB lineage inputs, got %', actual; end if;

    select count(*) into actual
    from audit.run_readiness
    where run_type = 'valuation' and run_id = run_uuid
      and readiness = 'provisional';
    if actual <> 1 then raise exception 'expected provisional CMB readiness, got % rows', actual; end if;

    select de.decision_id into decision_uuid
    from backtest.decision_events de
    where de.valuation_run_id = run_uuid
      and de.signal = 'avoid_at_price';
    if decision_uuid is null then raise exception 'native CMB Phase-A decision is missing'; end if;

    select count(*) into actual
    from backtest.decision_outcomes o
    where o.decision_id = decision_uuid
      and abs(o.annualized_return - 0.0062381161097595506) < 0.000000001
      and o.source_quality = 'legacy_proxy';
    if actual <> 1 then raise exception 'native CMB Phase-B endpoint outcome is missing or changed'; end if;

    select count(*) into actual
    from backtest.attribution_results a
    join backtest.decision_outcomes o on o.outcome_id = a.outcome_id
    where o.decision_id = decision_uuid
      and a.methodology_version = 'endpoint_attribution_v1';
    if actual <> 8 then raise exception 'expected 8 CMB attribution rows, got %', actual; end if;
end
$$;
