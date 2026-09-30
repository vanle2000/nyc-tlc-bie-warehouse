# NYC Taxi Warehouse & Congestion-Pricing Impact Analysis

An end-to-end business intelligence pipeline on NYC Taxi & Limousine Commission (TLC)
trip data: raw Parquet in S3, profiled and modeled with Amazon Athena into a star
schema, quality-gated, loaded into Amazon Redshift, served through an Amazon QuickSight
dashboard, and extended with a causal analysis of the January 2025 congestion-pricing
policy.

> **Stack:** Amazon S3 · Amazon Athena · Amazon Redshift (Serverless) · Amazon QuickSight · SQL · Python (boto3)
> **Region:** `us-east-1`

---

## The business framing

A transportation-operations stakeholder wants a single, trusted place to answer
recurring questions about taxi demand, revenue, and driver efficiency, and one
strategic question: **did the January 2025 congestion-pricing toll change taxi
behavior in the tolled zone?**

The requirements I gathered:

1. **One reliable source of truth** for trip metrics that non-analysts can self-serve
   (not a spreadsheet re-pulled by hand each month).
2. **Metrics that answer business questions** — revenue, trip volume, tip behavior,
   and driver efficiency — sliceable by zone, time of day, and payment type.
3. **Trustworthy numbers** — data-quality controls so a wrong figure never reaches
   the dashboard.
4. **A decision on the policy shock** — a defensible estimate of the congestion-pricing
   effect, not just a before/after chart.

This repo delivers all four.

---

## Architecture

```
                 ┌──────────────────────────────────────────────────────────┐
 (1) INGEST      │  TLC public Parquet  ──►  s3://<bucket>/raw/               │
                 │  yellow_tripdata_YYYY-MM.parquet  (Jan 2024 – Mar 2025)    │
                 │  + taxi_zone_lookup.csv                                    │
                 └──────────────────────────────────────────────────────────┘
                                        │
 (2) PROFILE     │  Athena external tables over raw/  ──► row counts, null %, │
                 │  value ranges, cardinality  ──► informs the schema design  │
                                        │
 (3) MODEL       │  Star schema (grain = one completed trip):                 │
                 │  fact_trips + dim_date, dim_time, dim_zone,                │
                 │  dim_vendor, dim_payment, dim_ratecode                     │
                                        │
 (4) TRANSFORM   │  Athena CTAS builds conformed dims + fact as Parquet       │
                 │  in s3://<bucket>/curated/   (SQL-first ETL, not pandas)   │
                                        │
 (5) DQ GATE     │  Validation queries run BEFORE load and FAIL LOUD:         │
                 │   • fact rows reconcile to raw counts (within tolerance)   │
                 │   • no orphan zone / vendor / payment IDs (anti-join)      │
                 │   • fares, distances, timestamps in plausible range        │
                 │   • no duplicate trip keys                                 │
                 │   • schema-drift check vs expected column set              │
                                        │
 (6) LOAD        │  s3://<bucket>/curated/  ──COPY──►  Amazon Redshift        │
                 │  distkey / sortkey chosen and justified                    │
                                        │
 (7) SERVE       │  Amazon QuickSight dashboard on Redshift                   │
                 │  KPIs, trends, zone map, time-of-day heatmap               │
                                        │
 (8) ANALYZE     │  Difference-in-differences on the congestion-pricing shock │
                 │  (parallel-trends + placebo tests) + zone×hour             │
                 │  revenue-efficiency segmentation  ──► BUSINESS_QUESTIONS.md│
                 └────────────────────────────────────────────────────────────┘
```

Steps **5** (quality gate) and **6** (distribution/sort-key choices) are what make
this a warehouse an operations team can trust, rather than a one-off load. Step **8**
turns the warehouse into a decision.

---

## Repository layout

