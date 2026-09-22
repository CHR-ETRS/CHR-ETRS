-- Generated 2026-09-22 from Gold SoT Doc 1_frkn_u7r_LQWR1pW-bo0mcwVTJwYww5Hh6J8xSCc34
-- (CHR-ETRS — Source of Truth זהב מאוחד 1–6) + Excel 06 Data Tables.
-- 10 MVP entities locked: Employee_Value_Asset, Anchor, SpoonBudget, HRVSample, Task,
-- JournalEntry, TeamAggregate, CuckooAlert, Avatar_State, Manager_Ledger.
-- Supporting FK scaffolding: Companies, Users. Out of scope: Web3 / VR / supply-chain AI.
-- CHR-ETRS Supabase/PostgreSQL migration
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- lighting_type physical DDL: Authority/Soft/Task.
-- Excel 06 synonym: Type_Lighting Chandelier ↔ Authority, Crown ↔ Soft (document only; enum values unchanged).
CREATE TYPE lighting_type AS ENUM ('Authority', 'Soft', 'Task');
CREATE TYPE exposure_gate_type AS ENUM ('Closed', 'Filtered', 'Open');
CREATE TYPE avatar_role_state AS ENUM ('HOPE', 'NESS', 'SHAY');
CREATE TYPE dichotomous_alert_level AS ENUM ('GREEN', 'RED');
CREATE TYPE trigger_reason_enum AS ENUM (
    'Spoon_Bankruptcy',
    'Contract_Fragility',
    'Accelerated_Depreciation',
    'Toxic_Positivity_AfterHours',
    'HRV_Safety_Cut'
);

