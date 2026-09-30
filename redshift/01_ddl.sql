-- =====================================================================
-- 01_ddl.sql  (Amazon Redshift, Serverless, us-east-1)
-- Star schema in Redshift. The DISTKEY / SORTKEY choices are the
-- "query optimization" decisions; each is justified inline because in an
-- interview the follow-up is always "why that key?"
--
-- Guiding facts about how this warehouse is queried:
--   * Almost every dashboard query and the DiD FILTER ON A DATE RANGE.
--   * The heaviest join is fact -> dim_zone (pickup zone: map, CBD flag).
--   * The dimensions are tiny (<= 265 rows); the fact is tens of millions.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS tlc;

-- ---------------------------------------------------------------------
-- Dimensions.
-- Tiny tables -> DISTSTYLE ALL replicates a full copy to every node, so
-- the fact->dim join is local (no data movement) on every slice.
-- ---------------------------------------------------------------------
CREATE TABLE tlc.dim_zone (
    zone_key      INTEGER      NOT NULL,
    location_id   INTEGER      NOT NULL,
    borough       VARCHAR(40),
    zone          VARCHAR(80),
    service_zone  VARCHAR(40),
    is_cbd        SMALLINT     NOT NULL,
    PRIMARY KEY (zone_key)
) DISTSTYLE ALL SORTKEY (zone_key);

CREATE TABLE tlc.dim_date (
    date_key    INTEGER     NOT NULL,
    date        DATE        NOT NULL,
    year        SMALLINT,
    month       SMALLINT,
    dow         SMALLINT,
    year_month  VARCHAR(7),
    is_weekend  SMALLINT,
    period      VARCHAR(4),          -- 'pre' / 'post' the 2025-01-05 policy
    PRIMARY KEY (date_key)
) DISTSTYLE ALL SORTKEY (date_key);

CREATE TABLE tlc.dim_time (
    time_key SMALLINT NOT NULL,
    hour     SMALLINT,
    daypart  VARCHAR(12),
    PRIMARY KEY (time_key)
) DISTSTYLE ALL SORTKEY (time_key);

CREATE TABLE tlc.dim_payment (
    payment_key  SMALLINT NOT NULL,
    payment_desc VARCHAR(20),
    PRIMARY KEY (payment_key)
) DISTSTYLE ALL;

CREATE TABLE tlc.dim_ratecode (
    ratecode_key  SMALLINT NOT NULL,
    ratecode_desc VARCHAR(30),
    PRIMARY KEY (ratecode_key)
) DISTSTYLE ALL;

CREATE TABLE tlc.dim_vendor (
    vendor_key  SMALLINT NOT NULL,
    vendor_desc VARCHAR(40),
    PRIMARY KEY (vendor_key)
) DISTSTYLE ALL;

-- ---------------------------------------------------------------------
-- Fact.
--   DISTKEY (pu_zone_key):
--     Distributing the fact by pickup zone co-locates rows that share a
--     pickup zone. The zone dimension is DISTSTYLE ALL, so the biggest
--     join is local either way; distributing on pu_zone_key ALSO makes
--     the common "group by pickup zone" aggregations (dashboard map,
--     zone x hour segmentation, treated-vs-control DiD grouping) shuffle
--     less. 265 zones give reasonable, if not perfect, slice balance.
--     Alternative considered: DISTSTYLE KEY on date_key -- rejected
--     because time-range filtering is already handled by the SORTKEY, and
--     zone is the busier GROUP BY / join column.
--
--   SORTKEY (date_key, pu_zone_key):
--     Every dashboard query and the DiD filter a date range, so a leading
--     date_key sortkey lets Redshift zone-map prune whole blocks outside
--     the range (the single biggest scan reduction here). pu_zone_key
--     second clusters each day's rows by zone for the group-bys.
-- ---------------------------------------------------------------------
CREATE TABLE tlc.fact_trips (
    trip_key          VARCHAR(32) NOT NULL,
    date_key          INTEGER     NOT NULL,
    time_key          SMALLINT    NOT NULL,
    pu_zone_key       INTEGER     NOT NULL,
    do_zone_key       INTEGER     NOT NULL,
    vendor_key        SMALLINT,
    payment_key       SMALLINT,
    ratecode_key      SMALLINT,
    trip_distance     DECIMAL(10,2),
    fare_amount       DECIMAL(10,2),
    tip_amount        DECIMAL(10,2),
    tolls_amount      DECIMAL(10,2),
    total_amount      DECIMAL(10,2),
    passenger_count   SMALLINT,
    trip_duration_min INTEGER,
    tip_pct           DECIMAL(6,4),
    pu_is_cbd         SMALLINT
)
DISTSTYLE KEY
DISTKEY (pu_zone_key)
COMPOUND SORTKEY (date_key, pu_zone_key);
