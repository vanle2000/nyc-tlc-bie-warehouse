-- =====================================================================
-- placebo_test.sql
-- Falsification test. Re-run the DiD using a FAKE cutoff inside the
-- pre-treatment period (2024-07-01), on pre-period data ONLY (Jan-Dec
-- 2024). There was no policy then, so a well-identified design should
-- return a DiD estimate near ZERO. A large "effect" at the fake cutoff
-- means the treated/control gap was already moving -- i.e. the real DiD
-- would be confounded. This is the honesty check on the headline number.
-- =====================================================================
WITH zone_counts AS (
    SELECT pu_is_cbd, COUNT(DISTINCT zone_key) AS n_zones
    FROM tlc.dim_zone JOIN tlc.fact_trips ON zone_key = pu_zone_key
    GROUP BY pu_is_cbd
),
base AS (
    SELECT
        f.pu_is_cbd,
        CASE WHEN d.date >= DATE '2024-07-01' THEN 'fake_post' ELSE 'fake_pre' END AS fake_period,
        d.date,
        COUNT(*) AS trips
    FROM tlc.fact_trips f
    JOIN tlc.dim_date d ON d.date_key = f.date_key
    WHERE d.date < DATE '2025-01-05'          -- pre-treatment window ONLY
    GROUP BY f.pu_is_cbd,
             CASE WHEN d.date >= DATE '2024-07-01' THEN 'fake_post' ELSE 'fake_pre' END,
             d.date
),
cell AS (
    SELECT b.pu_is_cbd, b.fake_period,
           SUM(b.trips) * 1.0 / (COUNT(DISTINCT b.date) * MAX(zc.n_zones)) AS trips_per_zone_day
    FROM base b JOIN zone_counts zc ON zc.pu_is_cbd = b.pu_is_cbd
    GROUP BY b.pu_is_cbd, b.fake_period
)
SELECT
    'placebo_volume' AS test,
    ROUND(
        (MAX(CASE WHEN pu_is_cbd=1 AND fake_period='fake_post' THEN trips_per_zone_day END)
       - MAX(CASE WHEN pu_is_cbd=1 AND fake_period='fake_pre'  THEN trips_per_zone_day END))
      - (MAX(CASE WHEN pu_is_cbd=0 AND fake_period='fake_post' THEN trips_per_zone_day END)
       - MAX(CASE WHEN pu_is_cbd=0 AND fake_period='fake_pre'  THEN trips_per_zone_day END))
    , 2) AS placebo_did_estimate_should_be_near_zero
FROM cell;
