-- =====================================================================
-- 00_athena_raw_external.sql
-- Athena external tables over the RAW layer in S3.
-- These read the TLC files in place; nothing is copied or transformed yet.
-- Run these first, then profile (below) before designing the schema.
-- Replace <BUCKET> with your bucket name.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS nyc_tlc;

-- ---------------------------------------------------------------------
-- Raw yellow-taxi trips.
-- Partitioned by trip_month (the YYYY-MM we upload under) so Athena
-- prunes to the months a query needs instead of scanning every file
-- (Athena bills on bytes scanned).
-- Column names follow the TLC yellow data dictionary. Types are widened
-- (BIGINT / DOUBLE) so month-to-month schema drift does not break reads.
-- ---------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS nyc_tlc.raw_yellow_trips (
    VendorID              BIGINT,
    tpep_pickup_datetime  TIMESTAMP,
    tpep_dropoff_datetime TIMESTAMP,
    passenger_count       DOUBLE,
    trip_distance         DOUBLE,
    RatecodeID            DOUBLE,
    store_and_fwd_flag    STRING,
    PULocationID          BIGINT,
    DOLocationID          BIGINT,
    payment_type          BIGINT,
    fare_amount           DOUBLE,
    extra                 DOUBLE,
    mta_tax               DOUBLE,
    tip_amount            DOUBLE,
    tolls_amount          DOUBLE,
    improvement_surcharge DOUBLE,
    total_amount          DOUBLE,
    congestion_surcharge  DOUBLE,   -- pre-2019 per-trip surcharge; NOT the 2025 road toll
    airport_fee           DOUBLE
)
PARTITIONED BY (trip_month STRING)          -- e.g. '2025-01'
STORED AS PARQUET
LOCATION 's3://<BUCKET>/raw/yellow/';

-- Register partitions. Two options:
--   (a) if you laid files out as raw/yellow/trip_month=2025-01/... :
MSCK REPAIR TABLE nyc_tlc.raw_yellow_trips;
--   (b) otherwise add each explicitly, e.g.:
-- ALTER TABLE nyc_tlc.raw_yellow_trips ADD IF NOT EXISTS
--   PARTITION (trip_month='2025-01') LOCATION 's3://<BUCKET>/raw/yellow/trip_month=2025-01/';

-- ---------------------------------------------------------------------
-- Taxi zone lookup (265 zones). LocationID -> Borough, Zone, service_zone.
-- CSV with a header row (skip.header.line.count).
-- ---------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS nyc_tlc.raw_zone_lookup (
    LocationID   INT,
    Borough      STRING,
    Zone         STRING,
    service_zone STRING
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
STORED AS TEXTFILE
LOCATION 's3://<BUCKET>/raw/zone_lookup/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- =====================================================================
-- PROFILING QUERIES (run before designing the schema).
-- These are the numbers that justify the grain and the cleaning rules.
-- =====================================================================

-- Row count per month (sanity: volume roughly stable, no missing month).
SELECT trip_month, COUNT(*) AS trips
FROM nyc_tlc.raw_yellow_trips
GROUP BY trip_month
ORDER BY trip_month;

-- Null / invalid rates on the columns the model depends on.
SELECT
    COUNT(*)                                                          AS total_rows,
    SUM(CASE WHEN tpep_pickup_datetime IS NULL THEN 1 ELSE 0 END)     AS null_pickup_ts,
    SUM(CASE WHEN PULocationID IS NULL THEN 1 ELSE 0 END)             AS null_pu_zone,
    SUM(CASE WHEN trip_distance <= 0 THEN 1 ELSE 0 END)              AS nonpos_distance,
    SUM(CASE WHEN fare_amount < 0 THEN 1 ELSE 0 END)                 AS negative_fare,
    SUM(CASE WHEN tpep_dropoff_datetime < tpep_pickup_datetime
             THEN 1 ELSE 0 END)                                       AS dropoff_before_pickup
FROM nyc_tlc.raw_yellow_trips;

-- Value ranges (spot fat-finger fares / impossible distances).
SELECT
    MIN(trip_distance) AS min_dist, MAX(trip_distance) AS max_dist,
    MIN(fare_amount)   AS min_fare, MAX(fare_amount)   AS max_fare,
    MIN(total_amount)  AS min_total, MAX(total_amount) AS max_total
FROM nyc_tlc.raw_yellow_trips;

-- Cardinality of the would-be dimension keys.
SELECT
    COUNT(DISTINCT PULocationID) AS distinct_pu_zones,
    COUNT(DISTINCT payment_type) AS distinct_payment_types,
    COUNT(DISTINCT VendorID)     AS distinct_vendors,
    COUNT(DISTINCT RatecodeID)   AS distinct_ratecodes
FROM nyc_tlc.raw_yellow_trips;
