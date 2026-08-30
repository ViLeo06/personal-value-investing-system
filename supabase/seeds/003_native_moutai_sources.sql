begin;

insert into raw.data_sources (
    source_code,name,source_type,homepage_url,is_free,is_open_source,
    pit_capability,priority,notes
) values
('CNSTOCK_ARCHIVE','上海证券报信息披露归档','official_disclosure_archive',
 'https://paper.cnstock.com/',true,false,'derived',20,
 'Historical disclosure title/time archive; numeric facts require filing or archive cross-check.'),
('SINA_FINANCE_ARCHIVE','新浪财经上市公司公告归档','historical_financial_archive',
 'https://vip.stock.finance.sina.com.cn/',true,false,'derived',40,
 'Free historical filing mirror used for numeric cross-checks; not the authoritative PIT ledger.'),
('JIEMIAN_ARCHIVE','界面新闻历史行情叙述归档','historical_news_archive',
 'https://www.jiemian.com/',true,false,'derived',60,
 'Historical price narrative cross-check; not an authoritative daily market-data supplier.')
on conflict (source_code) do update set
    name=excluded.name,
    source_type=excluded.source_type,
    homepage_url=excluded.homepage_url,
    is_free=excluded.is_free,
    is_open_source=excluded.is_open_source,
    pit_capability=excluded.pit_capability,
    priority=excluded.priority,
    notes=excluded.notes;

-- Preserve the official annual-report reference when it is not already seeded.
insert into raw.documents (
    source_id,issuer_id,document_type,title,source_url,mime_type,language,
    published_at,effective_date,parser_version,metadata
)
select ds.source_id,i.issuer_id,'annual_report','贵州茅台2020年年度报告',
       'https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf',
       'application/pdf','zh-CN','2021-03-31 00:00:00+08','2020-12-31',
       'manual_reference_v1',
       '{"gate":"gate0","evidence_status":"metadata_verified","publication_date_precision":"date"}'::jsonb
from raw.data_sources ds
join master.issuers i on i.issuer_code='KWEICHOW_MOUTAI'
where ds.source_code='SSE'
  and not exists (
      select 1 from raw.documents d
      where d.source_url='https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf'
  );

insert into raw.documents (
    source_id,issuer_id,document_type,title,source_url,mime_type,language,
    published_at,effective_date,content_hash,parser_version,metadata
)
select ds.source_id,i.issuer_id,'half_year_report_publication',
       '贵州茅台酒股份有限公司2021年半年度报告（披露归档）',
       'https://paper.cnstock.com/html/2021-07/31/content_1501967.htm',
       'text/html','zh-CN','2021-07-30 19:34:00+08','2021-06-30',
       '8527c8faba38d77c8ecdc13a4e567b9424940440790528921a93f43a16f06011',
       'manual_archive_v1',
       '{"evidence_role":"publication_event","after_market_close":true,"next_usable_session":"2021-08-02T09:30:00+08:00"}'::jsonb
from raw.data_sources ds
join master.issuers i on i.issuer_code='KWEICHOW_MOUTAI'
where ds.source_code='CNSTOCK_ARCHIVE'
on conflict (content_hash) where content_hash is not null do nothing;

insert into raw.documents (
    source_id,issuer_id,document_type,title,source_url,mime_type,language,
    published_at,effective_date,content_hash,parser_version,metadata
)
select ds.source_id,i.issuer_id,'half_year_report_numeric_archive',
       '贵州茅台2021年半年度报告数值归档',
       'https://vip.stock.finance.sina.com.cn/corp/view/vCB_AllBulletinDetail.php?id=7409759&stockid=600519',
       'text/html','zh-CN','2021-07-30 19:34:00+08','2021-06-30',
       '709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71',
       'manual_archive_v1',
       '{"evidence_role":"numeric_cross_check","authoritative":false,"free_source":true}'::jsonb
from raw.data_sources ds
join master.issuers i on i.issuer_code='KWEICHOW_MOUTAI'
where ds.source_code='SINA_FINANCE_ARCHIVE'
on conflict (content_hash) where content_hash is not null do nothing;

insert into raw.documents (
    source_id,issuer_id,security_id,document_type,title,source_url,mime_type,language,
    published_at,effective_date,content_hash,parser_version,metadata
)
select ds.source_id,i.issuer_id,s.security_id,'historical_price_cross_check',
       '贵州茅台2021-08-30收盘价历史叙述交叉验证',
       'https://www.jiemian.com/article/6896977.html',
       'text/html','zh-CN','2021-12-08 13:47:00+08','2021-08-30',
       'c7a935619b026f92f45978727d0d1c3535416f25bd667fd6a5b527625a38661a',
       'manual_archive_v1',
       '{"evidence_role":"historical_price_cross_check","reported_close":1586.0,"source_published_after_decision":true,"authoritative":false}'::jsonb
from raw.data_sources ds
join master.issuers i on i.issuer_code='KWEICHOW_MOUTAI'
join master.securities s on s.issuer_id=i.issuer_id and s.security_code='600519.SH'
where ds.source_code='JIEMIAN_ARCHIVE'
on conflict (content_hash) where content_hash is not null do nothing;

commit;
