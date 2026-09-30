-- =====================================================================
-- 03_ctas_fact_trips.sql
-- Build fact_trips as partitioned Parquet in the CURATED layer via CTAS.
-- Grain = one completed trip (see sql/01_star_schema_design.md).
--
-- This one query demonstrates the SQL that matters for a BIE:
--   * multi-source joins  (trips -> date / time / zone / payment / ...)
--   * CTEs to layer the logic (clean -> key -> assemble)
--   * ROW_NUMBER() de-duplication of exact duplicate trip records
--   * derived measures computed ONCE (tip_pct, trip_duration_min)
--   * the documented cleaning rules from the design doc as WHERE clauses
--
-- Partitioned by year_month to keep the Redshift COPY and any Athena
-- re-reads pruned and cheap. Replace <BUCKET>.
-- =====================================================================

CREATE TABLE nyc_tlc.fact_trips
WITH (
    format = 'PARQUET',
    partitioned_by = ARRAY['year_month'],
    external_location = 's3://<BUCKET>/curated/fact_trips/'
) AS

WITH cleaned AS (
    -- Apply the documented grain rules. Rows failing these are excluded
    -- here and COUNTED in dq/dq_checks.sql so the drop is auditable.
    SELECT
        t.VendorID,
        t.tpep_pickup_datetime  AS pickup_ts,
        t.tpep_dropoff_datetime AS dropoff_ts,
        t.passenger_count,
        t.trip_distance,
        COALESCE(t.RatecodeID, 99)  AS ratecode_id,
        t.PULocationID,
        t.DOLocationID,
        t.payment_type,
        t.fare_amount,
        t.tip_amount,
        t.tolls_amount,
        t.total_amount
    FROM nyc_tlc.raw_yellow_trips t
    WHERE t.trip_distance > 0
      AND t.fare_amount >= 0
      AND t.tpep_dropoff_datetime >= t.tpep_pickup_datetime
      AND t.tpep_pickup_datetime >= TIMESTAMP '2024-01-01 00:00:00'
      AND t.tpep_pickup_datetime <  TIMESTAMP '2025-04-01 00:00:00'
),

deduped AS (
    -- Exact-duplicate trip records occasionally appear. Keep one per
    -- natural key (vendor + pickup instant + pickup zone + total).
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY VendorID, pickup_ts, PULocationID, total_amount
            ORDER BY dropoff_ts
        ) AS rn
    FROM cleaned
),

keyed AS (
    SELECT
        -- surrogate trip key: deterministic hash of the natural key
        to_hex(md5(to_utf8(
            CAST(VendorID AS VARCHAR) || '|' ||
            CAST(pickup_ts AS VARCHAR) || '|' ||
            CAST(PULocationID AS VARCHAR) || '|' ||
            CAST(total_amount AS VARCHAR)
        )))                                                    AS trip_key,
        CAST(date_format(pickup_ts, '%Y%m%d') AS INTEGER)      AS date_key,
        hour(pickup_ts)                                        AS time_key,
        PULocationID                                           AS pu_zone_key,
        DOLocationID                                           AS do_zone_key,
        VendorID                                               AS vendor_key,
        payment_type                                           AS payment_key,
        ratecode_id                                            AS ratecode_key,
        trip_distance,
        fare_amount,
        tip_amount,
        tolls_amount,
        total_amount,
        passenger_count,
        date_diff('minute', pickup_ts, dropoff_ts)             AS trip_duration_min,
        -- tip % of fare, guarded against divide-by-zero
        CASE WHEN fare_amount > 0
             THEN ROUND(tip_amount / fare_amount, 4) ELSE NULL END AS tip_pct,
        date_format(pickup_ts, '%Y-%m')                        AS year_month
    FROM deduped
    WHERE rn = 1
)

SELECT
    k.trip_key,
    k.date_key,
    k.time_key,
    k.pu_zone_key,
    k.do_zone_key,
    k.vendor_key,
    k.payment_key,
    k.ratecode_key,
    k.trip_distance,
    k.fare_amount,
    k.tip_amount,
    k.tolls_amount,
    k.total_amount,
    k.passenger_count,
    k.trip_duration_min,
    k.tip_pct,
    z.is_cbd            AS pu_is_cbd,   -- denormalized for fast dashboard/DiD filters
    k.year_month
FROM keyed k
-- referential integrity is enforced by the DQ gate; this join denormalizes
-- the pickup-zone CBD flag so downstream filters need no extra join.
LEFT JOIN nyc_tlc.dim_zone z
       ON k.pu_zone_key = z.zone_key;
