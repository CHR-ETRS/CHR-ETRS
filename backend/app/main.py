"""CHR-ETRS API — routers mounted at /api/v1 to match openapi.yaml servers + paths."""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import (
    anchors,
    audit,
    cringe,
    cuckoo,
    hris,
    journal,
    manager,
    resilience,
    tasks,
    telemetry,
)
from app.routers.deps import register_exception_handlers

app = FastAPI(
    title="CHR-ETRS API",
    version="1.1.0",
    description=(
        "Locked MVP API. Canonical contract: /openapi.yaml. "
        "Employee extensions (anchors, resilience matrix, journal) are documented in the README."
    ),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

register_exception_handlers(app)

API = "/api/v1"
app.include_router(telemetry.router, prefix=API)
app.include_router(cringe.router, prefix=API)
app.include_router(cuckoo.router, prefix=API)
app.include_router(tasks.router, prefix=API)
app.include_router(manager.router, prefix=API)
app.include_router(hris.router, prefix=API)
app.include_router(audit.router, prefix=API)
app.include_router(anchors.router, prefix=API)
app.include_router(resilience.router, prefix=API)
app.include_router(journal.router, prefix=API)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "chr-etrs"}
