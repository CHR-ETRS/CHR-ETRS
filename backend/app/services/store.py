"""In-memory persistence mirroring the 10 canonical entities.

No database is required for the MVP. Records follow schema.sql column meaning:
Employee_Value_Asset, Anchor, SpoonBudget, HRVSample, Task, JournalEntry,
TeamAggregate, CuckooAlert, Avatar_State, Manager_Ledger.
"""
from __future__ import annotations

import hashlib
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from decimal import Decimal
from typing import Optional

from app.services.validators import (
    DEPRIVATION_TAX_RATE,
    HRV_HARD_CUT_MS,
    calculate_br04_deprivation_tax,
)

ORG_RD = "11111111-1111-4111-8111-111111111111"
USER_HOPE = "emp-hope"
USER_LOW = "emp-low"
MANAGER_ID = "mgr-glass"


def utcnow() -> datetime:
    from app.services.clock import now_utc

    return now_utc()


def new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:12]}"


def sha256_hex(payload: str) -> str:
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


@dataclass
class EmployeeValueAsset:
    employee_id: str
    direct_cost_opex: float = 25000.0
    asset_value_capex: float = 105000.0
    productivity_alpha_factor: float = 1.0
    happiness_debt_liability: float = 0.0
    updated_at: datetime = field(default_factory=utcnow)


@dataclass
class Anchor:
    anchor_id: str
    user_id: str
    type_lighting: str
    territory_schema: Optional[str]
    exposure_gate: str
    created_at: datetime = field(default_factory=utcnow)


@dataclass
class SpoonBudget:
    budget_id: str
    user_id: str
    current_spoon_count: int
    daily_baseline_capacity: int = 12
    sinks_expenditure: int = 0
    sources_recovery: int = 0
    golden_spoons_held: int = 0
    updated_at: datetime = field(default_factory=utcnow)

    @property
    def available_capacity_pct(self) -> float:
        if self.daily_baseline_capacity <= 0:
            return 0.0
        return round(self.current_spoon_count / self.daily_baseline_capacity * 100.0, 2)

    @property
    def energy_state_indicator(self) -> str:
        if self.current_spoon_count < 3 or self.available_capacity_pct < 14:
            return "Critical"
        if self.current_spoon_count < 6:
            return "Strained"
        return "Optimal"

    @property
    def smart_pacing_status(self) -> str:
        if self.current_spoon_count < 3 or self.available_capacity_pct < 14:
            return "POST_TASK_CREATION_BLOCKED"
        return "Normal"


@dataclass
class HRVSample:
    sample_id: str
    user_id: str
    hrv_baseline: float
    distal_skin_temp: Optional[float]
    vagal_tone_index: Optional[float]
    cold_stim_recovery: Optional[int]
    sample_timestamp: datetime


@dataclass
class Task:
    task_id: str
    assignee_id: str
    task_name: str
    complexity_spoon_cost: int
    is_chunkable: bool
    pacing_status: str
    is_blocked_by_circuit_breaker: bool
    created_at: datetime = field(default_factory=utcnow)


@dataclass
class JournalEntry:
    entry_id: str
    user_id: str
    hallway_mirror_response: str
    relational_offloading_text: Optional[str]
    encrypted_blob: Optional[str] = None
    created_at: datetime = field(default_factory=utcnow)
    sealed: bool = False


@dataclass
class TeamAggregate:
    aggregate_id: str
    org_id: str
    department: str
    team_spoon_avg: float
    deprivation_tax_sum: float
    member_count: int
    dichotomous_alert_level: str
    calculated_at: datetime = field(default_factory=utcnow)


@dataclass
class CuckooAlert:
    alert_id: str
    manager_id: str
    target_user_id: str
    trigger_reason: str
    sovereign_veto_window_expiry: datetime
    is_vetoed_by_employee: bool = False
    logic_hash: str = ""
    created_at: datetime = field(default_factory=utcnow)


@dataclass
class AvatarState:
    avatar_id: str
    user_id: str
    base_role: str
    bone_memory_latency: int = 0
    contrast_nullification_active: bool = False
    updated_at: datetime = field(default_factory=utcnow)


@dataclass
class ManagerLedger:
    ledger_id: str
    manager_id: str
    logic_hash: str
    event_description: str
    deprivation_tax_cost: float
    system_justification: str
    restoration_status: str = "Pending_Restoration"
    action_type: str = ""
    created_at: datetime = field(default_factory=utcnow)


