# db/config — reviewed configuration (v1.7.0, Karin 16.11)

כל הקבצים כאן **מתחילים ריקים**. ערך נכנס רק דרך PR שעבר review, ואחר כך `tools/sync_config.py` טוען אותו ל-DB
כ-service role (פונקציות מערכת; לקוח לא יכול לקרוא להן). אין כאן מספרים, כתובות או מפתחות שהומצאו.
סודות (מפתח ה-HMAC של קוד החברה למחקר ושל מספר הכרטיס) **לא** נשמרים כאן — הם בכספת הסודות של השרת בלבד
(`chr.secret_research_company`, `chr.secret_badge`).

| קובץ | פונקציה | מבנה | J |
|---|---|---|---|
| `research_dpa.json` | `fn_sync_research_config` | `{"researchers": [{email, full_name, timezone}], "dpas": [{company_id, researcher_email, dpa_signed_on, dpa_valid_until}]}` — DPA לכל זוג (חברה, חוקר/ת), עד שנתיים | J-181, J-187, J-189 |
| `everstore_supplier_offers.json` | `fn_sync_supplier_offers` | `{"suppliers": [{supplier_key, name, order_email, offers: [{item_id, display_name, name_he, category, price_golden_spoons, tier}]}]}` | J-211, J-212 |
| `method_team.json` | `fn_sync_method_team` | `{"recipients": ["address", …]}` — כתובות צוות השיטה להערות חוקרים | J-191 |
| `platform_operator.json` | `fn_sync_platform_operator` | `{"recipients": ["address", …]}` — כתובת/ות מפעיל CHR-ETRS (נמען אחרון לתזכורת עמותת ברירת מחדל כשאין vp_hr ואין cfo פעילים). הכתובת **לא ידועה** — הקובץ ריק; כל עוד הוא ריק ההודעה נרשמת ב-outbox כשורה מוחזקת (נמען 'לא הוגדר', `hold_reason = recipient_not_configured`) ומשוחררת בטעינה. `tools/preflight.py` נכשל כל עוד הקובץ ריק | J-250, J-251 |
| `company_service_end.json` | `fn_sync_company_service_end` | `{"companies": [{company_id, service_ended_at}]}` — סיום שירות (מתחיל ספירת 24 החודשים לארכיון, DRAFT) | J-190 |

הטעינה לא מוחקת דבר: חוקר/ת, DPA או הצעת ספק שיצאו מהקובץ נשארים עד צעד ידני שעבר review.
