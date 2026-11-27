<!-- CHR-ETRS · HR absence import archive (J-330) · Spec only — NOT BUILT. Decisions: Karin 27.11, recorded in ADR_GAPS.md (ninth round). -->
# Secret system archive log of HR absence import staging (J-330)

**Status: NOT BUILT, blocked on J-283 privacy review and the retention decision (J-345).**

This document is the full spec of the archive Karin required after commit (J-330, 25.11; decisions J-339 – J-345, 27.11). Nothing here is implemented in PR #12. Do not invent a retention period, a legal duty, or a notification channel. Unset periods stay **לא הוגדר**.

Related record: `ADR_GAPS.md` (eighth-round proposal, ninth-round decisions, open interpretations J-355 – J-356). J-346 – J-354 are still open and are not part of this spec.

---

## 1. Purpose

After an HR absence import is committed, the staging data **moves** into a secret system archive log. The live `hr_absence_entry` rows stay as they are, including the kind, for HR (J-342). Staging itself is not the long-term store: the commit writes the archive in the same transaction and then deletes the staged row cells, leaving only the batch header with counts.

The archive is for later reading by a closed set of company roles (below). It is not an export, not a CHRO view, and not a second HR work-list.

---

## 2. Readers and per-role view (J-339, J-340, J-341)

**How a reader is identified (J-339 A).** No new role and no per-company grant list. A reader is identified by an **existing role**, **active**, in the **same company**. Permission is checked on **every open** (never cached). Every view is **logged** (who, when, what — company and batch, and which view class was returned; **no kind**, and no identity keys in the audit row).

**Role list (J-340 + J-341), recorded by content.** J-339 named the mechanism (existing roles). The roles themselves are:

| Who | How identified | What they see in this archive |
|---|---|---|
| Any VP | org role `vp` or `evp` (`schema.sql:327–328`), or the app role `vp_hr` | The archive as stored: codes, counts, outcomes, dates, row numbers, and identity keys (employee number and e-mail as typed) until those keys are removed at the end of the retention period. **Never the kind** (the kind is not stored — J-342). |
| CEO | org role `ceo` (`schema.sql:329`) | **Codes and counts only.** Never the kind, and never identity keys (employee number, e-mail, or any other name or id). The averages-only lock is kept (J-341). |
| Owners | org role `owner_shareholder` (`schema.sql:332`) | The same restricted view as the CEO (J-341). |
| cfo | app role `cfo` | **No full access** to this archive (J-340). A separate permission applies only if a future split exists — see §3. |
| Anyone else, another company, or an inactive role | — | The same 403 (see §6). |

`vp_hr` is a reader because 'any VP' includes her (J-340). Combined with J-343 A she gets **no extra access** beyond the other full readers (org `vp` / `evp`): same view, same log, same permission check. Owners are provisioned by vp_hr (`rpc_provision_governance_user`, `rpc.sql:4834`); `ceo` / `vp` / `evp` are set at provisioning or migration only (O-46: every migrated user starts as `employee`).

Active means the same employment rule already used for these roles (an end date that has been reached, or no role in this company, is not a reader). Permission is re-checked on every open, so a role change or an end of employment takes effect immediately.

---

## 3. cfo financial-part permission (conditional on a split)

The cfo gets **no** full access to the HR absence import archive (J-340).

**If** the secret archive is later split by data type, the cfo gets a **separate** permission for the **financial part only**: EverStore budget, unredeemed spoon liability (unredeemed כפיות מוזהבות), and board reports. That permission does **not** open the HR absence import part (and does not reveal the kind or HR identity keys).

A split is **not designed here**. This archive, as specified, holds import-staging outcomes of HR absence days; it has no EverStore budget, no spoon liability and no board-report payload. The cfo rule is recorded so a future split cannot silently give the cfo the HR part, and so the privacy review can see it.

---

## 4. Table design (without the kind)

**Working name:** `hr_absence_import_archive` (name may change at build time; the shape below is what is decided).

**What is stored (J-342).** The moved staging data **without the kind**, until the privacy advisor review (J-283) says otherwise:

- batch id, company id, committed at, committed by, archived at;
- per staged row: file row number, action, absence date (as typed / as parsed), outcome, code, winner row number;
- identity keys, until J-344 expiry: employee number and e-mail **as typed** in the file;
- batch-level counts (rows, accepted, rejected, duplicate, superseded, exception, and the written put / cancel counts already on the header).

The kind (`sick` / `other`) is **not** copied into the archive. It stays in the live `hr_absence_entry` for HR, and — since J-280 (Karin 27.11, replaced J-280 B) — NOT in the per-row WORM `access_audit_log` write rows (`hr_absence_put` / `hr_absence_cancel`) either: they record only that the kind was set (`kind_set`), who and when. Rejected, exception and superseded file rows therefore leave **no kind** in the archive.

**J-338 header link.** The existing WORM header row `hr_absence_import_commit` already holds the source file name and the SHA-256, plus the counts (`rpc.sql` commit path; J-338 A). The archive **keys on the same `import_batch_id`** and does **not** repeat the file name or the hash — one place for them. A reader who is allowed the header fields reads them from that audit row (or a join on the batch id), not from a second copy.

