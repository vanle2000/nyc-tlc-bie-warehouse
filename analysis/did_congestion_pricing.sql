-- =====================================================================
-- did_congestion_pricing.sql
-- Difference-in-differences, computed as group means in SQL (the "2x2"
-- DiD). Treated = CBD pickup zone (<=60th St); post = on/after 2025-01-05.
--
-- DiD estimate = (treated_post - treated_pre) - (control_post - control_pre)
--
-- Outcomes are BEHAVIORAL (trip volume per zone-day, avg trip_distance,
-- avg tip_pct). The 2025 road toll is paid by the vehicle; it is NOT the
-- pre-existing per-trip `congestion_surcharge` fare field, so we measure
-- how trips CHANGED, not a fare line item. See BUSINESS_QUESTIONS.md.
--
-- analysis/analysis.ipynb runs the equivalent regression with robust standard
-- errors so the estimate comes with uncertainty, not just a point value.
-- =====================================================================

-- ---- Outcome A: trip volume (trips per zone-day) ----
WITH zone_counts AS (
    SELECT pu_is_cbd, COUNT(DISTINCT zone_key) AS n_zones
    FROM tlc.dim_zone JOIN tlc.fact_trips ON zone_key = pu_zone_key
    GROUP BY pu_is_cbd
),
cell AS (
    SELECT
        f.pu_is_cbd,
        d.period,
        COUNT(*) * 1.0
          / (COUNT(DISTINCT d.date) * MAX(zc.n_zones)) AS trips_per_zone_day
    FROM tlc.fact_trips f
    JOIN tlc.dim_date d   ON d.date_key = f.date_key
    JOIN zone_counts zc   ON zc.pu_is_cbd = f.pu_is_cbd
    GROUP BY f.pu_is_cbd, d.period
),
p AS (
    SELECT
        MAX(CASE WHEN pu_is_cbd=1 AND period='pre'  THEN trips_per_zone_day END) AS t_pre,
        MAX(CASE WHEN pu_is_cbd=1 AND period='post' THEN trips_per_zone_day END) AS t_post,
        MAX(CASE WHEN pu_is_cbd=0 AND period='pre'  THEN trips_per_zone_day END) AS c_pre,
        MAX(CASE WHEN pu_is_cbd=0 AND period='post' THEN trips_per_zone_day END) AS c_post
    FROM cell
)
SELECT
    'volume_trips_per_zone_day' AS outcome,
    ROUND(t_pre,2)  AS treated_pre,  ROUND(t_post,2) AS treated_post,
    ROUND(c_pre,2)  AS control_pre,  ROUND(c_post,2) AS control_post,
    ROUND((t_post - t_pre), 2)                       AS treated_change,
    ROUND((c_post - c_pre), 2)                       AS control_change,
    ROUND((t_post - t_pre) - (c_post - c_pre), 2)    AS did_estimate,
    ROUND(100.0 * ((t_post - t_pre) - (c_post - c_pre)) / t_pre, 1) AS did_pct_of_treated_pre
FROM p;

-- ---- Outcome B: avg trip_distance,  Outcome C: avg tip_pct ----
-- Same 2x2 structure; averages instead of a normalized count.
WITH cell AS (
    SELECT
        f.pu_is_cbd, d.period,
        AVG(f.trip_distance) AS avg_distance,
        AVG(f.tip_pct)       AS avg_tip_pct
    FROM tlc.fact_trips f
    JOIN tlc.dim_date d ON d.date_key = f.date_key
    WHERE f.payment_key = 1     -- tip_pct only meaningful on card-paid trips
    GROUP BY f.pu_is_cbd, d.period
)
SELECT
    'avg_trip_distance' AS outcome,
    ROUND(MAX(CASE WHEN pu_is_cbd=1 AND period='post' THEN avg_distance END)
        - MAX(CASE WHEN pu_is_cbd=1 AND period='pre'  THEN avg_distance END)
        - MAX(CASE WHEN pu_is_cbd=0 AND period='post' THEN avg_distance END)
        + MAX(CASE WHEN pu_is_cbd=0 AND period='pre'  THEN avg_distance END), 3) AS did_estimate
FROM cell
UNION ALL
SELECT
    'avg_tip_pct',
    ROUND(MAX(CASE WHEN pu_is_cbd=1 AND period='post' THEN avg_tip_pct END)
        - MAX(CASE WHEN pu_is_cbd=1 AND period='pre'  THEN avg_tip_pct END)
        - MAX(CASE WHEN pu_is_cbd=0 AND period='post' THEN avg_tip_pct END)
        + MAX(CASE WHEN pu_is_cbd=0 AND period='pre'  THEN avg_tip_pct END), 4)
FROM cell;
