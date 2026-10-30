#!/usr/bin/env python3
# CHR-ETRS MVP v1.6.10 · tools/gen_ref_country_calendar.py
# Version: 1.6.10-mvp (2026-10-21) — supersedes 1.6.9 (UZ keeps the capital's Asia/Tashkent, Samarkand excluded;
#   a pinned country is not multi-zone for review — rule applied in SQL, reported here).
# Generates ref_country_calendar.sql (country → CLDR firstDay / weekendStart / weekendEnd + main IANA zone)
# from the REAL upstream data. The ONLY hand-set values are the explicit, documented OVERRIDES below
# (each row of the output names its source: 'CLDR' / 'zone.tab' / 'override: …').
#   CLDR : npm package cldr-core (unicode-org/cldr-json), supplemental/weekData.json
#   tz   : IANA tz database zone.tab (+ zone1970.tab, compared only), e.g. /usr/share/zoneinfo
# Usage:
#   npm install cldr-core@48.2.0   (in a scratch dir)
#   python3 tools/gen_ref_country_calendar.py --cldr <dir>/node_modules/cldr-core \
#       --tzdir /usr/share/zoneinfo --out ref_country_calendar.sql
# Standard library only. Output is deterministic for the same inputs.
import argparse
import datetime
import zoneinfo
import json
import os
import re
import sys

# Explicit overrides (documented in README / ADR_GAPS):
#   IL firstDay pinned to Sunday (Karin 20.10; CLDR 48 agrees).
#   XK → Europe/Belgrade, AN → America/Curacao (Chief of Drive 20.10, O-43): CLDR lists both,
#   IANA zone.tab has no row for them.
FIRST_DAY_OVERRIDES = {"IL": (0, "override: Karin 20.10 (IL pinned Sunday)")}
TZ_OVERRIDES = {
    "XK": ("Europe/Belgrade", "override: Chief of Drive 20.10 (O-43)"),
    "AN": ("America/Curacao", "override: Chief of Drive 20.10 (O-43)"),
    # v1.6.9 (O-51): zone.tab lists Europe/Simferopol BEFORE Europe/Kyiv; the first-row rule would pick
    # Simferopol. Pinned to Kyiv. Simferopol is NOT excluded (different UTC offset) → UA still counts 2
    # zones, but v1.6.10 (Chief of Drive): the pin is final — a pinned country is never needs_review.
    "UA": ("Europe/Kyiv", "override: Chief of Drive 21.10 (O-51, UA pinned Kyiv)"),
}
# Manual exclusion list (v1.6.8): zones IGNORED when counting a country's zones for multi-zone
# detection (tz_zone_count) and never picked as its main zone. Only rulings go here.
#   Europe/Busingen — German exclave inside Switzerland (Chief of Drive 21.10): DE counts as single-zone.
#   v1.6.9 (Chief of Drive 21.10, O-51): the second zone.tab zone of CY, MH, MY, PS, UZ — each has the
#   same UTC offset as the kept (first-listed) zone; verify_exclusions() re-checks this on every run
#   and refuses to generate otherwise.
ZONE_EXCLUSIONS = {
    "Europe/Busingen": "ruling: Chief of Drive 21.10 (DE exclave)",
    "Asia/Famagusta": "ruling: Chief of Drive 21.10 (O-51, CY; same offset as Asia/Nicosia)",
    "Pacific/Kwajalein": "ruling: Chief of Drive 21.10 (O-51, MH; same offset as Pacific/Majuro)",
    "Asia/Kuching": "ruling: Chief of Drive 21.10 (O-51, MY; same offset as Asia/Kuala_Lumpur)",
    "Asia/Hebron": "ruling: Chief of Drive 21.10 (O-51, PS; same offset as Asia/Gaza)",
    # v1.6.10 (Chief of Drive 21.10): UZ keeps the capital's zone — Samarkand excluded instead of Tashkent.
    "Asia/Samarkand": "ruling: Chief of Drive 21.10 (v1.6.10, UZ; capital Asia/Tashkent kept, same offset)",
}
# Window of the same-offset check: every hour from VERIFY_FROM (UTC) up to VERIFY_TO (UTC, exclusive).
VERIFY_FROM = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
VERIFY_TO = datetime.datetime(2038, 1, 1, tzinfo=datetime.timezone.utc)

