"""Immutable raw-evidence retrieval and local archival primitives.

Only official/free endpoints configured in ``SOURCE_HOSTS`` are accepted. The
module intentionally performs no parsing: exact bytes are hashed and retained
before any source-specific parser is allowed to interpret them.
"""
from __future__ import annotations

import hashlib
import os
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Mapping, Protocol
from urllib.parse import urlparse
from urllib.request import Request, urlopen


SOURCE_HOSTS: Mapping[str, tuple[str, ...]] = {
    "SSE": ("sse.com.cn",),
    "SZSE": ("szse.cn",),
    "CNINFO": ("cninfo.com.cn",),
    "HKEXNEWS": ("hkexnews.hk",),
    "HKEX": ("hkex.com.hk",),
    "TENCENT_IR": ("tencent.com",),
}


class ResponseLike(Protocol):
    headers: Mapping[str, str]

    def read(self, amount: int = -1) -> bytes: ...

    def geturl(self) -> str: ...

    def __enter__(self) -> "ResponseLike": ...

    def __exit__(self, *args: object) -> None: ...


OpenUrl = Callable[..., ResponseLike]


@dataclass(frozen=True)
class EvidenceBlob:
    source_code: str
    requested_url: str
    final_url: str
    retrieved_at: datetime
    media_type: str
    content_sha256: str
    size_bytes: int
    content: bytes

    def manifest(self) -> dict[str, object]:
        return {
            "source_code": self.source_code,
            "requested_url": self.requested_url,
            "final_url": self.final_url,
            "retrieved_at": self.retrieved_at.isoformat(),
            "media_type": self.media_type,
            "content_sha256": self.content_sha256,
            "size_bytes": self.size_bytes,
        }


def _host_allowed(host: str | None, allowed_hosts: tuple[str, ...]) -> bool:
    if not host:
        return False
    normalized = host.lower().rstrip(".")
    return any(
        normalized == allowed or normalized.endswith(f".{allowed}")
        for allowed in allowed_hosts
    )


def fetch_evidence(
    source_code: str,
    url: str,
    *,
    expected_sha256: str | None = None,
    max_bytes: int = 50 * 1024 * 1024,
    timeout_seconds: float = 30.0,
    opener: OpenUrl = urlopen,
) -> EvidenceBlob:
    """Retrieve and hash exact evidence bytes.

    Redirects are permitted only when the final host remains inside the same
    source allowlist. The body is read with a hard byte limit.
    """
    if max_bytes <= 0:
        raise ValueError("max_bytes must be positive")
    try:
        allowed_hosts = SOURCE_HOSTS[source_code]
    except KeyError as exc:
        raise ValueError(f"unknown or unapproved source_code: {source_code}") from exc

    parsed = urlparse(url)
    if parsed.scheme != "https":
        raise ValueError("evidence URLs must use HTTPS")
    if not _host_allowed(parsed.hostname, allowed_hosts):
        raise ValueError(
            f"host {parsed.hostname!r} is not approved for {source_code}"
        )

    request = Request(
        url,
        headers={
            "User-Agent": (
                "value-investing-valuation-system/1.2 "
                "(+private reproducible research)"
            ),
            "Accept": (
                "application/pdf,text/html,application/json,text/plain,*/*;q=0.1"
            ),
        },
    )
    with opener(request, timeout=timeout_seconds) as response:
        final_url = response.geturl()
        final_parsed = urlparse(final_url)
        if final_parsed.scheme != "https" or not _host_allowed(
            final_parsed.hostname, allowed_hosts
        ):
            raise ValueError("redirected to an unapproved evidence host")
        content_length = response.headers.get("Content-Length")
        if content_length is not None and int(content_length) > max_bytes:
            raise ValueError("evidence file exceeds configured size limit")
        content = response.read(max_bytes + 1)
        if len(content) > max_bytes:
            raise ValueError("evidence file exceeds configured size limit")
        content_type = response.headers.get(
            "Content-Type", "application/octet-stream"
        ).split(";", 1)[0].strip().lower()

    digest = hashlib.sha256(content).hexdigest()
    if expected_sha256 and digest.lower() != expected_sha256.lower():
        raise ValueError(
            f"evidence hash mismatch: expected {expected_sha256}, got {digest}"
        )
    return EvidenceBlob(
        source_code=source_code,
        requested_url=url,
        final_url=final_url,
        retrieved_at=datetime.now(timezone.utc),
        media_type=content_type,
        content_sha256=digest,
        size_bytes=len(content),
        content=content,
    )


def archive_evidence(blob: EvidenceBlob, root: str | Path) -> Path:
    """Write evidence bytes once under a content-addressed path.

    Existing objects are verified and never overwritten. A temporary file plus
    atomic rename prevents partially written evidence objects.
    """
    root_path = Path(root)
    target = (
        root_path
        / "sha256"
        / blob.content_sha256[:2]
        / blob.content_sha256
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        existing_digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if existing_digest != blob.content_sha256:
            raise ValueError("existing archive object has an invalid hash")
        return target

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{blob.content_sha256}.",
        dir=target.parent,
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(blob.content)
            handle.flush()
            os.fsync(handle.fileno())
        temporary_path = Path(temporary_name)
        written_digest = hashlib.sha256(temporary_path.read_bytes()).hexdigest()
        if written_digest != blob.content_sha256:
            raise ValueError("archive write verification failed")
        temporary_path.replace(target)
    finally:
        temporary_path = Path(temporary_name)
        if temporary_path.exists():
            temporary_path.unlink()
    return target
