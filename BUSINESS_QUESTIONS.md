# Business questions answered

This is the deliverable a stakeholder actually reads: the questions, the answer with a
number, a recommendation, and — critically — where each answer breaks. Fill the
`<>` placeholders from your own run; the queries that produce each number are named.

> Discipline note: every figure below must come from the pipeline output. Do not
> quote a number here you have not produced and cannot reproduce. "We did not measure
> X" is an acceptable answer; an invented number is not.

---

## Q1. Which zone × time segments are the most revenue-efficient, and how concentrated is that value?

**Why the stakeholder asks:** to steer driver supply toward the highest revenue-per-time
segments instead of spreading it evenly.

**Query:** `analysis/zone_hour_segmentation.sql`

**Answer (fill from your run):**
- Top segment by revenue-per-minute: **`<zone>` during `<daypart>`**, at `$<x>/min`.
- The **top efficiency decile of segments carries `<pct>%` of total revenue** from
  `<n>` of `<total>` segments — revenue is/ isn't highly concentrated.

**Recommendation:** `<e.g. concentrate incentive spend on the top-decile zone×daypart
segments; the bottom decile returns <x>/min and is a candidate for reduced positioning.>`

**Where it breaks:** revenue-per-minute rewards short high-fare trips; it ignores
deadhead (empty) time between fares, which this dataset does not capture. Treat it as a
relative ranking, not an absolute earnings figure.

---

## Q2. Did the January 2025 congestion-pricing toll change taxi trip volume in the tolled zone?

**Why the stakeholder asks:** to understand demand impact of the policy on the CBD.

**Design:** difference-in-differences. Treated = trips with pickup in the Congestion
Relief Zone (Manhattan ≤ 60th St); control = pickups elsewhere. Pre = Jan–Dec 2024,
post = Jan 5 – Mar 2025.

**Queries:** `analysis/did_congestion_pricing.sql` (2×2 point estimate);
`analysis/analysis.ipynb` runs the DiD regression (estimate + 95% CI + p-value).

**Assumption check first (this gates whether Q2 is answerable):**
- Parallel trends: `analysis/parallel_trends.sql` + the pre-check in the regression.
  Result: `<parallel / not parallel — treated:time p = <p>>`.
- Placebo (fake July-2024 cutoff): `analysis/placebo_test.sql`. Result:
  `<placebo DiD = <x>, near zero / not near zero>`.

**Answer (fill from your run):**
- DiD estimate on trip volume: **`<x>` trips per zone-day** (`<pct>%` of the treated
  pre-period level), 95% CI `[<lo>, <hi>]`, p = `<p>`.
- Direction: CBD pickups `<fell / rose / did not measurably change>` relative to control
  after the toll.

**Recommendation:** `<e.g. plan for a <pct>% shift in CBD taxi demand; revisit driver
positioning at the zone boundary where trips may re-originate just outside the toll.>`

**Where it breaks (state these plainly):**
1. **Causal only if parallel trends hold.** If the pre-check flags divergence, report
   this as an association, not a causal effect.
2. **The toll is not a fare field.** The 2025 road toll is paid by the vehicle; it is
   **not** the pre-2019 per-trip `congestion_surcharge` column. The analysis measures
   behavioral change (volume, distance, tips), not a fare line item.
3. **Coincident shocks.** Any other CBD-specific event around Jan 2025 (weather,
   unrelated policy) would contaminate the estimate. Note known events.
4. **Yellow taxi only.** Findings do not generalize to for-hire/rideshare, which have
   different toll pass-through.
5. **Boundary definition.** The treated-zone set is a documented analyst call
   (`sql/04_cbd_zone_reference.sql`); results should be checked for sensitivity to
   borderline zones.

---

## Q3. Did rider tipping or trip distance change in the tolled zone after the policy?

**Query:** `analysis/did_congestion_pricing.sql` (Outcomes B and C).

**Answer (fill from your run):**
- DiD on avg trip distance: `<x>` miles.
- DiD on avg tip % (card-paid trips): `<x>` percentage points.

**Recommendation / read:** `<what the secondary outcomes suggest about who kept taking
CBD taxis after the toll.>`

**Where it breaks:** tip % is only meaningful for card-paid trips (cash tips are
unrecorded), so the tip analysis is filtered to `payment_type = 1` and describes card
riders only.

---

## Summary for a non-technical reader

`<Three sentences: what changed, how confident we are, and the one action you would
take. This is the part a director reads; keep it plain and quantified.>`
