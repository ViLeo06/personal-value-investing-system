begin;

insert into raw.data_sources (
    source_code,name,source_type,homepage_url,is_free,is_open_source,
    pit_capability,priority,notes
) values (
    'TENCENT_IR','Tencent investor-relations release archive',
    'issuer_investor_relations','https://www.tencent.com/en-us/investors.html',
    true,false,'native',15,
    'Issuer-issued results releases; official filing bytes should be archived separately when available.'
)
on conflict (source_code) do update set
    name=excluded.name,source_type=excluded.source_type,
    homepage_url=excluded.homepage_url,is_free=excluded.is_free,
    is_open_source=excluded.is_open_source,pit_capability=excluded.pit_capability,
    priority=excluded.priority,notes=excluded.notes;

insert into fundamentals.metric_definitions
    (metric_code,name_cn,name_en,statement_type,default_unit,description)
values
    ('total_cash','现金及短期投资总额','Total cash','balance_sheet','currency',
     'Issuer-defined total cash measure; definition and components must be retained in provenance.'),
    ('listed_investee_fair_value','上市投资公允价值','Fair value of listed investees','investment_schedule','currency',
     'Fair value of listed investee stakes used only through a separately documented SOTP bridge.'),
    ('annualized_revenue','年化收入锚','Annualized revenue anchor','normalization','currency',
     'Interim revenue annualized under an explicit policy for valuation anchoring; not a reported full-year fact.'),
    ('operating_margin','经营利润率','Operating margin','normalization','ratio',
     'Operating profit divided by revenue under a versioned definition.'),
    ('adjusted_net_income_parent','扣非归母净利润','Adjusted parent net income','income_statement','currency',
     'Parent-attributable net income after issuer-defined non-recurring adjustments.'),
    ('profit_before_tax','税前利润','Profit before tax','income_statement','currency',
     'Reported or reconstructed profit before income tax.'),
    ('income_tax_expense','所得税费用','Income tax expense','income_statement','currency',
     'Reported income-tax expense.'),
    ('short_term_borrowings','短期借款','Short-term borrowings','balance_sheet','currency',
     'Interest-bearing short-term borrowings.'),
    ('current_noncurrent_debt','一年内到期的非流动负债','Current portion of non-current debt','balance_sheet','currency',
     'Current portion of non-current interest-bearing liabilities.'),
    ('long_term_borrowings','长期借款','Long-term borrowings','balance_sheet','currency',
     'Interest-bearing long-term borrowings.'),
    ('bonds_payable','应付债券','Bonds payable','balance_sheet','currency',
     'Interest-bearing bonds payable.'),
    ('lease_liabilities','租赁负债','Lease liabilities','balance_sheet','currency',
     'Current and non-current lease liabilities included in the valuation debt bridge.'),
    ('minority_interest','少数股东权益','Minority interest','balance_sheet','currency',
     'Equity attributable to non-controlling interests.'),
    ('interest_bearing_debt','有息负债','Interest-bearing debt','normalization','currency',
     'Versioned sum of debt components included in the equity bridge.'),
    ('equity_bridge','股权价值桥接项','Equity bridge','valuation_input','currency',
     'Non-operating assets less debt, minority interest and other claims applied to enterprise value.')
on conflict (metric_code) do update set
    name_cn=excluded.name_cn,name_en=excluded.name_en,
    statement_type=excluded.statement_type,default_unit=excluded.default_unit,
    description=excluded.description;

insert into raw.documents (
    source_id,issuer_id,security_id,document_type,title,source_url,mime_type,
    language,published_at,available_at,effective_date,parser_version,
    publication_precision,evidence_quality,metadata
)
select ds.source_id,i.issuer_id,s.security_id,'half_year_results_release',
       'Tencent 2021 second-quarter and interim results release',
       'https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
       'text/html','en','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08',
       date '2021-06-30','manual_issuer_release_reference_v1','date','official_reference',
       jsonb_build_object(
           'gate','gate0','binary_archived',false,
           'evidence_status','issuer_release_url_verified',
           'availability_policy','availability_policy_v1',
           'next_usable_session','2021-08-19T09:30:00+08:00',
           'delivery_platform','PR Newswire'
       )
from raw.data_sources ds
join master.issuers i on i.issuer_code='TENCENT'
join master.securities s on s.issuer_id=i.issuer_id and s.security_code='0700.HK'
where ds.source_code='TENCENT_IR'
  and not exists (
      select 1 from raw.documents d
      where d.source_url='https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html'
  );