DOW = {"sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6}
WORLD = "001"


def load_cldr(cldr_dir):
    """Read weekData + the cldr-core package version; return (version_str, weekData dict)."""
    with open(os.path.join(cldr_dir, "supplemental", "weekData.json"), encoding="utf-8") as f:
        sup = json.load(f)["supplemental"]
    with open(os.path.join(cldr_dir, "package.json"), encoding="utf-8") as f:
        pkg = json.load(f)
    ver = "CLDR %s (cldr-core %s, unicode %s)" % (
        sup["version"]["_cldrVersion"], pkg["version"], sup["version"].get("_unicodeVersion", "?"))
    return ver, sup["weekData"]


def region_map(section):
    """Keep only world (001) and 2-letter region keys; drop '-alt-' variants. Values → 0–6."""
    return {k: DOW[v] for k, v in section.items() if k == WORLD or re.fullmatch(r"[A-Z]{2}", k)}


def tz_version(tzdir):
    """tzdata version from tzdata.zi ('# version 2026c'), or 'unknown'."""
    try:
        with open(os.path.join(tzdir, "tzdata.zi"), encoding="utf-8") as f:
            m = re.match(r"#\s*version\s+(\S+)", f.readline())
            return m.group(1) if m else "unknown"
    except OSError:
        return "unknown"


def read_tab(path):
    """Rows of a zone tab file as (country_codes[list], zone) in file order."""
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            parts = line.rstrip("\n").split("\t")
            rows.append((parts[0].split(","), parts[2]))
    return rows


def zone_lists(rows):
    """Country → every zone listed for it, in tab order."""
    out = {}
    for codes, zone in rows:
        for c in codes:
            out.setdefault(c, []).append(zone)
    return out


def main_zones(rows):
    """Country → (first zone listed, number of zones listed) in tab order, ignoring ZONE_EXCLUSIONS;
    a country whose only zones are excluded keeps none."""
    out = {}
    for c, zs in zone_lists(rows).items():
        kept = [z for z in zs if z not in ZONE_EXCLUSIONS]
        if kept:
            out[c] = (kept[0], len(kept))
    return out


def excluded_of(k, lists):
    """Documented note of the zones ignored for a country ('zone (reason)', '; '-joined), or None."""
    ex = ["%s (%s)" % (z, ZONE_EXCLUSIONS[z]) for z in lists.get(k, []) if z in ZONE_EXCLUSIONS]
    return "; ".join(ex) or None


def exclusion_effect(lists):
    """Countries whose multi-zone status changes because of ZONE_EXCLUSIONS: (country, before, after)."""
    out = []
    for c, zs in sorted(lists.items()):
        after = len([z for z in zs if z not in ZONE_EXCLUSIONS])
        if after != len(zs):
            out.append((c, len(zs), after))
    return out


def offsets_differ_at(a, b, start, end):
    """Hours (UTC) in [start, end) at which zones a and b have different UTC offsets."""
    za, zb, t, out = zoneinfo.ZoneInfo(a), zoneinfo.ZoneInfo(b), start, []
    while t < end:
        if t.astimezone(za).utcoffset() != t.astimezone(zb).utcoffset():
            out.append(t)
        t += datetime.timedelta(hours=1)
    return out


def verify_exclusions(lists):
    """Each excluded zone vs its country's kept main zone: same offset every hour of the window, else
    abort. Returns report lines (incl. the last differing hour since 1970, for the record)."""
    notes = []
    for c, zs in sorted(lists.items()):
        kept = [z for z in zs if z not in ZONE_EXCLUSIONS]
        for z in (z for z in zs if z in ZONE_EXCLUSIONS):
            bad = offsets_differ_at(kept[0], z, VERIFY_FROM, VERIFY_TO)
            if bad:
                sys.exit("exclusion %s (%s): offset differs from %s at %s" % (z, c, kept[0], bad[0].isoformat()))
            hist = offsets_differ_at(kept[0], z, datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc), VERIFY_FROM)
            notes.append("exclusion check: %s %s excluded, kept %s — same offset every hour %s…%s; last differed %s" % (
                c, z, kept[0], VERIFY_FROM.date(), VERIFY_TO.date(), hist[-1].isoformat() if hist else "never since 1970"))
    return notes


