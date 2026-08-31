#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Any
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen

from pypdf import PdfReader


OUTPUT_DIR = Path("data/raw/gate0/moutai/official/2020-annual-report")
QUERY_URL = "https://www.cninfo.com.cn/new/hisAnnouncement/query"
STATIC_ROOT = "https://static.cninfo.com.cn/"
USER_AGENT = "Mozilla/5.0 value-investing-valuation-system/1.2 PIT evidence capture"

KEYWORDS = (
    "折旧",
    "摊销",
    "固定资产折旧",
    "无形资产摊销",
    "长期待摊费用摊销",
    "购建固定资产",
    "无形资产和其他长期资产支付的现金",
    "资本开支",
    "货币资金",
    "交易性金融资产",
    "短期借款",
    "长期借款",
    "应付债券",
    "股本",
    "股份总数",
    "存货",
    "应收账款",
    "应付账款",
    "合同负债",
    "经营活动产生的现金流量净额",
)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def post_form(url: str, values: dict[str, Any]) -> Any:
    body = urlencode(values).encode("utf-8")
    request = Request(
        url,
        data=body,
        method="POST",
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/json,text/plain,*/*",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Referer": "https://www.cninfo.com.cn/new/commonUrl/pageOfSearch?url=disclosure/list/search",
            "Origin": "https://www.cninfo.com.cn",
            "X-Requested-With": "XMLHttpRequest",
        },
    )
    with urlopen(request, timeout=45) as response:
        raw = response.read()
        if response.status != 200:
            raise RuntimeError(f"CNINFO query HTTP {response.status}")
    return json.loads(raw.decode("utf-8"))


def get_bytes(url: str) -> bytes:
    request = Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/pdf,*/*",
            "Referer": "https://www.cninfo.com.cn/",
        },
    )
    with urlopen(request, timeout=120) as response:
        raw = response.read()
        if response.status != 200:
            raise RuntimeError(f"PDF HTTP {response.status}")
    if not raw.startswith(b"%PDF"):
        raise RuntimeError("Downloaded object is not a PDF")
    return raw


def select_report(payload: Any) -> dict[str, Any]:
    announcements = (payload or {}).get("announcements") or []
    candidates: list[dict[str, Any]] = []
    for item in announcements:
        title = re.sub(r"<[^>]+>", "", str(item.get("announcementTitle") or ""))
        if "2020年年度报告" not in title:
            continue
        if any(excluded in title for excluded in ("摘要", "英文", "更正", "修订")):
            continue
        candidates.append({**item, "cleanTitle": title})
    if not candidates:
        raise RuntimeError("No full 2020 annual report found in CNINFO response")
    return sorted(candidates, key=lambda item: int(item.get("announcementTime") or 0))[0]


def context_snippets(text: str, keyword: str, radius: int = 300) -> list[str]:
    snippets: list[str] = []
    start = 0
    while True:
        index = text.find(keyword, start)
        if index < 0:
            break
        left = max(0, index - radius)
        right = min(len(text), index + len(keyword) + radius)
        snippet = re.sub(r"\s+", " ", text[left:right]).strip()
        snippets.append(snippet)
        start = index + len(keyword)
        if len(snippets) >= 5:
            break
    return snippets


def build_page_index(pdf_path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    reader = PdfReader(str(pdf_path))
    pages: list[dict[str, Any]] = []
    hits: list[dict[str, Any]] = []
    for page_number, page in enumerate(reader.pages, 1):
        text = page.extract_text() or ""
        normalized = re.sub(r"[\u0000-\u001f]+", " ", text)
        page_hash = sha256(normalized.encode("utf-8")).hexdigest()
        matched_keywords = [keyword for keyword in KEYWORDS if keyword in normalized]
        pages.append(
            {
                "page": page_number,
                "text_sha256": page_hash,
                "characters": len(normalized),
                "keywords": matched_keywords,
            }
        )
        for keyword in matched_keywords:
            hits.append(
                {
                    "page": page_number,
                    "keyword": keyword,
                    "snippets": context_snippets(normalized, keyword),
                    "page_text_sha256": page_hash,
                }
            )
    return pages, hits


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    attempt = {
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "query_url": QUERY_URL,
        "status": "started",
        "error": None,
    }
    try:
        query_payload = post_form(
            QUERY_URL,
            {
                "pageNum": 1,
                "pageSize": 30,
                "column": "sse",
                "tabName": "fulltext",
                "plate": "sh",
                "stock": "600519,gssh0600519",
                "searchkey": "",
                "secid": "",
                "category": "category_ndbg_szsh;",
                "trade": "",
                "seDate": "2021-03-01~2021-04-30",
                "sortName": "",
                "sortType": "",
                "isHLtitle": "true",
            },
        )
        write_json(OUTPUT_DIR / "cninfo_query_response.json", query_payload)
        report = select_report(query_payload)
        adjunct_url = str(report.get("adjunctUrl") or "").lstrip("/")
        if not adjunct_url:
            raise RuntimeError("CNINFO result has no adjunctUrl")
        pdf_url = urljoin(STATIC_ROOT, adjunct_url)
        pdf_bytes = get_bytes(pdf_url)
        pdf_path = OUTPUT_DIR / "kweichow_moutai_2020_annual_report.pdf"
        pdf_path.write_bytes(pdf_bytes)
        pages, hits = build_page_index(pdf_path)
        write_json(OUTPUT_DIR / "page_index.json", pages)
        write_json(OUTPUT_DIR / "financial_keyword_hits.json", hits)
        metadata = {
            "issuer_code": "KWEICHOW_MOUTAI",
            "security_code": "600519.SH",
            "announcement_id": report.get("announcementId"),
            "announcement_title": report.get("cleanTitle"),
            "announcement_time_epoch_ms": report.get("announcementTime"),
            "adjunct_url": adjunct_url,
            "pdf_url": pdf_url,
            "pdf_sha256": sha256(pdf_bytes).hexdigest(),
            "pdf_bytes": len(pdf_bytes),
            "page_count": len(pages),
            "keyword_hit_count": len(hits),
            "evidence_grade_candidate": 3,
            "source_code": "CNINFO",
            "parser": "pypdf-5.4.0",
        }
        write_json(OUTPUT_DIR / "metadata.json", metadata)
        attempt.update(
            {
                "status": "success",
                "pdf_url": pdf_url,
                "pdf_sha256": metadata["pdf_sha256"],
                "page_count": len(pages),
                "keyword_hit_count": len(hits),
            }
        )
    except Exception as exc:  # noqa: BLE001 - attempt record must survive failures
        attempt.update({"status": "failed", "error": repr(exc)})
    write_json(OUTPUT_DIR / "attempt.json", attempt)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