**WORM and access.**

- Append-only: an update / delete trigger in the same family as `access_audit_log` (WORM 403).
- RLS forced, no policy, no client `SELECT` / `INSERT` / `UPDATE` / `DELETE` grant.
- Written only by the import commit (SECURITY DEFINER), in the same transaction as the HR writes.
- After a successful write, the staged row cells are deleted so the data has moved, not been copied; the batch header (status `committed`, counts, fingerprint) remains.

**Open conflict (not resolved here):** J-344 requires that, at the end of the retention period, identity keys are **removed** while codes and counts stay forever, and the records themselves are **not deleted**. Removing fields from a WORM table conflicts with the WORM trigger and with the standing rule **לא למחוק כלום**, and must be reconciled with O-14 (crypto-shredding). Options and a recommendation are in `ADR_GAPS.md` **J-355** and **J-356**. Do not pick a mechanism in this spec.

---

## 5. Retention (J-344)

- The retention **period** is **לא הוגדר**. It is decided with the privacy advisor **before** the archive is built (J-344, J-345).
- When that period ends: records are **not** deleted; **only** the identity keys (employee number, e-mail) are removed; **codes and counts stay forever**.
- No purge job, no period, and no key-removal job are built now. Nothing in this document invents a number of days.

---

## 6. Read RPC

**Working name:** `rpc_hr_import_archive_read(p_company_id, p_batch_id)` (name may change at build time).

- SECURITY DEFINER, granted only to `authenticated`.
- **Permission is checked on every open** (J-339): the caller must be an active reader of `p_company_id` as in §2.
- **Identical 403s:** a non-reader, a reader of another company, an inactive role, an unknown batch id, and a batch of another company all receive the **same** 403 (`access_denied` — the existing pattern; no existence hint).
- The payload is projected by role on that open:
  - vp / evp / vp_hr: the stored archive (no kind; keys present until removed);
  - CEO / owners: codes and counts only (no keys, no kind, no row-level identity);
  - cfo: refused for this HR archive (403 as above), unless a future financial split and a distinct RPC or filter for that part exist.
- One-time emergency access (justified request, second approver, logged, auto-expiry) is **not** built; it is a privacy-review item only (J-343).

**Read logging (J-339).** Every successful open writes one WORM `access_audit_log` row (working action name `hr_import_archive_read`): who (the viewer), when, what (company, batch, the view class returned — full or codes-and-counts — and a row count). **No kind. No employee number, e-mail, or other identity key.** A refused open may be logged the same way without distinguishing "no such batch" from "wrong company" in the payload; that detail is for the build, provided the 403 stays identical. This logging applies to **every** reader, including vp_hr (it is not a J-292 unlogged HR list: these are archive views, and J-339 requires a log).

---

## 7. Items for the J-283 privacy advisor review

These go to the pending privacy advisor review together. No duty, period, or design is assumed here.

1. **Separate or encrypt the kind from identity.** Under J-342 the archive does not store the kind at all until this review. If the kind is later added, it must be separated or encrypted so that it is not stored next to employee number and e-mail. The live `hr_absence_entry` and the J-280 B write-audit rows already hold the kind; this review should look at all three places together.
2. **Who in HR sees the kind, and whether views are logged.** Today: only an active vp_hr of the company (single-employee list and the company list, J-288 / J-293) and the employee herself (`rpc_hr_absence_my_list`, J-291 B). vp_hr reads of the live rows are **not** logged (J-292). Self-reads are logged, without the kind. Archive reads, when built, **are** logged (J-339), without the kind. The review should say whether live vp_hr views should also be logged, and whether that changes J-292.
3. **Any legal duty to keep absence records, and whether it belongs in CHR-ETRS or in payroll.** No legal duty is invented or assumed here (same stance as J-285 A / J-271 B). If a duty exists, the advisor should say what it requires (what is kept, for how long, identifiable or not) and whether it is a duty of this system or of payroll / the HR system that already receives the offboarding pending list (J-309).
4. **Emergency access (J-343).** A one-time emergency path — justified request, second approver, logged, auto-expiry — is in scope for this review only. It is **not** built.
5. **The retention period.** Still **לא הוגדר**. J-344: decide it before building; at the end, keys are removed, codes and counts stay forever. The mechanism for removing keys from a WORM store is an open conflict (J-355, J-356), for this review.
6. **J-299 D linkage.** Already on this review, to be decided with the retention policy: (1) an active vp_hr can read every employee's name, user id and sick days in one unlogged company-list call; (2) `full_name` stays on `users` after offboarding (O-14 does not clear it), so the company list can show leavers' names with their kinds indefinitely (retention **לא הוגדר**, J-271 B / J-285 A). J-344's key-removal at the end of the archive period does **not** by itself change the live list or `hr_absence_entry`. The three (live rows, company list, archive keys) should be decided together.

---

## 8. What is deliberately not in this document

- Build work, SQL, OpenAPI, or a notification channel (J-345, J-309).
- A chosen mechanism for J-344 key removal (see J-355, J-356).
- A retention number, a legal basis, or a processor agreement.
- Adding the kind to the archive, or lifting the CEO / owners averages-only lock.
- cfo access to HR rows, or a designed financial-archive split.