CREATE TABLE "Companies" (
    company_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name VARCHAR(255) NOT NULL UNIQUE,
    industry VARCHAR(255),
    company_size VARCHAR(50),
    location VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "Users" (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES "Companies"(company_id) ON DELETE SET NULL,
    manager_id UUID REFERENCES "Users"(user_id) ON DELETE SET NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    full_name VARCHAR(255) NOT NULL,
    department VARCHAR(255) NOT NULL,
    "role" VARCHAR(255) NOT NULL,
    start_date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "Employee_Value_Asset" (
    "EmployeeID" UUID PRIMARY KEY REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Direct_Cost_OPEX" DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    "Asset_Value_CAPEX" DECIMAL(18,2) NOT NULL DEFAULT 105000.00,
    "Productivity_Alpha_Factor" DOUBLE PRECISION NOT NULL DEFAULT 1.00,
    "Happiness_Debt_Liability" DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "Anchors" (
    "AnchorID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Type_Lighting" lighting_type NOT NULL DEFAULT 'Authority',
    "Territory_Schema" TEXT,
    "Exposure_Gate" exposure_gate_type NOT NULL DEFAULT 'Filtered',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "SpoonBudget" (
    "BudgetID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Current_Spoon_Count" INT NOT NULL CHECK ("Current_Spoon_Count" BETWEEN 0 AND 12),
    "Daily_Baseline_Capacity" INT NOT NULL DEFAULT 12 CHECK ("Daily_Baseline_Capacity" > 0),
    "Available_Capacity_Pct" DECIMAL(5,2) GENERATED ALWAYS AS (
        ("Current_Spoon_Count"::DECIMAL / NULLIF("Daily_Baseline_Capacity", 0)) * 100.0
    ) STORED,
    "Energy_State_Indicator" VARCHAR(50) NOT NULL DEFAULT 'Optimal',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "HRVSample" (
    "SampleID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "HRV_Baseline" DOUBLE PRECISION NOT NULL,
    "Distal_Skin_Temp" DOUBLE PRECISION,
    "Vagal_Tone_Index" DOUBLE PRECISION,
    "Cold_Stim_Recovery" INT,
    sample_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "Tasks" (
    "TaskID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "AssigneeID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Task_Name" VARCHAR(255) NOT NULL,
    "Complexity_Spoon_Cost" INT NOT NULL CHECK ("Complexity_Spoon_Cost" > 0),
    "Is_Chunkable" BOOLEAN NOT NULL DEFAULT TRUE,
    "Pacing_Status" VARCHAR(50) DEFAULT 'Normal',
    "Is_Blocked_By_Circuit_Breaker" BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "JournalEntry" (
    "EntryID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Hallway_Mirror_Response" TEXT NOT NULL,
    "Relational_Offloading_Text" TEXT,
    "Encrypted_Blob" BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "TeamAggregate" (
    "AggregateID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "OrgID" UUID NOT NULL REFERENCES "Companies"(company_id) ON DELETE CASCADE,
    "Department" VARCHAR(255) NOT NULL,
    "Team_Spoon_Avg" DOUBLE PRECISION NOT NULL,
    "Deprivation_Tax_Sum" DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    "Member_Count" INT NOT NULL CHECK ("Member_Count" >= 5),
    "Dichotomous_Alert_Level" dichotomous_alert_level NOT NULL DEFAULT 'GREEN',
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "CuckooAlerts" (
    "AlertID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "ManagerID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "TargetUserID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Trigger_Reason" trigger_reason_enum NOT NULL,
    "Sovereign_Veto_Window_Expiry" TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '60 minutes'),
    "Is_Vetoed_By_Employee" BOOLEAN NOT NULL DEFAULT FALSE,
    "Logic_Hash" VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "Avatar_State" (
    "AvatarID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Role_State" avatar_role_state NOT NULL DEFAULT 'HOPE',
    "Bone_Memory_Latency" INT DEFAULT 0,
    "Contrast_Nullification_Active" BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "Manager_Ledger" (
    "LedgerID" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "ManagerID" UUID NOT NULL REFERENCES "Users"(user_id) ON DELETE CASCADE,
    "Logic_Hash" VARCHAR(64) UNIQUE NOT NULL,
    "Event_Description" TEXT NOT NULL,
    "Deprivation_Tax_Cost" DECIMAL(18,2) NOT NULL DEFAULT 0.00,
    "System_Justification" TEXT NOT NULL,
    "Restoration_Status" VARCHAR(100) NOT NULL DEFAULT 'Pending_Restoration',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_hrv_user_timestamp
    ON "HRVSample" ("UserID", sample_timestamp DESC);
CREATE INDEX idx_spoon_user
    ON "SpoonBudget" ("UserID");
CREATE INDEX idx_tasks_assignee_blocked
    ON "Tasks" ("AssigneeID", "Is_Blocked_By_Circuit_Breaker");
CREATE INDEX idx_team_agg_dept
    ON "TeamAggregate" ("OrgID", "Department", calculated_at DESC);
CREATE UNIQUE INDEX idx_ledger_hash
    ON "Manager_Ledger" ("Logic_Hash");

ALTER TABLE "HRVSample" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "JournalEntry" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "SpoonBudget" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Anchors" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "TeamAggregate" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "CuckooAlerts" ENABLE ROW LEVEL SECURITY;

CREATE POLICY hrv_private_vault_policy ON "HRVSample"
    FOR ALL
    USING (auth.uid() = "UserID")
    WITH CHECK (auth.uid() = "UserID");

CREATE POLICY journal_private_vault_policy ON "JournalEntry"
    FOR ALL
    USING (auth.uid() = "UserID")
    WITH CHECK (auth.uid() = "UserID");

CREATE POLICY spoon_budget_user_policy ON "SpoonBudget"
    FOR ALL
    USING (auth.uid() = "UserID")
    WITH CHECK (auth.uid() = "UserID");

CREATE POLICY anchors_user_policy ON "Anchors"
    FOR ALL
    USING (auth.uid() = "UserID")
    WITH CHECK (auth.uid() = "UserID");

CREATE POLICY team_aggregate_manager_policy ON "TeamAggregate"
    FOR SELECT
    USING (
        "Member_Count" >= 5
        AND EXISTS (
            SELECT 1
            FROM "Users" AS u
            WHERE u.user_id = auth.uid()
              AND u.company_id = "TeamAggregate"."OrgID"
              AND u."role" IN ('Manager', 'Admin', 'C-Suite')
        )
    );

CREATE POLICY cuckoo_employee_veto_policy ON "CuckooAlerts"
    FOR UPDATE
    USING (auth.uid() = "TargetUserID")
    WITH CHECK (auth.uid() = "TargetUserID");

CREATE POLICY cuckoo_manager_view_policy ON "CuckooAlerts"
    FOR SELECT
    USING (auth.uid() = "ManagerID");

CREATE OR REPLACE FUNCTION fn_check_circuit_breaker()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_spoons INT;
    v_latest_hrv DOUBLE PRECISION;
BEGIN
    SELECT "Current_Spoon_Count"
      INTO v_current_spoons
      FROM "SpoonBudget"
     WHERE "UserID" = NEW."AssigneeID";

    SELECT "HRV_Baseline"
      INTO v_latest_hrv
      FROM "HRVSample"
     WHERE "UserID" = NEW."AssigneeID"
     ORDER BY sample_timestamp DESC
     LIMIT 1;

    IF (v_current_spoons < 3)
       OR (v_latest_hrv IS NOT NULL AND v_latest_hrv < 40.0) THEN
        NEW."Is_Blocked_By_Circuit_Breaker" := TRUE;
        NEW."Pacing_Status" := 'BLOCKED_BY_CIRCUIT_BREAKER';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_circuit_breaker
    BEFORE INSERT OR UPDATE ON "Tasks"
    FOR EACH ROW
    EXECUTE FUNCTION fn_check_circuit_breaker();

CREATE OR REPLACE PROCEDURE Calculate_Human_Alpha(
    IN p_employee_id UUID,
    OUT p_calculated_alpha DOUBLE PRECISION,
    OUT p_deprivation_tax DECIMAL(18,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_alpha_factor DOUBLE PRECISION;
    v_happiness_debt DECIMAL(18,2);
    v_spoons_capacity DECIMAL(5,2);
    v_base_cost DECIMAL(18,2);
BEGIN
    SELECT "Productivity_Alpha_Factor",
           "Happiness_Debt_Liability",
           "Direct_Cost_OPEX"
      INTO v_alpha_factor, v_happiness_debt, v_base_cost
      FROM "Employee_Value_Asset"
     WHERE "EmployeeID" = p_employee_id;

    SELECT "Available_Capacity_Pct"
      INTO v_spoons_capacity
      FROM "SpoonBudget"
     WHERE "UserID" = p_employee_id;

    IF v_spoons_capacity < 14.0 THEN
        p_deprivation_tax := v_base_cost * 0.12;
    ELSE
        p_deprivation_tax := 0.00;
    END IF;

    p_calculated_alpha :=
        (v_alpha_factor * (v_spoons_capacity / 100.0))
        - (v_happiness_debt / 100000.0);
END;
$$;