def sql_lit(v):
    """SQL literal for str / int / None."""
    if v is None:
        return "NULL"
    if isinstance(v, int):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


def first_day_of(k, fd):
    """(first_day_dow, source) for a country: override, else CLDR explicit value, else NULL (→ 001)."""
    if k in FIRST_DAY_OVERRIDES:
        return FIRST_DAY_OVERRIDES[k]
    return (fd[k], "CLDR") if k in fd else (None, None)


def zone_of(k, zones):
    """(main_timezone, tz_zone_count, source) for a country: override, else first zone.tab row."""
    z = zones.get(k)
    if k in TZ_OVERRIDES:
        return TZ_OVERRIDES[k][0], (z[1] if z else 0), TZ_OVERRIDES[k][1]
    return (z[0], z[1], "zone.tab") if z else (None, 0, None)


def build_rows(wd, zones, lists):
    """One row per country known to CLDR weekData or zone.tab, plus the 001 world row."""
    fd, ws, we = (region_map(wd[k]) for k in ("firstDay", "weekendStart", "weekendEnd"))
    keys = sorted(set(fd) | set(ws) | set(we) | set(zones))
    rows = []
    for k in keys:
        f, fsrc = first_day_of(k, fd)
        tz, n, tsrc = zone_of(k, zones)
        rows.append((k, f, ws.get(k), we.get(k), tz, n, fsrc, tsrc, excluded_of(k, lists)))
    return rows


def compare(rows, z1970):
    """Report: effective Monday-start countries whose weekend does not start Saturday; zone1970 vs zone.tab."""
    world = {r[0]: r for r in rows}[WORLD]
    notes = []
    for k, fd, ws, _we, tz, _n, _fs, _ts, _ex in rows:
        if k == WORLD:
            continue
        efd = fd if fd is not None else world[1]
        ews = ws if ws is not None else world[2]
        if efd == 1 and ews != 6:
            notes.append("monday-start %s: CLDR weekendStart=%d → last workday %d (not Friday)" % (k, ews, (ews + 6) % 7))
        if tz and k in z1970 and z1970[k][0] != tz:
            notes.append("zone: %s zone.tab first=%s, zone1970.tab first=%s" % (k, tz, z1970[k][0]))
    return notes


