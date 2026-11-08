# 🚖 Ride-Hailing Trip Analytics: Medallion Pipeline on Databricks


A beginner-friendly data engineering project. A messy monthly cab-trips CSV goes through
**Bronze → Silver → Gold** tables built with **Lakeflow Spark Declarative Pipelines (SQL)**,
is proven correct with a **reconciliation check**, and is shown in a **3-page AI/BI dashboard**.

> **Dataset:** `data/ride_trips_raw.csv` is **synthetic** (made up): 1,214 rows, 20 columns, cab trips in 2025.
> No real customer data.

---

## 📑 Table of Contents
- [Architecture](#-architecture)
- [Tech Stack](#-tech-stack)
- [Repo Contents](#-repo-contents)
- [How to Run](#-how-to-run)
- [Cleaning Rules and Why](#-cleaning-rules-and-why)
- [Reconciliation](#-reconciliation-proof-that-no-row-was-lost)
- [Validation Checks](#-validation-checks)
- [Dashboard](#-dashboard)
- [Results](#-results)
- [Known Limitations](#-known-limitations)
- [What I Learned](#-what-i-learned)

---

## 🏗 Architecture

```
 ride_trips_raw.csv
        |  (upload)
        v
 Unity Catalog Volume  /Volumes/mobility_catalog/trips/raw_files/
        |
        v
 BRONZE  bronze_ride_trips            raw text + source_file + ingested_at     1,214 rows
        |
        v   helper view: trips_labeled (typed, cleaned, reject_reason, copy_number)
        |
        +--> SILVER  silver_trips_clean       valid, one row per trip_id         1,168 rows
        +--> SILVER  silver_trips_rejected    bad rows + reason (kept!)             22 rows
        +--> SILVER  silver_trips_duplicates  extra copies (kept!)                  24 rows
        |
        v   (Gold reads ONLY silver_trips_clean ...)
 GOLD  gold_monthly_trips | gold_city_summary | gold_vehicle_summary | gold_payment_summary
        |
 GOLD  gold_data_quality + gold_data_issues   (... except these two, which also read Bronze)
        |
        v
 DASHBOARD (AI/BI)  Page 1 Overview | Page 2 Products & Payments | Page 3 Data Quality
```

| Layer | Purpose | Objects |
|---|---|---|
| **Bronze** | Raw file kept exactly as it arrived (all columns as `STRING`) | `bronze_ride_trips` (streaming table) |
| **Silver** | Cleaned, typed, trusted data. Bad rows are kept, never deleted silently | `silver_trips_clean`, `silver_trips_rejected`, `silver_trips_duplicates` |
| **Gold** | Small summary tables that answer business questions | `gold_monthly_trips`, `gold_city_summary`, `gold_vehicle_summary`, `gold_payment_summary`, `gold_data_quality`, `gold_data_issues` |

---

## 🧰 Tech Stack
- **Databricks** (Free Edition works)
- **Lakeflow Spark Declarative Pipelines** (SQL): streaming tables and materialized views
- **Unity Catalog** (catalog → schema → volume)
- **Databricks AI/BI Dashboards**
- **DuckDB** (optional local test of the same SQL logic)

---

## 📂 Repo Contents

| Path | What it is |
|---|---|
| `sql/00_setup.sql` | Run in SQL Editor: catalog, schema, volume, CSV preview |
| `sql/01_bronze.sql` | Pipeline file: raw streaming table |
| `sql/02_silver.sql` | Pipeline file: labelled view, clean, rejected, duplicates |
| `sql/03_gold.sql` | Pipeline file: 4 business tables + data-quality tables |
| `sql/04_validation.sql` | Run after the pipeline: 29 PASS/FAIL checks + detail queries |
| `dashboard/` | Dataset queries (`dashboard_queries.sql`) and exact widget settings |
| `docs/` | Click-by-click guide, interview questions, LinkedIn draft |
| `tests/local_duckdb_check.py` | Optional: runs the same SQL logic locally in DuckDB |

---

## ▶️ How to Run

> Full click-by-click guide: [`docs/databricks_guide.md`](docs/databricks_guide.md)

1. **Setup:** run `sql/00_setup.sql` in the SQL Editor (one statement at a time), then upload the CSV into the volume:
   `Catalog > mobility_catalog > trips > raw_files > Upload to this volume`.
2. **Pipeline:** create an **ETL pipeline** with default catalog `mobility_catalog` and default schema `trips`. Add `01_bronze.sql`, `02_silver.sql`, `03_gold.sql` as pipeline files and click **Run pipeline**.
3. **Validate:** run `sql/04_validation.sql` Part A. Every row must say `PASS`.
4. **Dashboard:** create one dataset per query in `dashboard/dashboard_queries.sql`, then build the 3 pages from `dashboard/dashboard_guide.md`.

> 💡 **Free Edition tip:** if `CREATE CATALOG` fails, use the built-in `workspace` catalog instead and replace `mobility_catalog` with `workspace` in every file.

---

## 🧹 Cleaning Rules and Why

| Problem found | Rows | Rule | Why |
|---|---|---|---|
| Same `trip_id` twice | 24 | Keep one copy (`ROW_NUMBER` per `trip_id`); extra copies go to `silver_trips_duplicates` | Duplicates inflate trips and revenue. `trip_id` is unique per trip; `customer_id`/`driver_id` are not |
| Spaces and mixed capitals in city, vehicle, channel | 155 | `INITCAP(TRIM(x))` | "  mumbai", "MUMBAI", "Mumbai" must group as one city |
| IDs and `payment_method` | n/a | `TRIM` only, **never `INITCAP`** | `INITCAP` would turn `UPI` into `Upi` and could corrupt IDs |
| Blank city | 12 | `'Unknown'` | Keep the trip's revenue in totals instead of losing it; make the gap visible |
| Blank payment method | 14 | `'Unknown'` | Same reason |
| Blank fare | 18 (16 after clean-up) | `distance_km × rate_per_km`, flagged in `fare_was_filled` | Fare is defined by that formula; all non-blank fares in this file match it within 1 rupee |
| Blank rating | 27 (25 in clean) | Stay `NULL` | `AVG` skips `NULL`. A `0` would drag every average down |
| Blank `customer_id` | 9 | Stay `NULL` | Not needed for any report; an invented ID would be false |
| Distance ≤ 0 | 13 | Reject, keep with reason | A trip cannot have zero or negative distance |
| Rate per km < 0 | 9 | Reject, keep with reason | A negative price makes revenue wrong |
| Text that is not a number/date | 0 today | `TRY_CAST` gives `NULL`, then rejected with a reason | One bad value must not crash the load or vanish |

**Never delete silently:** every row that leaves the clean table is saved in
`silver_trips_rejected` (with `reject_reason`) or `silver_trips_duplicates`.

**Money formulas** (computed in `silver_trips_clean`):
```
net_revenue       = fare_amount - discount_amount
platform_earnings = net_revenue - driver_payout
```

---

## ✅ Reconciliation: Proof That No Row Was Lost

```
bronze_rows (1,214)  =  clean_rows (1,168)  +  rejected_rows (22)  +  duplicate_rows (24)
```

- `clean_rows` and `rejected_rows` come from the **`ROW_NUMBER` logic in Silver**.
- `duplicate_rows` comes from a **different method on Bronze**: `COUNT(*) - COUNT(DISTINCT trip_id)`.

Because the numbers come from two independent methods, the check can **fail**.
I tested that: I deliberately broke the de-duplication rule locally and the check turned to
`No` with a difference of -24. If `duplicate_rows` were computed as `bronze - clean - rejected`,
the check would pass no matter what, which would be a fake test.

The result is stored in `gold_data_quality` (`reconciliation_diff`, `reconciliation_passed`) and shown on dashboard page 3.

---

## 🔍 Validation Checks

`sql/04_validation.sql` **Part A** runs 29 checks in one result table. Expected: every row says `PASS`.

| Group | Checks | Examples |
|---|---|---|
| Row counts and reconciliation | 01–07 | Bronze = 1,214, clean = 1,168, rejected = 22, reconciliation difference = 0 |
| Silver quality | 10–22 | No duplicate `trip_id`, no extra spaces, `payment_method` only UPI/Cash/Card/Wallet/Unknown, no rating of 0 |
| Gold vs Silver totals | 30–38 | Trips and net revenue in every gold table equal silver; platform earnings = net revenue − driver payout |

**Part B** has detail queries to investigate when a check fails (layer counts, duplicate IDs, distinct values, rejected rows and reasons).

> The expected numbers (1214, 1168, 22, 24) are for `ride_trips_raw.csv` from this project. A different file will give different numbers.

---

## 📊 Dashboard

The dashboard reads **only `gold_*` tables** (never Bronze or Silver).

| Page | Content | Datasets |
|---|---|---|
| **1. Overview** | KPI cards (trips, net revenue, km, platform earnings), monthly trend, city bars with region filter | `ds_kpi`, `ds_monthly`, `ds_city` |
| **2. Products & Payments** | Vehicle type revenue and rating, payment method, booking channel, pending amount | `ds_vehicle`, `ds_payment`, `ds_channel`, `ds_pending` |
| **3. Data Quality** | Bronze/clean/rejected/duplicate counts, reconciliation status, issues chart and table | `ds_dq`, `ds_issues` |

---

## 📈 Results

Expected values for this file:

| Metric | Value |
|---|---|
| Clean trips | 1,168 |
| Net revenue | ₹237,150.58 |
| Distance | 15,769.1 km |
| Platform earnings | ₹52,639.56 |
| Pending amount | ₹18,746.19 |
| Highest-revenue vehicle | Mini (₹68,193.19) |
| Best-rated vehicle | Auto (4.10) |
| Highest-revenue city | Bengaluru (₹43,393.63) |

---

## ⚠️ Known Limitations

- Rows with a blank `trip_id` would each be rejected, but extra blanks would be counted as duplicates. There are none in this file.
- `Unknown` city appears under 3 regions because region is not blank for those trips.
- `driver_payout` is trusted as given; there is no rule checking it against fare.
- Batch learning project: no alerting, no incremental business logic, no SCD.
- Re-uploading a file with the same name is not re-read by the streaming table; use **Full refresh**.


---

## 🎓 What I Learned

- Layers make data trustworthy step by step.
- `TRY_CAST` plus a reject table beats crashing or deleting.
- A check is only worth something if it can fail.

---

## 📄 License
Educational project using synthetic data. Add a license of your choice (e.g. MIT) before sharing.
