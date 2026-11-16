#!/usr/bin/env python3
"""CHR-ETRS v1.7.0 · tools/preflight.py — go-live readiness check (J-191, Karin 16.11; J-243).

Run before a production deploy. It FAILS (exit 1) while a value that must exist in production is still missing from
the reviewed config. The repository config stays EMPTY on purpose, so this check fails on it by design; the normal
test run (run_tests.sh) does not depend on it. Usage:
    python3 tools/preflight.py [--config-dir PATH]
Checks today: method_team.json has at least one recipient address (research method comments, J-191).
"""
import argparse
import json
import pathlib
import sys

DEFAULT_CONFIG_DIR = pathlib.Path(__file__).resolve().parent.parent / "config"
# Required before go-live but kept outside db/config (recorded in ADR_GAPS J-244); printed as a reminder only.
MANUAL_ITEMS = [
    "ערך כפית מוזהבת בשקלים — לא הוגדר",
    "התורם המשפטי לקבלות (רואה חשבון) — לא הוגדר",
]


def read_json(path: pathlib.Path):
    """Read one config file; returns (data, error text or None)."""
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"{path.name}: missing"
    except ValueError as exc:
        return None, f"{path.name}: invalid JSON ({exc})"


def check_method_team(config_dir: pathlib.Path):
    """J-191: method_team.json must list at least one non-empty recipient address. Returns an error text or None."""
    data, err = read_json(config_dir / "method_team.json")
    if err:
        return err
    recipients = data.get("recipients") if isinstance(data, dict) else None
    if not isinstance(recipients, list) or not recipients:
        return "method_team.json: no recipients (J-191 — required before go-live)"
    if not all(isinstance(r, str) and r.strip() for r in recipients):
        return "method_team.json: every recipient must be a non-empty address"
    return None


def main() -> int:
    """Run every check; print PASS / FAIL lines and the manual go-live items; exit 1 on any failure."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--config-dir", default=str(DEFAULT_CONFIG_DIR))
    args = ap.parse_args()
    errors = [e for e in (check_method_team(pathlib.Path(args.config_dir)),) if e]
    for e in errors:
        print(f"PREFLIGHT FAIL {e}")
    for item in MANUAL_ITEMS:
        print(f"PREFLIGHT MANUAL {item}")
    print("PREFLIGHT " + ("FAILED" if errors else "OK"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
