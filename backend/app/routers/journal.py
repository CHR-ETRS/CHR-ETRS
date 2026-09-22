"""Trail journal — employee private vault.

Not in the locked OpenAPI. Added so Happy Path screen 5 can create and list
JournalEntry rows without exposing them on the manager surface.
The veto reason blob is never returned; sealed rows stay opaque.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.routers.deps import require_bearer
from app.schemas.api import JournalCreateRequest, JournalEntryView, JournalListResponse
from app.services.exceptions import InvalidTelemetryFormat
from app.services.store import JournalEntry, new_id, store

router = APIRouter(
    prefix="/journal",
    tags=["journal"],
    dependencies=[Depends(require_bearer)],
)


def _to_view(row: JournalEntry) -> JournalEntryView:
    if row.sealed:
        return JournalEntryView(
            entry_id=row.entry_id,
            user_id=row.user_id,
            hallway_mirror_response=row.hallway_mirror_response,
            relational_offloading_text=None,
            created_at=row.created_at,
            sealed=True,
        )
    return JournalEntryView(
        entry_id=row.entry_id,
        user_id=row.user_id,
        hallway_mirror_response=row.hallway_mirror_response,
        relational_offloading_text=row.relational_offloading_text,
        created_at=row.created_at,
        sealed=False,
    )


@router.get("/entries", response_model=JournalListResponse)
def list_entries(user_id: str = Query(...)) -> JournalListResponse:
    store.ensure_defaults(user_id)
    rows = store.journal.get(user_id, [])
    return JournalListResponse(
        user_id=user_id,
        private_vault=True,
        entries=[_to_view(row) for row in rows],
    )


@router.post("/entries", response_model=JournalEntryView, status_code=201)
def create_entry(body: JournalCreateRequest) -> JournalEntryView:
    text = body.hallway_mirror_response.strip()
    if not text:
        raise InvalidTelemetryFormat(
            "Biometric parameters out of valid range (e.g. negative HRV or Spoons > 12)."
        )
    store.ensure_defaults(body.user_id)
    row = JournalEntry(
        entry_id=new_id("journal"),
        user_id=body.user_id,
        hallway_mirror_response=text,
        relational_offloading_text=(body.relational_offloading_text or "").strip() or None,
        encrypted_blob=None,
        sealed=False,
    )
    store.journal.setdefault(body.user_id, []).append(row)
    return _to_view(row)
