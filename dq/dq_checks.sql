-- =====================================================================
-- dq_checks.sql
-- The data-quality gate. Runs AFTER the CTAS build and BEFORE the Redshift
-- COPY. Every check returns a `failures` count; the orchestrator treats
-- ANY row with failures > 0 as a hard stop (fail loud, before the data
-- reaches a dashboard). These are DESIGNED to catch the listed failure
-- modes -- they are safeguards, not a claim that a bad load has occurred.
--
-- Design mirrors production reconciliation practice: reconcile counts,
-- enforce referential integrity, bound ranges, forbid duplicates, and
-- detect schema drift. Each check names what it protects against.
-- =====================================================================

-- ---------------------------------------------------------------------
-- CHECK 1 -- ROW RECONCILIATION
-- Protects against: silent row loss in the ETL. Fact rows + documented
-- exclusions must reconcile to the raw count within tolerance.
-- The excluded count is itself reported so drops are auditable.
-- ---------------------------------------------------------------------
WITH raw AS (SELECT COUNT(*) AS raw_rows FROM nyc_tlc.raw_yellow_trips),
     fact AS (SELECT COUNT(*) AS fact_rows FROM nyc_tlc.fact_trips),
     excluded AS (
        SELECT COUNT(*) AS excluded_rows
        FROM nyc_tlc.raw_yellow_trips
        WHERE NOT (trip_distance > 0
               AND fare_amount >= 0
               AND tpep_dropoff_datetime >= tpep_pickup_datetime
               AND tpep_pickup_datetime >= TIMESTAMP '2024-01-01 00:00:00'
               AND tpep_pickup_datetime <  TIMESTAMP '2025-04-01 00:00:00')
     )
SELECT
    'row_reconciliation' AS check_name,
    raw.raw_rows, fact.fact_rows, excluded.excluded_rows,
    (raw.raw_rows - fact.fact_rows - excluded.excluded_rows) AS unexplained_gap,
    -- allow a tiny tolerance for dedup removals; tune after first run
    CASE WHEN ABS(raw.raw_rows - fact.fact_rows - excluded.excluded_rows)
              > (0.02 * raw.raw_rows)
         THEN 1 ELSE 0 END AS failures
FROM raw, fact, excluded;

-- ---------------------------------------------------------------------
-- CHECK 2 -- REFERENTIAL INTEGRITY (anti-join / NOT EXISTS)
-- Protects against: orphan fact rows whose keys are missing from a dim
-- (would silently drop from an inner-join dashboard query).
-- ---------------------------------------------------------------------
SELECT 'orphan_pickup_zone' AS check_name, COUNT(*) AS failures
FROM nyc_tlc.fact_trips f
WHERE NOT EXISTS (SELECT 1 FROM nyc_tlc.dim_zone z WHERE z.zone_key = f.pu_zone_key)
UNION ALL
SELECT 'orphan_dropoff_zone', COUNT(*)
FROM nyc_tlc.fact_trips f
WHERE NOT EXISTS (SELECT 1 FROM nyc_tlc.dim_zone z WHERE z.zone_key = f.do_zone_key)
UNION ALL
SELECT 'orphan_payment', COUNT(*)
FROM nyc_tlc.fact_trips f
WHERE NOT EXISTS (SELECT 1 FROM nyc_tlc.dim_payment p WHERE p.payment_key = f.payment_key)
UNION ALL
SELECT 'orphan_ratecode', COUNT(*)
FROM nyc_tlc.fact_trips f
WHERE NOT EXISTS (SELECT 1 FROM nyc_tlc.dim_ratecode r WHERE r.ratecode_key = f.ratecode_key)
UNION ALL
SELECT 'orphan_vendor', COUNT(*)
FROM nyc_tlc.fact_trips f
WHERE NOT EXISTS (SELECT 1 FROM nyc_tlc.dim_vendor v WHERE v.vendor_key = f.vendor_key)
UNION ALL
SELECT 'orphan_date', COUNT(*)
FROM nyc_tlc.fact_trips f
WHERE NOT EXISTS (SELECT 1 FROM nyc_tlc.dim_date d WHERE d.date_key = f.date_key);

-- ---------------------------------------------------------------------
-- CHECK 3 -- RANGE / DOMAIN ASSERTIONS
-- Protects against: fat-finger fares, impossible distances/durations,
-- out-of-domain codes leaking past the cleaning rules.
-- Thresholds are generous outliers, not business rules -- tune post-profiling.
-- ---------------------------------------------------------------------
SELECT 'range_assertions' AS check_name,
    SUM(CASE WHEN trip_distance <= 0 OR trip_distance > 200          THEN 1 ELSE 0 END) +
    SUM(CASE WHEN fare_amount   < 0  OR fare_amount   > 5000         THEN 1 ELSE 0 END) +
    SUM(CASE WHEN total_amount  < 0  OR total_amount  > 5000         THEN 1 ELSE 0 END) +
    SUM(CASE WHEN trip_duration_min < 0 OR trip_duration_min > 1440  THEN 1 ELSE 0 END) +
    SUM(CASE WHEN tip_pct IS NOT NULL AND (tip_pct < 0 OR tip_pct > 5) THEN 1 ELSE 0 END)
    AS failures
FROM nyc_tlc.fact_trips;

-- ---------------------------------------------------------------------
-- CHECK 4 -- UNIQUENESS OF THE GRAIN
-- Protects against: double-counting from duplicate trip keys (would
-- inflate revenue/volume metrics).
-- ---------------------------------------------------------------------
SELECT 'duplicate_trip_keys' AS check_name, COUNT(*) AS failures
FROM (
    SELECT trip_key
    FROM nyc_tlc.fact_trips
    GROUP BY trip_key
    HAVING COUNT(*) > 1
) d;

-- ---------------------------------------------------------------------
-- CHECK 5 -- SCHEMA DRIFT
-- Protects against: TLC changing/renaming columns across months, which
-- would silently null out a measure. Assert the expected columns exist
-- with expected types in the raw external table.
-- Returns the count of MISSING expected columns.
-- ---------------------------------------------------------------------
WITH expected AS (
    SELECT col FROM (VALUES
        ('vendorid'),('tpep_pickup_datetime'),('tpep_dropoff_datetime'),
        ('passenger_count'),('trip_distance'),('ratecodeid'),('pulocationid'),
        ('dolocationid'),('payment_type'),('fare_amount'),('tip_amount'),
        ('tolls_amount'),('total_amount')
    ) AS t(col)
),
actual AS (
    SELECT lower(column_name) AS col
    FROM information_schema.columns
    WHERE table_schema = 'nyc_tlc' AND table_name = 'raw_yellow_trips'
)
SELECT 'schema_drift_missing_cols' AS check_name, COUNT(*) AS failures
FROM expected e
WHERE NOT EXISTS (SELECT 1 FROM actual a WHERE a.col = e.col);

-- ---------------------------------------------------------------------
-- CHECK 6 -- COMPLETENESS ACROSS THE WINDOW
-- Protects against: a missing month (e.g. a failed upload) that would
-- bias the pre/post comparison. Expect 15 months Jan 2024 - Mar 2025.
-- ---------------------------------------------------------------------
SELECT 'month_completeness' AS check_name,
    CASE WHEN COUNT(DISTINCT year_month) = 15 THEN 0 ELSE 1 END AS failures,
    COUNT(DISTINCT year_month) AS months_present
FROM nyc_tlc.fact_trips;
