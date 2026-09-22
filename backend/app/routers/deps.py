"""Auth dependency and domain-error envelope (OpenAPI ErrorResponse)."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from app.services.exceptions import ChrEtrsDomainError, InvalidOAuthToken


def require_bearer(authorization: Optional[str] = Header(default=None)) -> str:
    """MVP bearer check: any non-empty token. Missing/blank → 401."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise InvalidOAuthToken("JWT expired or not authorized.")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise InvalidOAuthToken("JWT expired or not authorized.")
    return token


def _error_body(exc: ChrEtrsDomainError) -> dict:
    body = {
        "error_code": exc.error_code,
        "http_status": exc.http_status,
        "message": exc.message,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    if exc.logic_hash:
        body["logic_hash"] = exc.logic_hash
    return body


async def domain_error_handler(_request: Request, exc: ChrEtrsDomainError) -> JSONResponse:
    return JSONResponse(status_code=exc.http_status, content=_error_body(exc))


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ChrEtrsDomainError, domain_error_handler)
