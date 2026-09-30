# Star-schema design

Designed **after** profiling the raw data (see the profiling queries in
`00_athena_raw_external.sql`), not before. The profiling step sets the grain and the
cleaning rules below.

## Grain

**One row = one completed yellow-taxi trip.**

Records excluded from the fact table (and counted, so the exclusion is auditable — see
the DQ gate):

- `trip_distance <= 0` (not a real trip)
- `tpep_dropoff_datetime < tpep_pickup_datetime` (impossible time order)
- `fare_amount < 0` (refund/adjustment rows, not trips)
- pickup timestamp outside the loaded window (stray records; TLC files occasionally
  contain a few rows dated to other months)

Every exclusion rule is a `WHERE` clause in `03_ctas_fact_trips.sql` and a counted
check in `dq/dq_checks.sql`, so "how many rows did you drop and why" has an answer.

## Schema

```
                         ┌───────────────┐
                         │   dim_date    │
                         │ date_key (PK) │
                         │ date, year,   │
                         │ month, dow,   │
                         │ is_weekend,   │
                         │ period (pre/  │
                         │  post policy) │
                         └──────┬────────┘
                                │
   ┌───────────────┐      ┌─────┴─────────────────────────────┐      ┌───────────────┐
   │   dim_time    │      │            fact_trips             │      │   dim_zone    │
   │ time_key (PK) │──────┤ trip_key (PK, surrogate)          ├──────│ zone_key (PK) │
   │ hour, minute, │      │ date_key   (FK) -> dim_date       │      │ location_id   │
   │ daypart       │      │ time_key   (FK) -> dim_time       │      │ borough, zone │
   └───────────────┘      │ pu_zone_key(FK) -> dim_zone       │      │ service_zone  │
                          │ do_zone_key(FK) -> dim_zone       │      │ is_cbd (<=60St)│
   ┌───────────────┐      │ vendor_key (FK) -> dim_vendor     │      └───────────────┘
   │  dim_payment  │──────┤ payment_key(FK) -> dim_payment    │
   │ payment_key   │      │ ratecode_key(FK)-> dim_ratecode   │      ┌───────────────┐
   │ payment_desc  │      │                                   ├──────│ dim_ratecode  │
   └───────────────┘      │ MEASURES:                         │      │ ratecode_key  │
                          │  trip_distance, fare_amount,      │      │ ratecode_desc │
   ┌───────────────┐      │  tip_amount, tolls_amount,        │      └───────────────┘
   │  dim_vendor   │──────┤  total_amount, passenger_count,   │
   │ vendor_key    │      │  trip_duration_min (derived),     │
   │ vendor_desc   │      │  tip_pct (derived)                │
   └───────────────┘      └───────────────────────────────────┘
```

## Why these choices

- **Conformed `dim_zone` used twice** (pickup + dropoff) via two FKs — standard
  role-playing dimension. `is_cbd` (pickup zone at/below 60th St) lives here so the
  causal analysis and the dashboard share one definition of "the tolled zone."
- **`dim_date` carries `period`** (pre / post the 2025-01-05 cutoff) so the DiD and
  every dashboard filter agree on the same before/after split — one definition, not
  one per query.
- **Derived measures** (`trip_duration_min`, `tip_pct`) are computed once in the ETL
  and stored, so reporting and analysis never recompute them inconsistently.
- **Surrogate `trip_key`** = a hash of the natural key (vendor + pickup ts + pickup
  zone + total) so the DQ gate can test for duplicate trips deterministically.

## Decode tables (from the TLC data dictionary)

- `payment_type`: 1 Credit card, 2 Cash, 3 No charge, 4 Dispute, 5 Unknown, 6 Voided.
- `RatecodeID`: 1 Standard, 2 JFK, 3 Newark, 4 Nassau/Westchester, 5 Negotiated, 6 Group.
- `VendorID`: 1 Creative Mobile, 2 VeriFone (7 also appears in some months).
