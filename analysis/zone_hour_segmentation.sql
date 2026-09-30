-- =====================================================================
-- zone_hour_segmentation.sql
-- Operational analysis (Business Acumen): which pickup-zone x daypart
-- segments are most revenue-efficient, so driver supply can be steered.
-- Uses window functions to rank segments and quantify concentration --
-- the "which segments carry the value" question, answered with a number.
-- =====================================================================
WITH seg AS (
    SELECT
        z.borough,
        z.zone,
        t.daypart,
        COUNT(*)                          AS trips,
        SUM(f.total_amount)               AS revenue,
        AVG(f.total_amount)               AS avg_fare,
        AVG(f.trip_duration_min)          AS avg_duration_min,
        -- revenue per minute = a proxy for driver-time efficiency
        SUM(f.total_amount) / NULLIF(SUM(f.trip_duration_min), 0) AS revenue_per_min
    FROM tlc.fact_trips f
    JOIN tlc.dim_zone z ON z.zone_key = f.pu_zone_key
    JOIN tlc.dim_time t ON t.time_key = f.time_key
    GROUP BY z.borough, z.zone, t.daypart
),
ranked AS (
    SELECT *,
        RANK()       OVER (ORDER BY revenue_per_min DESC)              AS efficiency_rank,
        ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)              AS pct_of_total_revenue,
        NTILE(10)    OVER (ORDER BY revenue_per_min DESC)             AS efficiency_decile
    FROM seg
    WHERE trips >= 1000    -- ignore thin segments that are noise
)
SELECT
    efficiency_rank,
    borough, zone, daypart,
    trips,
    ROUND(revenue, 0)          AS revenue,
    ROUND(avg_fare, 2)         AS avg_fare,
    ROUND(revenue_per_min, 3)  AS revenue_per_min,
    pct_of_total_revenue,
    efficiency_decile
FROM ranked
ORDER BY efficiency_rank
LIMIT 25;

-- Concentration summary: how much revenue the top efficiency decile carries.
WITH seg AS (
    SELECT z.zone, t.daypart,
           SUM(f.total_amount) AS revenue,
           SUM(f.total_amount) / NULLIF(SUM(f.trip_duration_min),0) AS revenue_per_min,
           COUNT(*) AS trips
    FROM tlc.fact_trips f
    JOIN tlc.dim_zone z ON z.zone_key = f.pu_zone_key
    JOIN tlc.dim_time t ON t.time_key = f.time_key
    GROUP BY z.zone, t.daypart
    HAVING COUNT(*) >= 1000
),
d AS (SELECT *, NTILE(10) OVER (ORDER BY revenue_per_min DESC) AS decile FROM seg)
SELECT
    CASE WHEN decile = 1 THEN 'top_decile' ELSE 'rest' END AS bucket,
    COUNT(*)                                   AS segments,
    ROUND(SUM(revenue), 0)                     AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue
FROM d
GROUP BY CASE WHEN decile = 1 THEN 'top_decile' ELSE 'rest' END;
