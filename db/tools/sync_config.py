#!/usr/bin/env python3
"""CHR-ETRS v1.7.0 · tools/sync_config.py — load the reviewed db/config/*.json files into the database.

Runs as the service role / owner (the sync functions are system-only). Each file is passed whole to its function;
nothing is deleted. Usage:
    PGHOST=/tmp PGPORT=54317 PGUSER=postgres python3 tools/sync_config.py --db chr [--dry-run]
"""
import argparse
import json
import pathlib
import subprocess
import sys

CONFIG_DIR = pathlib.Path(__file__).resolve().parent.parent / "config"
# file name → system function (order matters: researchers before anything that could reference them)
FILES = [
    ("research_dpa.json", "fn_sync_research_config"),
    ("everstore_supplier_offers.json", "fn_sync_supplier_offers"),
    ("method_team.json", "fn_sync_method_team"),
    ("company_service_end.json", "fn_sync_company_service_end"),
]


def load(name: str) -> dict:
    """Read and validate one config file (must be a JSON object)."""
    data = json.loads((CONFIG_DIR / name).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{name}: top level must be an object")
    return data


def statement(func: str, data: dict) -> str:
    """One SQL statement that hands the whole file to its function (dollar-quoted, no interpolation of values)."""
    body = json.dumps(data, ensure_ascii=False)
    if "$cfg$" in body:
        raise ValueError("config may not contain the quote tag $cfg$")
    return f"SELECT '{func}' AS fn, {func}($cfg${body}$cfg$::jsonb) AS rows;"


def main() -> int:
    """Build the statements and run them in one transaction with psql (or print them with --dry-run)."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    sql = "BEGIN;\n" + "\n".join(statement(f, load(n)) for n, f in FILES) + "\nCOMMIT;\n"
    if args.dry_run:
        sys.stdout.write(sql)
        return 0
    res = subprocess.run(["psql", "-d", args.db, "-v", "ON_ERROR_STOP=1", "-qAt"], input=sql, text=True)
    return res.returncode


if __name__ == "__main__":
    sys.exit(main())
