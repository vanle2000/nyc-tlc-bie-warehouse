-- =====================================================================
-- 02_copy.sql  (Amazon Redshift)
-- Load the curated Parquet from S3 into the star schema.
-- Parquet COPY is columnar and parallel; column mapping is by NAME so
-- column order in the file does not matter.
-- Replace <BUCKET> and <REDSHIFT_COPY_ROLE_ARN> (an IAM role attached to
-- the Redshift namespace with s3:GetObject on the bucket).
-- =====================================================================

-- Dimensions
COPY tlc.dim_zone
FROM 's3://<BUCKET>/curated/dim_zone/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

COPY tlc.dim_date
FROM 's3://<BUCKET>/curated/dim_date/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

COPY tlc.dim_time
FROM 's3://<BUCKET>/curated/dim_time/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

COPY tlc.dim_payment
FROM 's3://<BUCKET>/curated/dim_payment/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

COPY tlc.dim_ratecode
FROM 's3://<BUCKET>/curated/dim_ratecode/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

COPY tlc.dim_vendor
FROM 's3://<BUCKET>/curated/dim_vendor/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

-- Fact (the curated fact is partitioned by year_month in S3; COPY reads
-- all partitions under the prefix. year_month is a partition folder, not a
-- stored column, so it is intentionally not loaded -- date_key covers time.)
COPY tlc.fact_trips
FROM 's3://<BUCKET>/curated/fact_trips/'
IAM_ROLE '<REDSHIFT_COPY_ROLE_ARN>'
FORMAT AS PARQUET;

-- ---------------------------------------------------------------------
-- Post-load hygiene + a load-side reconciliation echo of the DQ gate.
-- ---------------------------------------------------------------------
ANALYZE tlc.fact_trips;

-- Row count per period -- sanity that both pre and post loaded.
SELECT d.period, COUNT(*) AS trips
FROM tlc.fact_trips f
JOIN tlc.dim_date d ON d.date_key = f.date_key
GROUP BY d.period;

-- Referential integrity re-check in Redshift (belt and suspenders).
SELECT COUNT(*) AS orphan_zone_rows
FROM tlc.fact_trips f
LEFT JOIN tlc.dim_zone z ON z.zone_key = f.pu_zone_key
WHERE z.zone_key IS NULL;