insert into raw.documents (
    source_id,issuer_id,security_id,document_type,title,source_url,mime_type,
    language,published_at,available_at,effective_date,parser_version,
    publication_precision,evidence_quality,metadata
)
select ds.source_id,i.issuer_id,s.security_id,'half_year_report',
       '比亚迪股份有限公司2021年半年度报告',
       'https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF',
       'application/pdf','zh-CN','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08',
       date '2021-06-30','manual_official_reference_v1','date','official_reference',
       jsonb_build_object(
           'gate','gate0','binary_archived',false,
           'evidence_status','official_url_verified',
           'availability_policy','availability_policy_v1',
           'next_usable_session','2021-08-30T09:30:00+08:00',
           'readable_mirror','https://money.finance.sina.com.cn/corp/view/vCB_AllBulletinDetail.php?id=7502467&stockid=002594'
       )
from raw.data_sources ds
join master.issuers i on i.issuer_code='BYD'
join master.securities s on s.issuer_id=i.issuer_id and s.security_code='002594.SZ'
where ds.source_code='CNINFO'
  and not exists (
      select 1 from raw.documents d
      where d.source_url='https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF'
  );

with rows(
    issuer_code,source_url,statement_type,metric_code,metric_label,
    period_start,period_end,fiscal_year,fiscal_period,fact_kind,
    value_numeric,unit,currency,published_at,available_at,
    source_fact_key,record_hash,metadata
) as (
    values
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'income_statement','revenue','Revenue',date '2021-01-01',date '2021-06-30',2021,'H1','duration',273562000000,'CNY','CNY','2021-08-18 00:00:00+08'::timestamptz,'2021-08-19 09:30:00+08'::timestamptz,'2021H1:revenue','07d47f0ef702692ac8563792d7bbbb335b2971d3da6262116f783f35504899dd','{"source_section":"2021 interim financial highlights","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'non_ifrs_income_statement','operating_income','Non-IFRS operating profit',date '2021-01-01',date '2021-06-30',2021,'H1','duration',85600000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021H1:non_ifrs_operating_profit','c94b71b89189a8cb8785b0f2f88115fa5be8a8d3873db5ea670c4e058e71129c','{"accounting_basis":"non-IFRS","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'income_statement','net_income_parent','Profit attributable to equity holders',date '2021-01-01',date '2021-06-30',2021,'H1','duration',90354000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021H1:net_income_parent','d8fb43b1b0075dc5ffef7a94b08f49a1d90c7c14a2fb79a98170dd9053df365b','{"accounting_basis":"IFRS","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'income_statement','basic_eps','Basic EPS',date '2021-01-01',date '2021-06-30',2021,'H1','duration',9.492,'CNY/share','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021H1:basic_eps','908b64f2e220baebaf330bbda11c9919dd59d85bd608f1c24829d06f2b840f04','{"accounting_basis":"IFRS","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'balance_sheet','total_cash','Total cash',null,date '2021-06-30',2021,'H1','instant',255200000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021H1:total_cash','7a9f1e4f485f672ecbcb637ada44ed52f94a4569c6d1fa8ab733bc56c23098da','{"issuer_defined_measure":true,"evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'balance_sheet','net_debt','Net debt',null,date '2021-06-30',2021,'H1','instant',21000000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021H1:net_debt','23fa362aeabc9eb17977ab76687b68f8e2fe84d7773f132b8d715d86b3f6742f','{"issuer_defined_measure":true,"evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'investment_schedule','listed_investee_fair_value','Fair value of listed investee stakes',null,date '2021-06-30',2021,'H1','instant',1446000000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021H1:listed_investee_fair_value','ca11c23b1154c3a73c2557dfdc3a335be1f121b5c6e993ae6fdfae0f5cadeff5','{"used_in":"SOTP","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'segment','segment_revenue','Value Added Services revenue',date '2021-04-01',date '2021-06-30',2021,'Q2','duration',72000000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021Q2:segment_revenue:VAS','842c2dde6b6a0c251c6aa527fe9f4c5a0df40b00af7806fc2090ed8840330c9d','{"segment_code":"VAS","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'segment','segment_revenue','Online Advertising revenue',date '2021-04-01',date '2021-06-30',2021,'Q2','duration',22800000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021Q2:segment_revenue:online_advertising','4a174e185a25bcbf3596e75ee4dffc79b40560adea2af3c196bd7e543d9dba16','{"segment_code":"ONLINE_ADVERTISING","evidence_quality":"official_reference"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html',
     'segment','segment_revenue','FinTech and Business Services revenue',date '2021-04-01',date '2021-06-30',2021,'Q2','duration',41900000000,'CNY','CNY','2021-08-18 00:00:00+08','2021-08-19 09:30:00+08','2021Q2:segment_revenue:fintech_business_services','806b24183cfc8e58f88594c26c014c90522d354d289dab15df9ae3325d097ca1','{"segment_code":"FINTECH_BUSINESS_SERVICES","evidence_quality":"official_reference"}'::jsonb),

    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','income_statement','revenue','营业收入',date '2021-01-01',date '2021-06-30',2021,'H1','duration',90885400000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:revenue','b1b6201020b29354e5d75e87c6423378dc1402d89482bafe17ce0625f17efa1e','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','income_statement','net_income_parent','归属于上市公司股东的净利润',date '2021-01-01',date '2021-06-30',2021,'H1','duration',1173571000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:net_income_parent','d51d2668a0538ffa13f4f62127dc02989e4e9c9ba844a2d3bd97edefa641ea08','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','income_statement','adjusted_net_income_parent','扣除非经常性损益后的归母净利润',date '2021-01-01',date '2021-06-30',2021,'H1','duration',368666000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:adjusted_net_income_parent','caa9d47a87b8ccefa8bad9c85302fae00653012da85998a8c2ca9969e3db89eb','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','cash_flow','operating_cash_flow','经营活动产生的现金流量净额',date '2021-01-01',date '2021-06-30',2021,'H1','duration',9676845000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:operating_cash_flow','7d644d64a468760214143fa7bd28827faf2dda862d49aff66b1c17f0957cba56','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','income_statement','profit_before_tax','税前利润',date '2021-01-01',date '2021-06-30',2021,'H1','duration',2204115000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:profit_before_tax','1cf6ad9dee11f6e5f5d935ac77f457dd831950ff019c85be62f463bd6fb704ef','{"used_as":"temporary_operating_profit_proxy","evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','income_statement','income_tax_expense','所得税费用',date '2021-01-01',date '2021-06-30',2021,'H1','duration',393344000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:income_tax_expense','0572c2bb15ae5867b80b346202186109ad40671aa2df8de1b2bf9cacda6835c6','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','cash_flow','capital_expenditure','资本开支',date '2021-01-01',date '2021-06-30',2021,'H1','duration',11132530000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:capital_expenditure','9cbbad7ea8d47bacc921f0af3f7fe4bdef4895a8ab7e7e796c1b955b64d5eb7a','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','cash_flow','depreciation_amortization','折旧与摊销',date '2021-01-01',date '2021-06-30',2021,'H1','duration',6395985000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:depreciation_amortization','4c03c2cbe58772fc20187c421d6f0941e354eb68183e951c001f88c8f8bc34b7','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','cash_and_equivalents','现金及现金等价物',null,date '2021-06-30',2021,'H1','instant',21152299000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:cash_and_equivalents','5877e2638e58f2747394b65fceb3c5e0150fc29eca0db90114924f321ddb4524','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','short_term_borrowings','短期借款',null,date '2021-06-30',2021,'H1','instant',11256556000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:short_term_borrowings','46dfb8348622eb3886704041f058959c0e2ee3397faabd28adaa27c708500498','{"debt_bridge":true,"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','current_noncurrent_debt','一年内到期的非流动负债',null,date '2021-06-30',2021,'H1','instant',14260446000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:current_noncurrent_debt','a7fe465472214892f3face01445893bd737caed2adcf4ea3a83d4f65fd2d9982','{"debt_bridge":true,"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','long_term_borrowings','长期借款',null,date '2021-06-30',2021,'H1','instant',10198931000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:long_term_borrowings','d4c3a42c5967ffafcba11208d6121659cf7f496709dd7814bcc4e5420c949d63','{"debt_bridge":true,"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','bonds_payable','应付债券',null,date '2021-06-30',2021,'H1','instant',4490423000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:bonds_payable','c964f6f342702a9a8aae98ee3f3416be7eaf032b2a4e4c24fcecbdb7c3dad2cd','{"debt_bridge":true,"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','lease_liabilities','租赁负债',null,date '2021-06-30',2021,'H1','instant',1066963000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:lease_liabilities','b5c316fea11b0d206ad73ebe2b9d7f92398c32ede08cc90cf1c0af772cfe4da7','{"debt_bridge":true,"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','minority_interest','少数股东权益',null,date '2021-06-30',2021,'H1','instant',8030113000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:minority_interest','6795139eaa957f90eee5842ec4b8c5a74602d46d0ce717c8dbbda9be9ace36d4','{"equity_bridge":true,"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','balance_sheet','equity_parent','归属于母公司所有者权益',null,date '2021-06-30',2021,'H1','instant',81255042000,'CNY','CNY','2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:equity_parent','8532ce68eabda7777ed49e0ee6771468d9683dfa9b5dc76221ca7f28a8dcdc2b','{"evidence_quality":"official_reference"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','per_share_denominator','shares_outstanding','期末股份数',null,date '2021-06-30',2021,'H1','instant',2861143000,'shares',null,'2021-08-28 00:00:00+08','2021-08-30 09:30:00+08','2021H1:shares_outstanding','9a683e9ba06f6209d48c2846c21251c8e15c00b4eda116452594f28d24e6e43d','{"evidence_quality":"official_reference"}'::jsonb)
)
insert into pit.financial_facts (
    issuer_id,statement_scope,statement_type,metric_code,metric_label,
    period_start,period_end,fiscal_year,fiscal_period,fact_kind,value_numeric,
    unit,currency,scale,published_at,available_at,revision_no,is_preliminary,
    source_document_id,source_fact_key,record_hash,metadata
)
select i.issuer_id,'consolidated',r.statement_type,r.metric_code,r.metric_label,
       r.period_start,r.period_end,r.fiscal_year,r.fiscal_period,r.fact_kind,
       r.value_numeric,r.unit,r.currency,1,r.published_at,r.available_at,1,false,
       d.document_id,r.source_fact_key,r.record_hash,r.metadata
from rows r
join master.issuers i on i.issuer_code=r.issuer_code
join raw.documents d on d.source_url=r.source_url
on conflict do nothing;

with rows(
    issuer_code,source_url,metric_code,value_numeric,unit,
    normalization_version,available_at,record_hash,metadata
) as (
    values
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html','annualized_revenue',547124000000,'CNY','tencent_platform_normalization_v1','2021-08-19 09:30:00+08'::timestamptz,'4a46ffb5a6f6064861316ac43ae277940b312f82c699e92eec1a76c558fd284f','{"formula":"H1 revenue * 2","diagnostic_only":true}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html','operating_margin',0.31290895665333635,'ratio','tencent_platform_normalization_v1','2021-08-19 09:30:00+08','e1cc10ad3ef00b0e2cbcaba488d5520f216b50232fb620150c8cebd479f05570','{"formula":"non-IFRS operating profit / revenue","accounting_basis":"non-IFRS"}'::jsonb),
    ('TENCENT','https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html','shares_outstanding_inferred',9518963337.547407,'shares','tencent_platform_normalization_v1','2021-08-19 09:30:00+08','b163bf10ebf2170d22662c8cfe1fa5e15a43ac8c2c8f1d4487e8954af659e941','{"formula":"IFRS parent profit / basic EPS","denominator_type":"weighted_average_proxy"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','annualized_revenue',181770800000,'CNY','byd_manufacturing_normalization_v1','2021-08-30 09:30:00+08','402af99e0f81fc344c6c7352dfd6cbf008fb1f95e6769c7114161398125d73a0','{"formula":"H1 revenue * 2","diagnostic_only":true}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','operating_margin',0.024251584963041365,'ratio','byd_manufacturing_normalization_v1','2021-08-30 09:30:00+08','722e00fa6ef38172fa44c31a8d2ed0554dfe52e2a59ea06b18cb57c72f3f3aee','{"formula":"profit before tax / revenue","proxy":true,"upgrade_required":"EBIT reconstruction"}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','tax_rate_normalized',0.17845892795974805,'ratio','byd_manufacturing_normalization_v1','2021-08-30 09:30:00+08','f7de4331f4d574509e00a06a3e566b78579f5d814163393caa7cdc6d902baf56','{"formula":"income tax expense / profit before tax","proxy":true}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','interest_bearing_debt',41273319000,'CNY','byd_manufacturing_normalization_v1','2021-08-30 09:30:00+08','b9dfd7f22d30fb2343bb94a1005127fd91c37eb4f715b0285ba75e770448bf94','{"components":["short_term_borrowings","current_noncurrent_debt","long_term_borrowings","bonds_payable","lease_liabilities"]}'::jsonb),
    ('BYD','https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF','equity_bridge',-28151133000,'CNY','byd_manufacturing_normalization_v1','2021-08-30 09:30:00+08','39539daaa69c087787d1ed395fef7cfaadae8e99687c759f80659eb90bbb267d','{"formula":"cash - interest-bearing debt - minority interest","future_bridge_held_constant":true}'::jsonb)
)
insert into fundamentals.normalized_facts (
    issuer_id,metric_code,period_start,period_end,value_numeric,unit,currency,
    normalization_version,available_at,record_hash,metadata,source_document_id
)
select i.issuer_id,r.metric_code,date '2021-01-01',date '2021-06-30',
       r.value_numeric,r.unit,case when r.unit='CNY' then 'CNY' else null end,
       r.normalization_version,r.available_at,r.record_hash,r.metadata,d.document_id
from rows r
join master.issuers i on i.issuer_code=r.issuer_code
join raw.documents d on d.source_url=r.source_url
on conflict do nothing;

with manifest as (
    select jsonb_build_object(
        'scope','native_tencent_2021_h1_provisional',
        'issuer_code','TENCENT','security_code','0700.HK',
        'decision_cutoff','2021-08-30T16:00:00+08:00',
        'eligible_rule','available_at <= decision_cutoff',
        'cutoff_policy_version','pit_cutoff_v1',
        'financial_fact_count',(select count(*) from pit.financial_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='TENCENT' and f.period_end=date '2021-06-30'),
        'financial_fact_hashes',(select jsonb_agg(f.record_hash order by f.record_hash) from pit.financial_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='TENCENT' and f.period_end=date '2021-06-30'),
        'normalized_fact_count',(select count(*) from fundamentals.normalized_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='TENCENT' and f.normalization_version='tencent_platform_normalization_v1'),
        'normalized_fact_hashes',(select jsonb_agg(f.record_hash order by f.record_hash) from fundamentals.normalized_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='TENCENT' and f.normalization_version='tencent_platform_normalization_v1'),
        'source_document_fingerprints',jsonb_build_array('source_url:https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html'),
        'market_bar_hash','efe4a1a0dd260d186239163bb4078b69fe9239f0e1b109e4130fac26f01718cb',
        'market_close',465.8,'market_available_at','2021-08-30T16:00:00+08:00',
        'fx_proxy',1.2042,'fx_proxy_status','secondary_free_archive_pending_authoritative_replacement',
        'data_quality','provisional','official_report_binary_archived',false,
        'authoritative_market_bar',false,
        'hash_policies',jsonb_build_array('pit_financial_fact_explicit_v2','normalized_fact_explicit_v2','frozen_manifest_sha256_v1')
    ) as value
)
insert into audit.data_snapshots (as_of_at,cutoff_policy_version,manifest,snapshot_hash)
select '2021-08-30 16:00:00+08','pit_cutoff_v1',value,
       encode(digest(value::text,'sha256'),'hex')
from manifest
on conflict (snapshot_hash) do update set manifest=excluded.manifest;

with manifest as (
    select jsonb_build_object(
        'scope','native_byd_2021_h1_provisional',
        'issuer_code','BYD','security_code','002594.SZ',
        'decision_cutoff','2021-08-30T15:00:00+08:00',
        'eligible_rule','available_at <= decision_cutoff',
        'cutoff_policy_version','pit_cutoff_v1',
        'financial_fact_count',(select count(*) from pit.financial_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='BYD' and f.period_end=date '2021-06-30'),
        'financial_fact_hashes',(select jsonb_agg(f.record_hash order by f.record_hash) from pit.financial_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='BYD' and f.period_end=date '2021-06-30'),
        'normalized_fact_count',(select count(*) from fundamentals.normalized_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='BYD' and f.normalization_version='byd_manufacturing_normalization_v1'),
        'normalized_fact_hashes',(select jsonb_agg(f.record_hash order by f.record_hash) from fundamentals.normalized_facts f join master.issuers i on i.issuer_id=f.issuer_id where i.issuer_code='BYD' and f.normalization_version='byd_manufacturing_normalization_v1'),
        'source_document_fingerprints',jsonb_build_array('source_url:https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF'),
        'market_bar_hash','db90c1d4cf8f027d7c5eb6324eda135d70aa0fc2572a4936293f70caa1861e86',
        'market_close',281.97,'market_available_at','2021-08-30T15:00:00+08:00',
        'data_quality','provisional','official_report_binary_archived',false,
        'authoritative_market_bar',false,'operating_profit_proxy','profit_before_tax',
        'hash_policies',jsonb_build_array('pit_financial_fact_explicit_v2','normalized_fact_explicit_v2','frozen_manifest_sha256_v1')
    ) as value
)
insert into audit.data_snapshots (as_of_at,cutoff_policy_version,manifest,snapshot_hash)
select '2021-08-30 15:00:00+08','pit_cutoff_v1',value,
       encode(digest(value::text,'sha256'),'hex')
from manifest
on conflict (snapshot_hash) do update set manifest=excluded.manifest;

commit;