```
nyc-tlc-bie-warehouse/
├── README.md                     # this file — doubles as the walkthrough script
├── BUSINESS_QUESTIONS.md         # questions answered + recommendations + limitations
├── requirements.txt
├── config.example.yaml           # bucket, region, workgroup, Redshift settings
├── sql/
│   ├── 00_athena_raw_external.sql    # external tables over raw Parquet + zone CSV
│   ├── 01_star_schema_design.md      # grain, facts, dimensions, and why
│   ├── 02_ctas_dimensions.sql        # conformed dims via CTAS
│   ├── 03_ctas_fact_trips.sql        # fact table via CTAS (joins + dedup + derived)
│   └── 04_cbd_zone_reference.sql     # derive the ≤60th-St treated-zone set from lookup
├── dq/
│   ├── dq_checks.sql                 # all quality-gate assertions (one query each)
│   └── README.md                     # what each check protects against
├── redshift/
│   ├── 01_ddl.sql                    # tables with DISTKEY / SORTKEY + justification
│   └── 02_copy.sql                   # COPY from S3 curated Parquet
├── analysis/
│   ├── did_congestion_pricing.sql    # DiD group means, computed in SQL
│   ├── parallel_trends.sql           # pre-period trend by month (assumption check)
│   ├── placebo_test.sql              # fake cutoff falsification test
│   ├── zone_hour_segmentation.sql    # revenue-per-hour efficiency segments
│   └── analysis.ipynb                # runs the SQL above + DiD regression + charts + findings
└── orchestration/
    └── run_pipeline.ipynb            # boto3: ingest → CTAS → DQ → COPY
```

---

## Data

- **Source:** [NYC TLC Trip Record Data](https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page) (public domain).
- **Files:** yellow-taxi monthly Parquet, `yellow_tripdata_YYYY-MM.parquet`, from
  `https://d37ci6vzurychx.cloudfront.net/trip-data/`.
- **Zone lookup:** `https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv`
  (`LocationID, Borough, Zone, service_zone`, 265 zones).
- **Window:** **January 2024 – March 2025** — 12 pre-treatment months (for a credible
  parallel-trends check) and 3 post-treatment months around the Jan 5, 2025 policy start.
- **Scale:** tens of millions of trips; queried as partitioned Parquet to keep scans
  (and cost) small.

> Note: TLC trip-record schemas drift slightly across years. The DQ gate includes an
> explicit schema-drift check for exactly this reason.

---

## The policy shock (for the causal analysis)

- **Congestion pricing began January 5, 2025** ([MTA CBDTP](https://www.mta.info/project/CBDTP)).
- **Treated area:** the Congestion Relief Zone — Manhattan **at or below 60th Street**.
- **Treatment definition here:** trips whose **pickup zone** falls in the ≤60th-St set
  (derived from the zone lookup in `sql/04_cbd_zone_reference.sql`, not hard-coded).
- **Outcomes analyzed:** trip volume, trip distance, and tip rate — *behavioral*
  outcomes. The 2025 road toll is paid by the vehicle and is **not** the pre-existing
  per-trip `congestion_surcharge` fare field (which dates to 2019); the analysis does
  **not** treat that field as the toll. See `BUSINESS_QUESTIONS.md` for the full list
  of assumptions and limitations.

---

## Setup & run

```bash
pip install -r requirements.txt
cp config.example.yaml config.yaml          # fill in your bucket + Redshift details
# then run the notebook top to bottom:
jupyter notebook orchestration/run_pipeline.ipynb
```

The notebook: downloads the TLC files → uploads to `s3://<bucket>/raw/` → creates
Athena external tables → runs the CTAS ETL → runs the DQ gate (**stops if any check
fails**) → issues the Redshift `COPY`. QuickSight is then pointed at Redshift (steps
in `redshift/README` and the notebook's final cell).

### Cost & teardown (do this — it prevents a surprise bill)

| Service | Cost control |
|---|---|
| S3 | Pennies for this data; delete the bucket when done. |
| Athena | Bills on bytes scanned — query partitioned Parquet, avoid `SELECT *`. |
| Redshift Serverless | Free-trial credit; **pause or delete the workgroup after screenshots.** |
| QuickSight | 30-day Author trial, then ~$24/mo; **cancel the subscription after capturing the dashboard.** |

A teardown checklist is in the final notebook cell.

---

## What this project demonstrates

| Capability | Where |
|---|---|
| SQL depth (windows, CTEs, anti-joins) | `sql/`, `dq/`, `analysis/` |
| Dimensional / star-schema data modeling | `sql/01_star_schema_design.md`, `sql/02`, `sql/03` |
| ETL on large, multi-file data | `sql/` CTAS + `orchestration/` |
| Data warehousing on Redshift + query optimization | `redshift/01_ddl.sql` (distkey/sortkey) |
| Data integrity / accuracy / reliability | `dq/` |
| Metrics, reporting, self-serve BI | QuickSight dashboard + `BUSINESS_QUESTIONS.md` |
| Analytical problem solving + business recommendation | `analysis/`, `BUSINESS_QUESTIONS.md` |

---

*Data © NYC TLC, used under its public terms. This is an independent portfolio
analysis and is not affiliated with the NYC TLC or the MTA.*
