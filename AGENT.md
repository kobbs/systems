 1. Category 1 (deduplication) — do first; lib/common.sh reduces noise in all subsequent diffs
 2. Category 2 (idempotency) — directly improves day-to-day re-run safety
 3. Category 3 (robustness) — fixes real silent failures in running scripts
 4. Category 4 (maintainability) — lower urgency but makes future changes easier
 5. Category 5 (error handling) — mostly additive, no risk of regression
 6. Category 6 (polish) — do last, purely cosmetic/minor
