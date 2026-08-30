do $$
declare
    missing_model_versions integer;
    missing_metric_definitions integer;
    invalid_ratio_units integer;
    duplicate_model_versions integer;
begin
    select count(*) into missing_model_versions
    from (values
        ('owner_earnings_dcf', '1.0.0'),
        ('platform_fcff_sotp', '1.0.0'),
        ('value_driver_fcff', '1.0.0'),
        ('bank_residual_income', '1.0.0')
    ) expected(model_name, semantic_version)
    where not exists (
        select 1 from model.model_versions mv
        where mv.model_name = expected.model_name
          and mv.semantic_version = expected.semantic_version
    );
    if missing_model_versions <> 0 then
        raise exception 'missing % required model-family versions', missing_model_versions;
    end if;

    select count(*) into missing_metric_definitions
    from (values
        ('maintenance_capex'),
        ('ebit'),
        ('tax_rate_normalized'),
        ('sales_to_capital'),
        ('non_operating_assets'),
        ('nopat'),
        ('ronic'),
        ('book_value_per_share'),
        ('roe'),
        ('payout_ratio'),
        ('cost_of_equity')
    ) expected(metric_code)
    where not exists (
        select 1 from fundamentals.metric_definitions md
        where md.metric_code = expected.metric_code
    );
    if missing_metric_definitions <> 0 then
        raise exception 'missing % required canonical metric definitions', missing_metric_definitions;
    end if;

    select count(*) into invalid_ratio_units
    from fundamentals.metric_definitions
    where metric_code in (
        'tax_rate_normalized', 'sales_to_capital', 'roic', 'ronic',
        'reinvestment_rate', 'roe', 'payout_ratio', 'cost_of_equity',
        'net_interest_margin', 'credit_cost', 'npl_ratio',
        'provision_coverage_ratio', 'cet1_ratio'
    ) and default_unit <> 'ratio';
    if invalid_ratio_units <> 0 then
        raise exception 'found % ratio metrics with incompatible default units', invalid_ratio_units;
    end if;

    select count(*) into duplicate_model_versions
    from (
        select model_name, semantic_version
        from model.model_versions
        group by model_name, semantic_version
        having count(*) > 1
    ) duplicates;
    if duplicate_model_versions <> 0 then
        raise exception 'found % duplicate model version keys', duplicate_model_versions;
    end if;
end $$;
