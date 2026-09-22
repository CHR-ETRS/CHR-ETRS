"""Process clock so business-rule windows are testable without waiting for night."""
from __future__ import annotations

from datetime import datetime, timezone

_fixed: datetime | None = None


def set_fixed(value: datetime | None) -> None:
    global _fixed
    _fixed = value


def now_utc() -> datetime:
    if _fixed is None:
        return datetime.now(timezone.utc)
    if _fixed.tzinfo is None:
        return _fixed.replace(tzinfo=timezone.utc)
    return _fixed.astimezone(timezone.utc)
