#!/usr/bin/env python3
"""CHR-ETRS v1.7.0 · tools/preflight.py — go-live readiness check (J-191, Karin 16.11; J-243).

Run before a production deploy. It FAILS (exit 1) while a value that must exist in production is still missing from
the reviewed config or the production database. The repository config stays EMPTY on purpose, so this check fails
on it by design; the normal test run (run_tests.sh) does not depend on it. Usage:
    PGHOST=… PGPORT=… PGUSER=… python3 tools/preflight.py --db NAME [--config-dir PATH]
Checks:
  * method_team.json has at least one recipient address (research method comments, J-191 / J-243);
  * platform_operator.json has at least one CHR-ETRS operator address (J-251);
  * every active company has at least one active vp_hr with an e-mail (J-252; needs --db — without it the check
    FAILS as "not run").
"""
import argparse
import json
import pathlib
import subprocess
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


def check_recipients(config_dir: pathlib.Path, name: str, label: str):
    """A {"recipients": [...]} file must list at least one non-empty address. Returns an error text or None."""
    data, err = read_json(config_dir / name)
    if err:
        return err
    recipients = data.get("recipients") if isinstance(data, dict) else None
    if not isinstance(recipients, list) or not recipients:
        return f"{name}: no recipients ({label} — required before go-live)"
    if not all(isinstance(r, str) and r.strip() for r in recipients):
        return f"{name}: every recipient must be a non-empty address"
    return None


def check_method_team(config_dir: pathlib.Path):
    """J-191 / J-243: method_team.json must list at least one recipient. Returns an error text or None."""
    return check_recipients(config_dir, "method_team.json", "J-191")


def check_platform_operator(config_dir: pathlib.Path):
    """J-251: platform_operator.json must list at least one CHR-ETRS operator address. Returns an error text or None."""
    return check_recipients(config_dir, "platform_operator.json", "J-251")


def check_companies_vp_hr(db):
    """J-252: every active company has an active vp_hr with an e-mail (system function in the DB). Error text or None."""
    if not db:
        return "companies without an active vp_hr: not run (give --db, J-252)"
    res = subprocess.run(["psql", "-X", "-d", db, "-v", "ON_ERROR_STOP=1", "-qAt", "-c",
                          "SELECT * FROM fn_j_companies_without_vp_hr()"], capture_output=True, text=True)
    if res.returncode != 0:
        return f"companies without an active vp_hr: database check failed ({res.stderr.strip()})"
    names = [n for n in res.stdout.splitlines() if n]
    if names:
        return f"{len(names)} active compan{'y' if len(names) == 1 else 'ies'} without an active vp_hr with an e-mail (J-252): " + ", ".join(names)
    return None


def main() -> int:
    """Run every check; print PASS / FAIL lines and the manual go-live items; exit 1 on any failure."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--config-dir", default=str(DEFAULT_CONFIG_DIR))
    ap.add_argument("--db", default=None, help="production database name (for the J-252 company check)")
    args = ap.parse_args()
    cfg = pathlib.Path(args.config_dir)
    errors = [e for e in (check_method_team(cfg), check_platform_operator(cfg), check_companies_vp_hr(args.db)) if e]
    for e in errors:
        print(f"PREFLIGHT FAIL {e}")
    for item in MANUAL_ITEMS:
        print(f"PREFLIGHT MANUAL {item}")
    print("PREFLIGHT " + ("FAILED" if errors else "OK"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
