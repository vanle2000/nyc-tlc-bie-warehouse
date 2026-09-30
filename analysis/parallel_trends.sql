-- =====================================================================
-- parallel_trends.sql
-- The identifying-assumption check for the DiD: BEFORE the policy, do
-- treated (CBD pickup) and control (non-CBD) zones move together?
-- DiD is only credible if the pre-period trends are parallel. This query
-- produces the monthly series to plot; eyeball parallelism in the 12
-- pre-months (Jan-Dec 2024) and confirm with the pre-period interaction
-- test in analysis/analysis.ipynb.
--
-- Metric = trips per zone-day (volume), normalized so the two groups are
-- comparable despite different zone counts. Swap the measure to avg
-- tip_pct or avg trip_distance to check those outcomes too.
-- =====================================================================
WITH daily AS (
    SELECT
        d.date,
        d.year_month,
        f.pu_is_cbd,
        COUNT(*) AS trips
    FROM tlc.fact_trips f
    JOIN tlc.dim_date d ON d.date_key = f.date_key
    GROUP BY d.date, d.year_month, f.pu_is_cbd
),
zone_counts AS (   -- treated vs control zone counts, to normalize per-zone
    SELECT pu_is_cbd, COUNT(DISTINCT zone_key) AS n_zones
    FROM tlc.dim_zone
    JOIN tlc.fact_trips ON zone_key = pu_zone_key
    GROUP BY pu_is_cbd
)
SELECT
    daily.year_month,
    CASE WHEN daily.pu_is_cbd = 1 THEN 'treated_CBD' ELSE 'control_nonCBD' END AS grp,
    ROUND(AVG(daily.trips * 1.0 / zc.n_zones), 1) AS avg_trips_per_zone_day
FROM daily
JOIN zone_counts zc ON zc.pu_is_cbd = daily.pu_is_cbd
GROUP BY daily.year_month,
         CASE WHEN daily.pu_is_cbd = 1 THEN 'treated_CBD' ELSE 'control_nonCBD' END
ORDER BY daily.year_month, grp;
