-- Database-level Gate-0 legacy bridge assertions.
-- This script is intended to be executed after seeds 003a-003f.

do $$
declare
    actual bigint;
begin
    select count(*) into actual
    from backtest.universe_memberships m
    join backtest.universes u using (universe_id)
    where u.universe_code = 'GATE0_LEGACY_4';
    if actual <> 4 then raise exception 'expected 4 universe memberships, got %', actual; end if;

    select count(*) into actual
    from model.valuation_runs
    where scenario_set_version = 'legacy_frozen_v1';
    if actual <> 4 then raise exception 'expected 4 valuation runs, got %', actual; end if;

    select count(*) into actual
    from model.valuation_outputs o
    join model.valuation_runs r using (run_id)
    where r.scenario_set_version = 'legacy_frozen_v1';
    if actual <> 48 then raise exception 'expected 48 valuation outputs, got %', actual; end if;

    select count(*) into actual
    from pit.corporate_actions a
    join raw.documents d on d.document_id = a.source_document_id
    where d.content_hash = 'ec4cc507acfa6e73427172cc0e3011881c96e7b7727bfe7226e15ab6b5665e6e';
    if actual <> 28 then raise exception 'expected 28 corporate actions, got %', actual; end if;

    select count(*) into actual
    from pit.market_bars b
    join raw.data_sources s using (source_id)
    where s.source_code = 'LEGACY_BACKTEST_XLSX'
      and b.metadata ->> 'phase' = 'phase_b'
      and b.available_at <= '2021-08-30T16:00:00+08:00'::timestamptz;
    if actual <> 0 then raise exception 'phase-B market-bar leakage detected: % rows', actual; end if;

    select count(*) into actual
    from pit.corporate_actions a
    join raw.documents d on d.document_id = a.source_document_id
    where d.content_hash = 'ec4cc507acfa6e73427172cc0e3011881c96e7b7727bfe7226e15ab6b5665e6e'
      and a.available_at <= '2021-08-30T16:00:00+08:00'::timestamptz;
    if actual <> 0 then raise exception 'corporate-action leakage detected: % rows', actual; end if;
end
$$;
