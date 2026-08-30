do $$
declare
    missing_tables integer;
    quality_rule_count integer;
    normalization_policy_count integer;
    unfrozen_reference_rows integer;
    invalid_hashes integer;
begin
    select count(*) into missing_tables
    from (values
        ('master','calendar_versions'),
        ('master','trading_day_versions'),
        ('raw','parser_versions'),
        ('raw','parser_runs'),
        ('fundamentals','mapping_registries'),
        ('fundamentals','mapping_rules'),
        ('fundamentals','normalization_policies'),
        ('fundamentals','normalization_runs'),
        ('model','parameter_sets'),
        ('model','parameter_values'),
        ('audit','quality_rule_sets'),
        ('audit','run_quality_results'),
        ('audit','run_readiness'),
        ('audit','release_manifests')
    ) expected(schema_name, table_name)
    where not exists (
        select 1
        from information_schema.tables actual
        where actual.table_schema = expected.schema_name
          and actual.table_name = expected.table_name
    );
    if missing_tables <> 0 then
        raise exception 'missing % governance/parser/calendar tables', missing_tables;
    end if;

    select jsonb_array_length(rules) into quality_rule_count
    from audit.quality_rule_sets
    where rule_set_version = 'gate0_quality_v1.0.0';
    if quality_rule_count <> 15 then
        raise exception 'expected 15 Gate-0 quality rules, found %', quality_rule_count;
    end if;

    select count(*) into normalization_policy_count
    from fundamentals.normalization_policies
    where semantic_version = '1.0.0'
      and policy_code in (
        'pit_revision_selection',
        'cumulative_to_standalone',
        'owner_earnings_normalization',
        'platform_fcff_normalization',
        'value_driver_normalization',
        'bank_residual_income_normalization'
      );
    if normalization_policy_count <> 6 then
        raise exception 'expected 6 normalization policies, found %', normalization_policy_count;
    end if;

    select count(*) into unfrozen_reference_rows
    from (
        select status, frozen_at from audit.quality_rule_sets
        where rule_set_version = 'gate0_quality_v1.0.0'
        union all
        select status, frozen_at from fundamentals.normalization_policies
        where semantic_version = '1.0.0'
    ) reference_rows
    where status <> 'frozen' or frozen_at is null;
    if unfrozen_reference_rows <> 0 then
        raise exception 'found % unfrozen reference-policy rows', unfrozen_reference_rows;
    end if;

    select count(*) into invalid_hashes
    from (
        select content_hash from audit.quality_rule_sets
        where rule_set_version = 'gate0_quality_v1.0.0'
        union all
        select content_hash from fundamentals.normalization_policies
        where semantic_version = '1.0.0'
    ) hashes
    where content_hash !~ '^[0-9a-f]{64}$';
    if invalid_hashes <> 0 then
        raise exception 'found % invalid reference content hashes', invalid_hashes;
    end if;
end $$;
