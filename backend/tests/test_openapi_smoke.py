"""Smoke tests for the locked /api/v1 surface and Happy Path extensions."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.clock import now_utc, set_fixed
from app.services.store import ORG_RD, USER_HOPE, USER_LOW, store
from app.services.validators import enforce_br07_right_to_disconnect

client = TestClient(app)
AUTH = {"Authorization": "Bearer demo-token"}
JERUSALEM = ZoneInfo("Asia/Jerusalem")


@pytest.fixture(autouse=True)
def _isolate_store():
    store.reset()
    set_fixed(datetime(2026, 9, 22, 10, 0, tzinfo=JERUSALEM))
    yield
    set_fixed(None)


def test_health_open():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_missing_bearer_is_401():
    res = client.get(f"/api/v1/telemetry/spoons-budget/{USER_HOPE}")
    assert res.status_code == 401
    body = res.json()
    assert body["error_code"] == "Invalid_OAuth_Token"
    assert body["http_status"] == 401
    assert "message" in body and "timestamp" in body


def test_spoons_and_hrv_roundtrip():
    res = client.get(f"/api/v1/telemetry/spoons-budget/{USER_HOPE}", headers=AUTH)
    assert res.status_code == 200
    body = res.json()
    assert body["current_spoon_count"] == 8
    assert body["daily_baseline_capacity"] == 12

    sample = client.post(
        "/api/v1/telemetry/hrv-sample",
        headers=AUTH,
        json={
            "user_id": USER_HOPE,
            "sample_timestamp": datetime.now(timezone.utc).isoformat(),
            "hrv_baseline_ms": 61.5,
            "vagal_tone_index": 0.7,
        },
    )
    assert sample.status_code == 201
    assert sample.json()["biometric_alert_triggered"] is False

    bad = client.post(
        "/api/v1/telemetry/hrv-sample",
        headers=AUTH,
        json={
            "user_id": USER_HOPE,
            "sample_timestamp": datetime.now(timezone.utc).isoformat(),
            "hrv_baseline_ms": -1,
        },
    )
    assert bad.status_code == 400
    assert bad.json()["error_code"] == "Invalid_Telemetry_Format"

    stream = client.get(
        "/api/v1/telemetry/hrv-stream",
        headers=AUTH,
        params={"device_id": "luna-hope", "sampling_rate_hz": 1},
    )
    assert stream.status_code == 200
    assert stream.json()["hrv_baseline"] == 61.5


def test_task_assign_happy_403_and_409():
    ok = client.post(
        "/api/v1/tasks/assign",
        headers=AUTH,
        json={
            "assignee_id": USER_HOPE,
            "task_name": "טיוטת מסמך קצרה",
            "complexity_spoon_cost": 1,
            "is_chunkable": True,
            "attempt_graded_load_increase": False,
        },
    )
    assert ok.status_code == 200
    assert ok.json()["is_blocked_by_circuit_breaker"] is False

    denied = client.post(
        "/api/v1/tasks/assign",
        headers=AUTH,
        json={
            "assignee_id": USER_LOW,
            "task_name": "עוד סבב",
            "complexity_spoon_cost": 2,
        },
    )
    assert denied.status_code == 403
    body = denied.json()
    assert body["http_status"] == 403
    assert "Circuit breaker" in body["message"]
    assert "error_code" in body and "timestamp" in body

    anti = client.post(
        "/api/v1/tasks/assign",
        headers=AUTH,
        json={
            "assignee_id": USER_LOW,
            "task_name": "הגדלת עומס",
            "complexity_spoon_cost": 2,
            "attempt_graded_load_increase": True,
        },
    )
    assert anti.status_code == 409
    assert anti.json()["error_code"] == "Anti_GET_Exception"


def test_japanese_veil_and_ledger():
    tiny = client.get(
        "/api/v1/manager/dashboard",
        headers=AUTH,
        params={"org_id": ORG_RD, "department_id": "tiny"},
    )
    assert tiny.status_code == 403
    assert tiny.json()["error_code"] == "Japanese_Veil_Violation"

    dash = client.get(
        "/api/v1/manager/dashboard",
        headers=AUTH,
        params={"org_id": ORG_RD, "department_id": "rd-core"},
    )
    assert dash.status_code == 200
    payload = dash.json()
    assert payload["member_count"] >= 5
    assert payload["dichotomous_alert_level"] in {"GREEN", "RED"}
    assert payload["japanese_veil_applied"] is True

    ledger = client.post(
        "/api/v1/manager/ledger/record",
        headers=AUTH,
        json={
            "manager_id": "mgr-glass",
            "action_type": "Note",
            "cost_impact": 12.5,
            "event_description": "Shadow note",
            "system_justification": "MVP WORM",
        },
    )
    assert ledger.status_code == 201
    recorded = ledger.json()
    assert recorded["worm_storage_status"] == "COMMITTED_IMMUTABLE"
    assert len(recorded["logic_hash_sha256"]) == 64


def test_cuckoo_veto_window():
    ping = client.post(
        "/api/v1/cringe/trigger-cuckoo-ping",
        headers=AUTH,
        json={
            "target_user_id": USER_HOPE,
            "manager_id": "mgr-glass",
            "trigger_reason": "HRV_Safety_Cut",
            "veto_window_minutes": 60,
        },
    )
    assert ping.status_code == 200
    alert_id = ping.json()["alert_id"]
    assert ping.json()["status"] == "VETO_WINDOW_ACTIVE"

    veto = client.post(
        "/api/v1/cuckoo/veto",
        headers=AUTH,
        json={"alert_id": alert_id, "encrypted_reason_note": "sealed-reason"},
    )
    assert veto.status_code == 200
    assert veto.json()["status"] == "VETOED_BY_EMPLOYEE"
    assert veto.json()["manager_ledger_credited"] is True

    from app.services.store import store

    store.alerts[alert_id].is_vetoed_by_employee = False
    store.alerts[alert_id].sovereign_veto_window_expiry = now_utc() - timedelta(minutes=5)
    expired = client.post(
        "/api/v1/cuckoo/veto",
        headers=AUTH,
        json={"alert_id": alert_id, "encrypted_reason_note": "too-late"},
    )
    assert expired.status_code == 422
    assert expired.json()["error_code"] == "Sovereign_Veto_Expired"


def test_sentiment_hris_audit_and_extensions():
    sentiment = client.post(
        "/api/v1/cringe/analyze-sentiment",
        headers=AUTH,
        json={
            "text_content": "הכל בסדר, רק חייב עכשיו",
            "source_channel": "Slack",
            "user_id": USER_HOPE,
            "metadata": {"is_after_hours": False},
        },
    )
    assert sentiment.status_code == 200
    patterns = sentiment.json()["detected_patterns"]
    assert "Toxic_Positivity" in patterns
    assert "Masking" in patterns

    sync = client.post(
        "/api/v1/hris/worker-wellness-sync",
        headers=AUTH,
        json={
            "worker_id": USER_HOPE,
            "org_tenant_id": ORG_RD,
            "sync_timestamp": datetime.now(timezone.utc).isoformat(),
            "chr_metrics": {
                "spoons_remaining": 8,
                "spoons_baseline": 12,
                "capacity_percentage": 66.6,
            },
            "system_enforcement": {
                "dichotomous_alert_level": "GREEN",
                "circuit_breaker_active": False,
                "halt_task_allocation": False,
                "overtime_approval_blocked": False,
                "manager_visibility": "DICHOTOMOUS_ONLY",
            },
        },
    )
    assert sync.status_code == 200
    assert sync.json()["sync_status"] == "SUCCESS"

    audit = client.get("/api/v1/audit/privacy-compliance", headers=AUTH)
    assert audit.status_code == 200
    assert audit.json()["regulatory_exposure"]["emotion_recognition_blocked"] is True

    anchors = client.get(f"/api/v1/anchors/{USER_HOPE}", headers=AUTH)
    assert anchors.status_code == 200
    assert anchors.json()["employee_value_asset"]["asset_value_capex"] == 105000.0

    saved = client.put(
        f"/api/v1/anchors/{USER_HOPE}",
        headers=AUTH,
        json={
            "anchors": [
                {
                    "type_lighting": "Task",
                    "territory_schema": "שולחן ליד החלון",
                    "exposure_gate": "Open",
                }
            ]
        },
    )
    assert saved.status_code == 200
    assert saved.json()["anchors"][0]["type_lighting"] == "Task"

    matrix = client.get(f"/api/v1/resilience/matrix/{USER_HOPE}", headers=AUTH)
    assert matrix.status_code == 200
    assert matrix.json()["role_state"] in {"HOPE", "SHAY", "NESS"}

    low = client.get(f"/api/v1/resilience/matrix/{USER_LOW}", headers=AUTH)
    assert low.status_code == 200
    assert low.json()["role_state"] == "NESS"
    assert low.json()["contrast_nullification_active"] is True

    created = client.post(
        "/api/v1/journal/entries",
        headers=AUTH,
        json={
            "user_id": USER_HOPE,
            "hallway_mirror_response": "רשמתי גבול להיום.",
            "relational_offloading_text": "אפשר להניח את זה.",
        },
    )
    assert created.status_code == 201
    listed = client.get(
        "/api/v1/journal/entries",
        headers=AUTH,
        params={"user_id": USER_HOPE},
    )
    assert listed.status_code == 200
    assert listed.json()["private_vault"] is True
    assert any(row["hallway_mirror_response"] == "רשמתי גבול להיום." for row in listed.json()["entries"])


def test_right_to_disconnect_evening():
    from app.services.exceptions import RightToDisconnectViolation

    evening = datetime(2026, 9, 22, 20, 15, tzinfo=JERUSALEM)
    with pytest.raises(RightToDisconnectViolation):
        enforce_br07_right_to_disconnect(when=evening)
    enforce_br07_right_to_disconnect(when=datetime(2026, 9, 22, 10, 0, tzinfo=JERUSALEM))

    set_fixed(evening)
    blocked = client.post(
        "/api/v1/tasks/assign",
        headers=AUTH,
        json={
            "assignee_id": USER_HOPE,
            "task_name": "הודעה לילית",
            "complexity_spoon_cost": 1,
        },
    )
    assert blocked.status_code == 403
    assert blocked.json()["error_code"] == "Right_To_Disconnect_Violation"
    assert store.ledger, "BR-07 breach should append a deprivation-tax ledger row"


def test_legacy_energy_routes_gone():
    res = client.get("/api/v1/energy/state", headers=AUTH)
    assert res.status_code == 404
    res = client.post("/api/v1/biometrics/log", headers=AUTH, json={})
    assert res.status_code == 404
    res = client.post("/api/v1/communication/sentiment", headers=AUTH, json={})
    assert res.status_code == 404
