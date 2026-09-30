-- =====================================================================
-- 02_ctas_dimensions.sql
-- Build conformed dimensions as Parquet in the CURATED layer via CTAS.
-- Athena CTAS = SQL-first ETL: the transform IS the query, output lands
-- in S3 ready for the Redshift COPY. Replace <BUCKET>.
-- Run AFTER 04_cbd_zone_reference.sql (dim_zone depends on cbd_zone_ref).
-- =====================================================================

-- ---------------------------------------------------------------------
-- dim_zone : conformed, role-played for pickup and dropoff.
-- Carries is_cbd so "the tolled zone" has ONE definition shared by the
-- dashboard and the causal analysis.
-- ---------------------------------------------------------------------
CREATE TABLE nyc_tlc.dim_zone
WITH (format='PARQUET', external_location='s3://<BUCKET>/curated/dim_zone/') AS
SELECT
    location_id                        AS zone_key,   -- natural = surrogate here (stable IDs)
    location_id,
    borough,
    zone,
    service_zone,
    is_cbd
FROM nyc_tlc.cbd_zone_ref;

-- ---------------------------------------------------------------------
-- dim_payment
-- ---------------------------------------------------------------------
CREATE TABLE nyc_tlc.dim_payment
WITH (format='PARQUET', external_location='s3://<BUCKET>/curated/dim_payment/') AS
SELECT payment_key, payment_desc FROM (
    VALUES
        (1, 'Credit card'), (2, 'Cash'), (3, 'No charge'),
        (4, 'Dispute'),     (5, 'Unknown'), (6, 'Voided trip')
) AS t(payment_key, payment_desc);

-- ---------------------------------------------------------------------
-- dim_ratecode
-- ---------------------------------------------------------------------
CREATE TABLE nyc_tlc.dim_ratecode
WITH (format='PARQUET', external_location='s3://<BUCKET>/curated/dim_ratecode/') AS
SELECT ratecode_key, ratecode_desc FROM (
    VALUES
        (1, 'Standard rate'), (2, 'JFK'), (3, 'Newark'),
        (4, 'Nassau/Westchester'), (5, 'Negotiated fare'), (6, 'Group ride'),
        (99, 'Unknown')
) AS t(ratecode_key, ratecode_desc);

-- ---------------------------------------------------------------------
-- dim_vendor
-- ---------------------------------------------------------------------
CREATE TABLE nyc_tlc.dim_vendor
WITH (format='PARQUET', external_location='s3://<BUCKET>/curated/dim_vendor/') AS
SELECT vendor_key, vendor_desc FROM (
    VALUES
        (1, 'Creative Mobile Technologies'),
        (2, 'VeriFone Inc.'),
        (6, 'Myle Technologies'),
        (7, 'Helix')
) AS t(vendor_key, vendor_desc);

-- ---------------------------------------------------------------------
-- dim_date : one row per calendar date in the window.
-- Carries `period` (pre/post the 2025-01-05 policy) so before/after is
-- defined once. generate a date spine, then decorate.
-- ---------------------------------------------------------------------
CREATE TABLE nyc_tlc.dim_date
WITH (format='PARQUET', external_location='s3://<BUCKET>/curated/dim_date/') AS
WITH spine AS (
    SELECT CAST(d AS DATE) AS date
    FROM UNNEST(
        sequence(DATE '2024-01-01', DATE '2025-03-31', INTERVAL '1' DAY)
    ) AS t(d)
)
SELECT
    CAST(date_format(date, '%Y%m%d') AS INTEGER)              AS date_key,
    date,
    year(date)                                               AS year,
    month(date)                                              AS month,
    day_of_week(date)                                        AS dow,        -- 1=Mon..7=Sun
    date_format(date, '%Y-%m')                               AS year_month,
    CASE WHEN day_of_week(date) IN (6,7) THEN 1 ELSE 0 END   AS is_weekend,
    CASE WHEN date >= DATE '2025-01-05' THEN 'post' ELSE 'pre' END AS period
FROM spine;

-- ---------------------------------------------------------------------
-- dim_time : one row per hour of day (grain of the fact = hour).
-- ---------------------------------------------------------------------
CREATE TABLE nyc_tlc.dim_time
WITH (format='PARQUET', external_location='s3://<BUCKET>/curated/dim_time/') AS
SELECT
    h AS time_key,
    h AS hour,
    CASE
        WHEN h BETWEEN 6  AND 9  THEN 'AM peak'
        WHEN h BETWEEN 10 AND 15 THEN 'Midday'
        WHEN h BETWEEN 16 AND 19 THEN 'PM peak'
        WHEN h BETWEEN 20 AND 23 THEN 'Evening'
        ELSE 'Overnight'
    END AS daypart
FROM UNNEST(sequence(0, 23)) AS t(h);
