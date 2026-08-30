begin;

-- Correct the 2020 annual-report document URL. The previous `_1.pdf` URL is a
-- different same-day announcement; the annual report is `_4.pdf`.
update raw.documents d
set source_url = 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_4.pdf',
    mime_type = 'application/pdf',
    metadata = d.metadata || jsonb_build_object(
        'official_url_verified', true,
        'official_url_verification_method', 'exchange_announcement_index',
        'binary_archive_status', 'pending',
        'content_hash_status', 'pending',
        'source_correction', 'replaced_wrong_same_day_announcement_url'
    )
where d.issuer_id = (
        select issuer_id from master.issuers where issuer_code = 'KWEICHOW_MOUTAI'
    )
  and d.document_type = 'annual_report'
  and d.title = '贵州茅台2020年年度报告';

-- Register the first-party 2021 half-year report URL. Numeric facts remain
-- linked to the parsed free mirror until the official PDF bytes are archived
-- and independently parsed; metadata below makes that boundary explicit.
insert into raw.documents (
    source_id,
    issuer_id,
    security_id,
    document_type,
    title,
    source_url,
    mime_type,
    language,
    published_at,
    effective_date,
    metadata
)
select
    ds.source_id,
    i.issuer_id,
    s.security_id,
    'half_year_report',
    '贵州茅台2021年半年度报告（上交所原始文件）',
    'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-07-31/600519_20210731_2_sUdHzgnQ.pdf',
    'application/pdf',
    'zh-CN',
    timestamptz '2021-07-30 11:34:00+00',
    date '2021-06-30',
    jsonb_build_object(
        'evidence_role', 'first_party_filing',
        'exchange_document_date', '2021-07-31',
        'publication_time_source', 'contemporaneous_publication_archive',
        'next_usable_session', '2021-08-02T09:30:00+08:00',
        'binary_archive_status', 'pending',
        'content_hash_status', 'pending',
        'official_url_verified', true,
        'official_url_verification_method', 'exchange_announcement_index'
    )
from raw.data_sources ds
join master.issuers i on i.issuer_code = 'KWEICHOW_MOUTAI'
join master.securities s on s.issuer_id = i.issuer_id
where ds.source_code = 'SSE'
  and s.security_code = '600519.SH'
  and not exists (
      select 1
      from raw.documents existing
      where existing.source_url = 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-07-31/600519_20210731_2_sUdHzgnQ.pdf'
  );

update pit.financial_facts f
set metadata = f.metadata || jsonb_build_object(
        'official_report_document_id', (
            select d.document_id::text
            from raw.documents d
            where d.source_url = 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-07-31/600519_20210731_2_sUdHzgnQ.pdf'
            limit 1
        ),
        'numeric_source_role', 'free_mirror_parse',
        'official_binary_parse_status', 'pending',
        'provenance_upgrade', 'official_filing_url_registered_without_overstating_binary_verification'
    )
where f.issuer_id = (
        select issuer_id from master.issuers where issuer_code = 'KWEICHOW_MOUTAI'
    )
  and f.period_end = date '2021-06-30';