def render(rows, cldr_ver, tzver):
    """The generated SQL (table + full reload + source row)."""
    out = [
        "-- =============================================================================",
        "-- CHR-ETRS MVP v1.6.10 · ref_country_calendar.sql — GENERATED, DO NOT EDIT BY HAND",
        "-- Generator: tools/gen_ref_country_calendar.py",
        "-- Source: %s supplemental/weekData.json (firstDay, weekendStart, weekendEnd);" % cldr_ver,
        "--         IANA tz database %s zone.tab (main zone = first row of the country)." % tzver,
        "-- Day of week 0–6 = Sunday … Saturday. NULL = CLDR has no explicit value (fall back to 001).",
        "-- Overrides (explicit, documented): IL firstDay = Sunday (Karin 20.10); XK = Europe/Belgrade,",
        "--   AN = America/Curacao (Chief of Drive 20.10, O-43); UA = Europe/Kyiv (Chief of Drive 21.10, O-51).",
        "--   See *_source columns.",
        "-- Zone exclusion list: zones ignored for multi-zone detection — Europe/Busingen (DE, v1.6.8); Asia/Famagusta",
        "--   (CY), Pacific/Kwajalein (MH), Asia/Kuching (MY), Asia/Hebron (PS) (v1.6.9, O-51), Asia/Samarkand (UZ,",
        "--   v1.6.10: capital Asia/Tashkent kept); each checked to have the kept zone's UTC offset — see",
        "--   tz_zones_excluded; tz_zone_count counts the rest. A pinned zone (main_timezone_source 'override: …')",
        "--   is never needs_review (v1.6.10, applied in schema.sql fn_country_tz_needs_review).",
        "-- No BEGIN/COMMIT here: the caller decides the transaction (migration runs it inside its own).",
        "-- =============================================================================",
        "CREATE TABLE IF NOT EXISTS ref_country_calendar (",
        "    country           text PRIMARY KEY CHECK (country = '001' OR country ~ '^[A-Z]{2}$'),",
        "    first_day_dow     smallint CHECK (first_day_dow BETWEEN 0 AND 6),",
        "    weekend_start_dow smallint CHECK (weekend_start_dow BETWEEN 0 AND 6),",
        "    weekend_end_dow   smallint CHECK (weekend_end_dow BETWEEN 0 AND 6),",
        "    main_timezone     text,",
        "    tz_zone_count     int NOT NULL DEFAULT 0,  -- zone.tab zones minus excluded ones; > 1 = multi-zone",
        "    first_day_source  text,                    -- 'CLDR' | 'override: …' | NULL (→ 001)",
        "    main_timezone_source text,                 -- 'zone.tab' | 'override: …' | NULL",
        "    tz_zones_excluded text                     -- zones ignored for the count, with the ruling",
        ");",
        "ALTER TABLE ref_country_calendar ADD COLUMN IF NOT EXISTS first_day_source text;",
        "ALTER TABLE ref_country_calendar ADD COLUMN IF NOT EXISTS main_timezone_source text;",
        "ALTER TABLE ref_country_calendar ADD COLUMN IF NOT EXISTS tz_zones_excluded text;",
        "CREATE TABLE IF NOT EXISTS ref_country_calendar_source (",
        "    id int PRIMARY KEY CHECK (id = 1), cldr_source text NOT NULL, tz_source text NOT NULL);",
        "DELETE FROM ref_country_calendar;",
        "INSERT INTO ref_country_calendar (country, first_day_dow, weekend_start_dow, weekend_end_dow, main_timezone, tz_zone_count, first_day_source, main_timezone_source, tz_zones_excluded) VALUES",
    ]
    vals = ["  (%s)" % ", ".join(sql_lit(v) for v in r) for r in rows]
    out.append(",\n".join(vals) + ";")
    out.append("INSERT INTO ref_country_calendar_source VALUES (1, %s, %s)" % (
        sql_lit(cldr_ver + " supplemental/weekData.json"), sql_lit("IANA tzdata %s zone.tab" % tzver)))
    out.append("  ON CONFLICT (id) DO UPDATE SET cldr_source = EXCLUDED.cldr_source, tz_source = EXCLUDED.tz_source;")
    return "\n".join(out) + "\n"


def main():
    """CLI entry point."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--cldr", required=True)
    ap.add_argument("--tzdir", default="/usr/share/zoneinfo")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cldr_ver, wd = load_cldr(a.cldr)
    tab = read_tab(os.path.join(a.tzdir, "zone.tab"))
    zoneinfo.reset_tzpath([a.tzdir])
    zones, lists = main_zones(tab), zone_lists(tab)
    checks = verify_exclusions(lists)
    z1970 = main_zones(read_tab(os.path.join(a.tzdir, "zone1970.tab")))
    rows = build_rows(wd, zones, lists)
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(render(rows, cldr_ver, tz_version(a.tzdir)))
    for n in compare(rows, z1970):
        print(n, file=sys.stderr)
    for c, before, after in exclusion_effect(lists):
        status = "multi-zone → single-zone" if before > 1 and after <= 1 else "zone count only"
        print("exclusion: %s %d → %d zones (%s)" % (c, before, after, status), file=sys.stderr)
    for n in checks:
        print(n, file=sys.stderr)
    multi = sorted(k for k, _f, _s, _e, _tz, n, _fs, _ts, _ex in rows if n > 1)
    review = sorted(k for k, _f, _s, _e, _tz, n, _fs, ts, _ex in rows if n > 1 and not (ts or "").startswith("override:"))
    print("multi-zone countries (zone count > 1): %d (%s)" % (len(multi), ", ".join(multi)), file=sys.stderr)
    print("multi-zone needing review (not pinned): %d (%s)" % (len(review), ", ".join(review)), file=sys.stderr)
    print("rows=%d source=%s tz=%s" % (len(rows), cldr_ver, tz_version(a.tzdir)), file=sys.stderr)


if __name__ == "__main__":
    main()
