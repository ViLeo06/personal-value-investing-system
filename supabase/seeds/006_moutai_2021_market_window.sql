begin;

insert into raw.data_sources
    (source_code, name, source_type, homepage_url, is_free, is_open_source,
     pit_capability, priority, notes)
values
    ('AKSHARE_EASTMONEY_DERIVED',
     'AKShare / Eastmoney historical daily bars',
     'open_source_adapter',
     'https://github.com/akfamily/akshare',
     true,
     true,
     'derived',
     50,
     'Open-source adapter with a free underlying web provider. Archive every raw response; reconcile formal backtests against an independent source.')
on conflict (source_code) do update
set name = excluded.name,
    source_type = excluded.source_type,
    homepage_url = excluded.homepage_url,
    is_free = excluded.is_free,
    is_open_source = excluded.is_open_source,
    pit_capability = excluded.pit_capability,
    priority = excluded.priority,
    notes = excluded.notes;

with provider as (
    select
        'https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=1.600519&klt=101&fqt=0&beg=20210330&end=20210402&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'::text as source_url,
        extensions.http_get(
            'https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=1.600519&klt=101&fqt=0&beg=20210330&end=20210402&fields1=f1,f2,f3,f4,f5,f6&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61'
        ) as response
), checked as (
    select
        source_url,
        (response).status as http_status,
        (response).content::jsonb as payload
    from provider
), source_row as (
    select source_id
    from raw.data_sources
    where source_code = 'AKSHARE_EASTMONEY_DERIVED'
), security_row as (
    select security_id
    from master.securities
    where security_code = '600519.SH'
), batch_row as (
    insert into raw.ingestion_batches
        (source_id, status, adapter_version, request_params)
    select
        source_row.source_id,
        'running',
        'eastmoney-kline-v1',
        jsonb_build_object(
            'security_code', '600519.SH',
            'beg', '20210330',
            'end', '20210402',
            'adjustment', 'none',
            'frequency', 'daily'
        )
    from source_row
    returning batch_id, source_id
), document_row as (
    insert into raw.documents
        (source_id, batch_id, security_id, document_type, title, source_url,
         mime_type, language, published_at, retrieved_at, content_hash, parser_version, metadata)
    select
        batch_row.source_id,
        batch_row.batch_id,
        security_row.security_id,
        'market_data_response',
        '600519.SH unadjusted daily bars 2021-03-30 to 2021-04-02',
        checked.source_url,
        'application/json',
        'zh-CN',
        null,
        now(),
        encode(extensions.digest(convert_to(checked.payload::text, 'UTF8'), 'sha256'), 'hex'),
        'eastmoney-kline-v1',
        jsonb_build_object(
            'http_status', checked.http_status,
            'provider_payload', checked.payload,
            'methodology_quality', 'derived_requires_reconciliation'
        )
    from checked
    cross join batch_row
    cross join security_row
    where checked.http_status = 200
      and jsonb_typeof(checked.payload->'data'->'klines') = 'array'
      and jsonb_array_length(checked.payload->'data'->'klines') > 0
    returning document_id, batch_id, source_id, security_id
), parsed as (
    select
        document_row.*,
        string_to_array(kline, ',') as fields
    from document_row
    cross join checked
    cross join lateral jsonb_array_elements_text(checked.payload->'data'->'klines') as k(kline)
), upserted as (
    insert into pit.market_bars
        (security_id, trade_date, open_price, high_price, low_price, close_price,
         volume, turnover, trading_status, currency, available_at, ingested_at,
         source_id, batch_id, record_hash, metadata)
    select
        parsed.security_id,
        parsed.fields[1]::date,
        parsed.fields[2]::numeric,
        parsed.fields[4]::numeric,
        parsed.fields[5]::numeric,
        parsed.fields[3]::numeric,
        nullif(parsed.fields[6], '')::numeric,
        nullif(parsed.fields[7], '')::numeric,
        'trading',
        'CNY',
        ((parsed.fields[1]::date + time '15:15') at time zone 'Asia/Shanghai'),
        now(),
        parsed.source_id,
        parsed.batch_id,
        encode(
            extensions.digest(
                convert_to(
                    concat_ws('|',
                        '600519.SH', parsed.fields[1], parsed.fields[2],
                        parsed.fields[4], parsed.fields[5], parsed.fields[3],
                        parsed.fields[6], parsed.fields[7], 'CNY'
                    ),
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        ),
        jsonb_build_object(
            'source_document_id', parsed.document_id,
            'provider', 'Eastmoney',
            'adapter', 'AKShare-compatible',
            'adjustment', 'none',
            'availability_policy', 'XSHG close plus 15-minute safety lag',
            'methodology_quality', 'derived_requires_reconciliation'
        )
    from parsed
    on conflict (security_id, trade_date, source_id, available_at) do update
    set open_price = excluded.open_price,
        high_price = excluded.high_price,
        low_price = excluded.low_price,
        close_price = excluded.close_price,
        volume = excluded.volume,
        turnover = excluded.turnover,
        ingested_at = excluded.ingested_at,
        batch_id = excluded.batch_id,
        record_hash = excluded.record_hash,
        metadata = excluded.metadata
    returning bar_id
)
update raw.ingestion_batches b
set status = case when exists (select 1 from upserted) then 'completed' else 'failed' end,
    completed_at = now(),
    row_count = (select count(*) from upserted),
    batch_hash = (
        select encode(
            extensions.digest(
                convert_to(string_agg(bar_id::text, '|' order by bar_id), 'UTF8'),
                'sha256'
            ),
            'hex'
        )
        from upserted
    ),
    error_text = case when exists (select 1 from upserted) then null else 'Provider returned no eligible kline rows' end
where b.batch_id in (select batch_id from batch_row);

commit;
