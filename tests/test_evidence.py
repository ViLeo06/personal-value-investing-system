import hashlib
from pathlib import Path
from urllib.request import Request

import pytest

from value_investing.evidence import EvidenceBlob, archive_evidence, fetch_evidence


class FakeResponse:
    def __init__(self, content: bytes, final_url: str, content_type: str = "application/pdf"):
        self._content = content
        self._final_url = final_url
        self.headers = {
            "Content-Length": str(len(content)),
            "Content-Type": content_type,
        }

    def read(self, amount: int = -1) -> bytes:
        return self._content if amount < 0 else self._content[:amount]

    def geturl(self) -> str:
        return self._final_url

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None


def fake_opener(content: bytes, final_url: str):
    def open_url(request: Request, *, timeout: float):
        assert isinstance(request, Request)
        assert timeout > 0
        return FakeResponse(content, final_url)

    return open_url


def test_fetch_evidence_hashes_exact_bytes():
    content = b"%PDF-1.7\nimmutable evidence"
    expected = hashlib.sha256(content).hexdigest()
    blob = fetch_evidence(
        "SSE",
        "https://static.sse.com.cn/disclosure/example.pdf",
        expected_sha256=expected,
        opener=fake_opener(
            content,
            "https://static.sse.com.cn/disclosure/example.pdf",
        ),
    )
    assert blob.content == content
    assert blob.content_sha256 == expected
    assert blob.size_bytes == len(content)
    assert blob.media_type == "application/pdf"


def test_unapproved_host_or_insecure_scheme_is_rejected():
    with pytest.raises(ValueError):
        fetch_evidence("SSE", "http://static.sse.com.cn/file.pdf")
    with pytest.raises(ValueError):
        fetch_evidence("SSE", "https://example.com/file.pdf")
    with pytest.raises(ValueError):
        fetch_evidence("UNKNOWN", "https://example.com/file.pdf")


def test_redirect_to_unapproved_host_is_rejected():
    with pytest.raises(ValueError):
        fetch_evidence(
            "SSE",
            "https://static.sse.com.cn/file.pdf",
            opener=fake_opener(b"bytes", "https://evil.example/file.pdf"),
        )


def test_byte_limit_and_expected_hash_are_enforced():
    with pytest.raises(ValueError):
        fetch_evidence(
            "SSE",
            "https://static.sse.com.cn/file.pdf",
            max_bytes=3,
            opener=fake_opener(b"four", "https://static.sse.com.cn/file.pdf"),
        )
    with pytest.raises(ValueError):
        fetch_evidence(
            "SSE",
            "https://static.sse.com.cn/file.pdf",
            expected_sha256="0" * 64,
            opener=fake_opener(b"bytes", "https://static.sse.com.cn/file.pdf"),
        )


def test_archive_is_content_addressed_idempotent_and_tamper_evident(tmp_path):
    content = b"official filing bytes"
    digest = hashlib.sha256(content).hexdigest()
    blob = EvidenceBlob(
        source_code="SSE",
        requested_url="https://static.sse.com.cn/a.pdf",
        final_url="https://static.sse.com.cn/a.pdf",
        retrieved_at=__import__("datetime").datetime.now(
            __import__("datetime").timezone.utc
        ),
        media_type="application/pdf",
        content_sha256=digest,
        size_bytes=len(content),
        content=content,
    )
    first = archive_evidence(blob, tmp_path)
    second = archive_evidence(blob, tmp_path)
    assert first == second
    assert first.read_bytes() == content
    assert first == tmp_path / "sha256" / digest[:2] / digest

    first.write_bytes(b"tampered")
    with pytest.raises(ValueError):
        archive_evidence(blob, tmp_path)