-- Register first-party implementation announcements for all post-cutoff cash
-- distributions in the native Moutai Gate-0 outcome horizon.
with evidence(
    title,
    source_url,
    published_at,
    effective_date
) as (
    values
      ('贵州茅台2021年年度权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2022-06-24/600519_20220624_1_uyoZ4ubX.pdf', timestamptz '2022-06-24 00:00:00+08', date '2022-06-30'),
      ('贵州茅台2022年度回报股东特别分红实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2022-12-21/600519_20221221_LBJY.pdf', timestamptz '2022-12-21 00:00:00+08', date '2022-12-27'),
      ('贵州茅台2022年年度权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2023-06-26/600519_20230626_V0SN.pdf', timestamptz '2023-06-26 00:00:00+08', date '2023-06-30'),
      ('贵州茅台2023年度回报股东特别分红实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2023-12-14/600519_20231214_WR1C.pdf', timestamptz '2023-12-14 00:00:00+08', date '2023-12-20'),
      ('贵州茅台2023年年度权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2024-06-12/600519_20240612_P65B.pdf', timestamptz '2024-06-12 00:00:00+08', date '2024-06-19'),
      ('贵州茅台2024年中期权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2024-12-14/600519_20241214_HGV2.pdf', timestamptz '2024-12-14 00:00:00+08', date '2024-12-20'),
      ('贵州茅台2024年年度权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2025-06-20/600519_20250620_3NKQ.pdf', timestamptz '2025-06-20 00:00:00+08', date '2025-06-26'),
      ('贵州茅台2025年中期权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2025-12-11/600519_20251211_TWNW.pdf', timestamptz '2025-12-11 00:00:00+08', date '2025-12-19'),
      ('贵州茅台2025年年度权益分派实施公告', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2026-06-22/600519_20260622_ZTRO.pdf', timestamptz '2026-06-22 00:00:00+08', date '2026-06-26')
)
insert into raw.documents (
    source_id,
    issuer_id,
    security_id,
    document_type,
    title,
    source_url,
    mime_type,
    language,
    published_at,
    effective_date,
    metadata
)
select
    ds.source_id,
    i.issuer_id,
    s.security_id,
    'corporate_action_implementation',
    e.title,
    e.source_url,
    'application/pdf',
    'zh-CN',
    e.published_at,
    e.effective_date,
    jsonb_build_object(
        'evidence_role', 'first_party_corporate_action_implementation',
        'publication_time_precision', 'date',
        'binary_archive_status', 'pending',
        'content_hash_status', 'pending',
        'official_url_verified', true,
        'official_url_verification_method', 'exchange_announcement_index'
    )
from evidence e
cross join raw.data_sources ds
join master.issuers i on i.issuer_code = 'KWEICHOW_MOUTAI'
join master.securities s on s.issuer_id = i.issuer_id
where ds.source_code = 'SSE'
  and s.security_code = '600519.SH'
  and not exists (
      select 1 from raw.documents d where d.source_url = e.source_url
  );

-- Upgrade proxy month-end action records to exact announced/record/ex/payment
-- dates. Date-only announcements are made usable at the next trading session
-- open; exact release times remain a documented uncertainty.
with action_evidence(
    action_type,
    cash_amount,
    source_url,
    announced_at,
    available_at,
    record_date,
    ex_date,
    payment_date
) as (
    values
      ('cash_dividend', numeric '21.675', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2022-06-24/600519_20220624_1_uyoZ4ubX.pdf', timestamptz '2022-06-24 00:00:00+08', timestamptz '2022-06-27 09:30:00+08', date '2022-06-29', date '2022-06-30', date '2022-06-30'),
      ('special_dividend', numeric '21.91', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2022-12-21/600519_20221221_LBJY.pdf', timestamptz '2022-12-21 00:00:00+08', timestamptz '2022-12-22 09:30:00+08', date '2022-12-26', date '2022-12-27', date '2022-12-27'),
      ('cash_dividend', numeric '25.911', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2023-06-26/600519_20230626_V0SN.pdf', timestamptz '2023-06-26 00:00:00+08', timestamptz '2023-06-27 09:30:00+08', date '2023-06-29', date '2023-06-30', date '2023-06-30'),
      ('special_dividend', numeric '19.106', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2023-12-14/600519_20231214_WR1C.pdf', timestamptz '2023-12-14 00:00:00+08', timestamptz '2023-12-15 09:30:00+08', date '2023-12-19', date '2023-12-20', date '2023-12-20'),
      ('cash_dividend', numeric '30.876', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2024-06-12/600519_20240612_P65B.pdf', timestamptz '2024-06-12 00:00:00+08', timestamptz '2024-06-13 09:30:00+08', date '2024-06-18', date '2024-06-19', date '2024-06-19'),
      ('interim_dividend', numeric '23.882', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2024-12-14/600519_20241214_HGV2.pdf', timestamptz '2024-12-14 00:00:00+08', timestamptz '2024-12-16 09:30:00+08', date '2024-12-19', date '2024-12-20', date '2024-12-20'),
      ('cash_dividend', numeric '27.673', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2025-06-20/600519_20250620_3NKQ.pdf', timestamptz '2025-06-20 00:00:00+08', timestamptz '2025-06-23 09:30:00+08', date '2025-06-25', date '2025-06-26', date '2025-06-26'),
      ('interim_dividend', numeric '23.957', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2025-12-11/600519_20251211_TWNW.pdf', timestamptz '2025-12-11 00:00:00+08', timestamptz '2025-12-12 09:30:00+08', date '2025-12-18', date '2025-12-19', date '2025-12-19'),
      ('cash_dividend', numeric '28.02423', 'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2026-06-22/600519_20260622_ZTRO.pdf', timestamptz '2026-06-22 00:00:00+08', timestamptz '2026-06-23 09:30:00+08', date '2026-06-25', date '2026-06-26', date '2026-06-26')
)
update pit.corporate_actions ca
set announced_at = a.announced_at,
    available_at = a.available_at,
    record_date = a.record_date,
    ex_date = a.ex_date,
    payment_date = a.payment_date,
    effective_date = a.ex_date,
    source_document_id = d.document_id,
    record_hash = encode(
        digest(
            concat_ws('|',
                'corporate_action_v2',
                ca.security_id::text,
                a.action_type,
                a.cash_amount::text,
                ca.currency,
                a.announced_at::text,
                a.available_at::text,
                a.record_date::text,
                a.ex_date::text,
                a.payment_date::text,
                a.source_url
            ),
            'sha256'
        ),
        'hex'
    ),
    metadata = (ca.metadata - 'note' - 'source_date_precision') || jsonb_build_object(
        'date_evidence', 'official_sse_implementation_announcement',
        'announcement_time_precision', 'date',
        'available_at_policy', 'next_session_open_after_date_only_announcement',
        'exact_action_dates_verified', true,
        'record_hash_version', 'corporate_action_v2',
        'legacy_proxy_price_bridge_only', true,
        'native_ledger_status', 'exact_dates_pending_exact_ex_date_reinvestment_price'
    )
from action_evidence a
join raw.documents d on d.source_url = a.source_url
where ca.security_id = (
        select security_id from master.securities where security_code = '600519.SH'
    )
  and ca.action_type = a.action_type
  and ca.cash_amount_per_share = a.cash_amount;

-- Honest, machine-readable unresolved boundaries.
insert into audit.data_quality_issues (
    severity, domain, table_name, record_key, rule_code, description, status, details
)
select
    'warning',
    'evidence',
    'raw.documents',
    'KWEICHOW_MOUTAI:OFFICIAL_FILINGS',
    'OFFICIAL_FILING_BINARY_NOT_ARCHIVED',
    'First-party SSE filing URLs are registered, but the original PDF bytes and SHA-256 hashes are not yet archived in project-controlled storage.',
    'open',
    jsonb_build_object(
        'required_before_formal_backtest', true,
        'affected_documents', jsonb_build_array('2020 annual report','2021 half-year report','post-cutoff distribution implementation announcements')
    )
where not exists (
    select 1 from audit.data_quality_issues
    where rule_code = 'OFFICIAL_FILING_BINARY_NOT_ARCHIVED'
      and record_key = 'KWEICHOW_MOUTAI:OFFICIAL_FILINGS'
      and status <> 'resolved'
);

insert into audit.data_quality_issues (
    severity, domain, table_name, record_key, rule_code, description, status, details
)
select
    'warning',
    'market_data',
    'pit.market_bars',
    '600519.SH:2021-08-30:CLOSE',
    'MARKET_CLOSE_PROVISIONAL',
    'The 2021-08-30 close of CNY 1,586 is cross-checked but not yet backed by an archived authoritative exchange market-data record.',
    'open',
    jsonb_build_object('required_before_formal_backtest', true, 'observed_close', 1586)
where not exists (
    select 1 from audit.data_quality_issues
    where rule_code = 'MARKET_CLOSE_PROVISIONAL'
      and record_key = '600519.SH:2021-08-30:CLOSE'
      and status <> 'resolved'
);

insert into audit.data_quality_issues (
    severity, domain, table_name, record_key, rule_code, description, status, details
)
select
    'warning',
    'corporate_actions',
    'pit.corporate_actions',
    '600519.SH:2022-2026:DIVIDEND_REINVESTMENT',
    'CORPORATE_ACTION_REINVESTMENT_PRICE_PROXY',
    'Cash amounts and action dates are now tied to implementation announcements, but dividend reinvestment prices remain legacy proxies rather than exact ex-date executable prices.',
    'open',
    jsonb_build_object('required_before_formal_backtest', true, 'exact_action_count', 9)
where not exists (
    select 1 from audit.data_quality_issues
    where rule_code = 'CORPORATE_ACTION_REINVESTMENT_PRICE_PROXY'
      and record_key = '600519.SH:2022-2026:DIVIDEND_REINVESTMENT'
      and status <> 'resolved'
);

insert into audit.data_quality_issues (
    severity, domain, table_name, record_key, rule_code, description, status, details
)
select
    'warning',
    'backtest',
    'pit.market_bars',
    '600519.SH:2021-2026:DAILY_TOTAL_RETURN',
    'DAILY_TOTAL_RETURN_SERIES_PENDING',
    'A complete daily unadjusted price series is still required for exact dividend reinvestment, volatility and maximum-drawdown calculations.',
    'open',
    jsonb_build_object('required_before_formal_backtest', true)
where not exists (
    select 1 from audit.data_quality_issues
    where rule_code = 'DAILY_TOTAL_RETURN_SERIES_PENDING'
      and record_key = '600519.SH:2021-2026:DAILY_TOTAL_RETURN'
      and status <> 'resolved'
);

commit;