class MemoryStore:
    def __init__(self) -> None:
        self.assets: dict[str, EmployeeValueAsset] = {}
        self.anchors: dict[str, list[Anchor]] = {}
        self.spoons: dict[str, SpoonBudget] = {}
        self.hrv: dict[str, list[HRVSample]] = {}
        self.tasks: list[Task] = []
        self.journal: dict[str, list[JournalEntry]] = {}
        self.teams: dict[tuple[str, str], TeamAggregate] = {}
        self.alerts: dict[str, CuckooAlert] = {}
        self.avatars: dict[str, AvatarState] = {}
        self.ledger: list[ManagerLedger] = []
        self.ledger_hashes: set[str] = set()
        self._seed()

    def _seed(self) -> None:
        self._ensure_user(
            USER_HOPE,
            spoons=8,
            hrv=62.0,
            base_role="HOPE",
            territory="חדר שקט בקומה 3 · אור Authority",
            happiness_debt=0.0,
        )
        self._ensure_user(
            USER_LOW,
            spoons=2,
            hrv=28.0,
            base_role="NESS",
            territory="עמדה פתוחה · שער Closed",
            happiness_debt=12000.0,
            lighting="Soft",
            gate="Closed",
        )
        self.journal[USER_HOPE] = [
            JournalEntry(
                entry_id="journal-seed-hope",
                user_id=USER_HOPE,
                hallway_mirror_response="הבוקר שמרתי על גבול בין פגישה עמוקה לבין רעש מסדרון.",
                relational_offloading_text="לא צריך לפתור את זה עכשיו — רק לרשום.",
            )
        ]
        tax = float(calculate_br04_deprivation_tax(Decimal("25000"), 2))
        self.teams[(ORG_RD, "rd-core")] = TeamAggregate(
            aggregate_id="agg-rd-core",
            org_id=ORG_RD,
            department="rd-core",
            team_spoon_avg=7.4,
            deprivation_tax_sum=tax,
            member_count=8,
            dichotomous_alert_level="GREEN",
        )
        self.teams[(ORG_RD, "tiny")] = TeamAggregate(
            aggregate_id="agg-tiny",
            org_id=ORG_RD,
            department="tiny",
            team_spoon_avg=5.0,
            deprivation_tax_sum=0.0,
            member_count=3,
            dichotomous_alert_level="RED",
        )

    def _ensure_user(
        self,
        user_id: str,
        *,
        spoons: int,
        hrv: Optional[float],
        base_role: str,
        territory: str,
        happiness_debt: float,
        lighting: str = "Authority",
        gate: str = "Filtered",
    ) -> None:
        self.assets[user_id] = EmployeeValueAsset(
            employee_id=user_id,
            happiness_debt_liability=happiness_debt,
            productivity_alpha_factor=1.05 if spoons >= 6 else 0.72,
        )
        self.anchors[user_id] = [
            Anchor(
                anchor_id=new_id("anchor"),
                user_id=user_id,
                type_lighting=lighting,
                territory_schema=territory,
                exposure_gate=gate,
            )
        ]
        self.spoons[user_id] = SpoonBudget(
            budget_id=new_id("budget"),
            user_id=user_id,
            current_spoon_count=spoons,
            sinks_expenditure=max(0, 12 - spoons),
            sources_recovery=1 if spoons >= 6 else 0,
            golden_spoons_held=2 if spoons < 3 else 0,
        )
        self.hrv[user_id] = []
        if hrv is not None:
            self.hrv[user_id].append(
                HRVSample(
                    sample_id=new_id("smp"),
                    user_id=user_id,
                    hrv_baseline=hrv,
                    distal_skin_temp=33.4,
                    vagal_tone_index=round(hrv / 80.0, 3),
                    cold_stim_recovery=40,
                    sample_timestamp=utcnow(),
                )
            )
        self.avatars[user_id] = AvatarState(
            avatar_id=new_id("avatar"),
            user_id=user_id,
            base_role=base_role,
        )
        self.journal.setdefault(user_id, [])

    def ensure_defaults(self, user_id: str) -> None:
        if user_id not in self.spoons:
            self._ensure_user(
                user_id,
                spoons=8,
                hrv=None,
                base_role="HOPE",
                territory="",
                happiness_debt=0.0,
            )
            self.anchors[user_id] = []

    def latest_hrv(self, user_id: str) -> Optional[HRVSample]:
        rows = self.hrv.get(user_id) or []
        return rows[-1] if rows else None

    def latest_hrv_ms(self, user_id: str) -> Optional[float]:
        sample = self.latest_hrv(user_id)
        return sample.hrv_baseline if sample else None

    def add_hrv(self, sample: HRVSample) -> None:
        self.ensure_defaults(sample.user_id)
        self.hrv.setdefault(sample.user_id, []).append(sample)
        if sample.hrv_baseline < HRV_HARD_CUT_MS:
            budget = self.spoons[sample.user_id]
            budget.golden_spoons_held = min(12, budget.golden_spoons_held + 1)
            budget.updated_at = utcnow()

    def spend_spoons(self, user_id: str, cost: int) -> None:
        budget = self.spoons[user_id]
        budget.current_spoon_count = max(0, budget.current_spoon_count - cost)
        budget.sinks_expenditure += cost
        budget.updated_at = utcnow()

    def inject_golden_spoons(self, user_id: str, count: int) -> int:
        self.ensure_defaults(user_id)
        budget = self.spoons[user_id]
        injected = max(0, count)
        budget.golden_spoons_held = min(12, budget.golden_spoons_held + injected)
        budget.updated_at = utcnow()
        return injected

    def derived_role(self, user_id: str) -> str:
        """Resilience view fed by spoons + HRV (HOPE / SHAY / NESS)."""
        budget = self.spoons[user_id]
        hrv = self.latest_hrv_ms(user_id)
        if budget.current_spoon_count < 3 or (hrv is not None and hrv < HRV_HARD_CUT_MS):
            return "NESS"
        if budget.current_spoon_count < 6 or (hrv is not None and hrv < 55):
            return "SHAY"
        return "HOPE"

    def resilience_axes(self, user_id: str) -> dict[str, float]:
        budget = self.spoons[user_id]
        hrv = self.latest_hrv_ms(user_id) or 40.0
        hope = round(max(0.0, min(100.0, budget.current_spoon_count / 12 * 100)), 1)
        resilience = round(max(0.0, min(100.0, hrv / 80 * 100)), 1)
        efficacy = round((hope + resilience) / 2, 1)
        optimism = round(min(100.0, efficacy + (8 if hope >= 50 else 0)), 1)
        return {
            "hope": hope,
            "efficacy": efficacy,
            "resilience": resilience,
            "optimism": optimism,
        }

    def commit_ledger(
        self,
        *,
        manager_id: str,
        action_type: str,
        cost_impact: float,
        event_description: str,
        system_justification: str,
        restoration_status: str = "Pending_Restoration",
    ) -> ManagerLedger:
        created = utcnow()
        payload = "|".join(
            [
                manager_id,
                action_type,
                f"{cost_impact:.2f}",
                event_description,
                system_justification,
                created.isoformat(),
                uuid.uuid4().hex,
            ]
        )
        digest = sha256_hex(payload)
        if digest in self.ledger_hashes:
            from app.services.exceptions import WormLedgerWriteFailure

            raise WormLedgerWriteFailure(
                "Failed to write SHA-256 Logic Hash to WORM Manager Ledger."
            )
        row = ManagerLedger(
            ledger_id=new_id("ledger"),
            manager_id=manager_id,
            logic_hash=digest,
            event_description=event_description,
            deprivation_tax_cost=round(cost_impact, 2),
            system_justification=system_justification,
            restoration_status=restoration_status,
            action_type=action_type,
            created_at=created,
        )
        self.ledger.append(row)
        self.ledger_hashes.add(digest)
        return row

    def reset(self) -> None:
        self.assets.clear()
        self.anchors.clear()
        self.spoons.clear()
        self.hrv.clear()
        self.tasks.clear()
        self.journal.clear()
        self.teams.clear()
        self.alerts.clear()
        self.avatars.clear()
        self.ledger.clear()
        self.ledger_hashes.clear()
        self._seed()

    def record_disconnect_debt(self, manager_id: str, assignee_id: str) -> None:
        """BR-07 breach records emotional debt + deprivation tax on the ledger."""
        asset = self.assets.get(assignee_id)
        salary = asset.direct_cost_opex if asset else 25000.0
        tax = float(
            (Decimal(str(salary)) * DEPRIVATION_TAX_RATE).quantize(Decimal("0.01"))
        )
        if asset:
            asset.happiness_debt_liability = round(asset.happiness_debt_liability + tax, 2)
        self.commit_ledger(
            manager_id=manager_id or MANAGER_ID,
            action_type="Right_To_Disconnect",
            cost_impact=tax,
            event_description=(
                "After-hours forced task blocked. Emotional debt recorded. "
                "Employee identity withheld from the narrative field."
            ),
            system_justification=(
                "BR-07 Right to Disconnect (19:00–07:00 Asia/Jerusalem) "
                "plus BR-04 deprivation tax on the breach."
            ),
            restoration_status="Emotional_Debt_Open",
        )


store = MemoryStore()
