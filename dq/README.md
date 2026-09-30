# Data-quality gate

These checks run **after** the CTAS build and **before** the Redshift `COPY`. The
orchestrator reads each check's `failures` column; **any** value `> 0` is a hard stop.
The principle is the one an operations team actually cares about: a wrong number must
fail loudly *before* it reaches a deliverable, not get discovered in a dashboard.

Every check is designed to catch a specific failure mode. It is a safeguard — its
presence is not a claim that a bad load has happened.

| # | Check | Failure mode it protects against | Technique |
|---|---|---|---|
| 1 | Row reconciliation | Silent row loss in the ETL | count reconciliation: `raw = fact + excluded ± tolerance`, with the excluded count reported so drops are auditable |
| 2 | Referential integrity | Orphan fact rows (missing dim key) that vanish from an inner-join query | `NOT EXISTS` anti-join, fact → each dim |
| 3 | Range / domain | Fat-finger fares, impossible distance/duration, bad codes | bounded `CASE` assertions summed to a failure count |
| 4 | Grain uniqueness | Double-counted trips inflating revenue/volume | `GROUP BY trip_key HAVING COUNT(*) > 1` |
| 5 | Schema drift | TLC renaming/removing a column across months, silently nulling a measure | `information_schema.columns` vs an expected column set |
| 6 | Window completeness | A missing month biasing the pre/post comparison | `COUNT(DISTINCT year_month) = 15` |

## Tuning note

The tolerance in check 1 (2%) and the outlier bounds in check 3 are starting points.
After the first profiling run, tighten them to what the data actually shows — an
honest gate is calibrated to observed distributions, not left at placeholder values.
Record the tuned thresholds here so the choice is reviewable.

## Why this matters for the analysis

The congestion-pricing DiD compares treated vs control zones before and after Jan 5,
2025. A silently dropped month (check 6) or a zone-key mismatch (check 2) would bias
that comparison directly — so the quality gate is not decoration, it is a precondition
for the causal estimate being trustworthy.
