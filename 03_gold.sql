-- =====================================================================
-- 03_gold.sql   |   Add to the PIPELINE as a SQL file
-- LAYER : GOLD = small summary tables that answer business questions.
-- RULE  : Gold reads ONLY clean data (silver_trips_clean), except the
--         data-quality tables, which must look at Bronze on purpose.
-- Money formulas (already computed in silver_trips_clean):
--   net_revenue       = fare_amount - discount_amount
--   platform_earnings = net_revenue - driver_payout
-- =====================================================================

-- BR-01  Monthly trends ------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW gold_monthly_trips
COMMENT 'Trips, km, revenue, payout and platform earnings per month'
AS
SELECT
  DATE_TRUNC('MONTH', trip_date)        AS trip_month,
  COUNT(*)                              AS trips,
  ROUND(SUM(distance_km), 2)            AS total_km,
  ROUND(SUM(net_revenue), 2)            AS net_revenue,
  ROUND(SUM(driver_payout), 2)          AS driver_payout,
  ROUND(SUM(platform_earnings), 2)      AS platform_earnings
FROM silver_trips_clean
GROUP BY DATE_TRUNC('MONTH', trip_date);

-- BR-02  Region and city ----------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW gold_city_summary
COMMENT 'Trips, revenue and average fare per region and city'
AS
SELECT
  region,
  city,
  COUNT(*)                              AS trips,
  ROUND(SUM(net_revenue), 2)            AS net_revenue,
  ROUND(AVG(net_revenue), 2)            AS avg_fare_per_trip,
  ROUND(AVG(customer_rating), 2)        AS avg_rating
FROM silver_trips_clean
GROUP BY region, city;

-- BR-03  Product performance (vehicle type) ----------------------------
CREATE OR REFRESH MATERIALIZED VIEW gold_vehicle_summary
COMMENT 'Trips, km, revenue and average rating per vehicle type'
AS
SELECT
  vehicle_type,
  COUNT(*)                              AS trips,
  ROUND(SUM(distance_km), 2)            AS total_km,
  ROUND(SUM(net_revenue), 2)            AS net_revenue,
  ROUND(AVG(customer_rating), 2)        AS avg_rating,      -- AVG skips blank ratings
  COUNT(customer_rating)                AS rated_trips      -- how many ratings the average uses
FROM silver_trips_clean
GROUP BY vehicle_type;

-- BR-04  Payment method and booking channel ----------------------------
CREATE OR REFRESH MATERIALIZED VIEW gold_payment_summary
COMMENT 'Trips, revenue and pending amount per payment method and booking channel'
AS
SELECT
  payment_method,
  booking_channel,
  COUNT(*)                                                                    AS trips,
  ROUND(SUM(net_revenue), 2)                                                  AS net_revenue,
  SUM(CASE WHEN payment_status = 'Pending' THEN 1 ELSE 0 END)                 AS pending_trips,
  ROUND(SUM(CASE WHEN payment_status = 'Pending' THEN net_revenue ELSE 0 END), 2) AS pending_amount
FROM silver_trips_clean
GROUP BY payment_method, booking_channel;

-- BR-05 / BR-06  Data quality + reconciliation -------------------------
-- IMPORTANT: duplicate_rows is counted straight from BRONZE with
--   COUNT(*) - COUNT(DISTINCT trip_id).
-- clean_rows and rejected_rows come from the ROW_NUMBER logic in Silver.
-- Two different methods, so the check can really FAIL if Silver has a bug.
CREATE OR REFRESH MATERIALIZED VIEW gold_data_quality
COMMENT 'One row: problem counts on raw data and the reconciliation check'
AS
WITH raw_counts AS (
  SELECT
    COUNT(*)                                   AS bronze_rows,
    COUNT(DISTINCT TRIM(trip_id))              AS distinct_trip_ids,
    SUM(CASE WHEN TRY_CAST(TRIM(distance_km) AS DECIMAL(10,2)) <= 0 THEN 1 ELSE 0 END) AS invalid_distance_rows,
    SUM(CASE WHEN TRY_CAST(TRIM(rate_per_km) AS DECIMAL(10,2)) < 0  THEN 1 ELSE 0 END) AS negative_rate_rows,
    SUM(CASE WHEN NULLIF(TRIM(city), '')           IS NULL THEN 1 ELSE 0 END) AS missing_city_rows,
    SUM(CASE WHEN NULLIF(TRIM(payment_method), '') IS NULL THEN 1 ELSE 0 END) AS missing_payment_rows,
    SUM(CASE WHEN NULLIF(TRIM(fare_amount), '')    IS NULL THEN 1 ELSE 0 END) AS missing_fare_rows,
    SUM(CASE WHEN NULLIF(TRIM(customer_rating), '') IS NULL THEN 1 ELSE 0 END) AS missing_rating_rows,
    SUM(CASE WHEN NULLIF(TRIM(customer_id), '')    IS NULL THEN 1 ELSE 0 END) AS missing_customer_rows,
    SUM(CASE WHEN city            <> INITCAP(TRIM(city))
               OR vehicle_type    <> INITCAP(TRIM(vehicle_type))
               OR booking_channel <> INITCAP(TRIM(booking_channel))
             THEN 1 ELSE 0 END)                                                  AS messy_text_rows
  FROM bronze_ride_trips
),
silver_counts AS (
  SELECT
    (SELECT COUNT(*) FROM silver_trips_clean)      AS clean_rows,
    (SELECT COUNT(*) FROM silver_trips_rejected)   AS rejected_rows,
    (SELECT COUNT(*) FROM silver_trips_duplicates) AS duplicates_removed_rows
)
SELECT
  r.bronze_rows,
  r.bronze_rows - r.distinct_trip_ids                      AS duplicate_rows,   -- independent count
  s.clean_rows,
  s.rejected_rows,
  s.duplicates_removed_rows,
  r.bronze_rows - (s.clean_rows + s.rejected_rows + (r.bronze_rows - r.distinct_trip_ids)) AS reconciliation_diff,
  CASE
    WHEN r.bronze_rows = s.clean_rows + s.rejected_rows + (r.bronze_rows - r.distinct_trip_ids)
     AND s.duplicates_removed_rows = r.bronze_rows - r.distinct_trip_ids THEN 'Yes'
    ELSE 'No'
  END                                                      AS reconciliation_passed,
  r.invalid_distance_rows, r.negative_rate_rows,
  r.missing_city_rows, r.missing_payment_rows, r.missing_fare_rows,
  r.missing_rating_rows, r.missing_customer_rows, r.messy_text_rows
FROM raw_counts r
CROSS JOIN silver_counts s;

-- BR-05  One row per problem: easy to chart ----------------------------
-- Counts are on RAW bronze rows (before de-duplication).
CREATE OR REFRESH MATERIALIZED VIEW gold_data_issues
COMMENT 'One row per data problem: how many rows, and what we did about it'
AS
SELECT 'Duplicate trips (same trip_id)' AS issue, duplicate_rows        AS rows_affected, 'Extra copy removed, kept in silver_trips_duplicates' AS action_taken FROM gold_data_quality
UNION ALL SELECT 'Zero or negative distance', invalid_distance_rows, 'Rejected, kept in silver_trips_rejected'  FROM gold_data_quality
UNION ALL SELECT 'Negative rate per km',      negative_rate_rows,    'Rejected, kept in silver_trips_rejected'  FROM gold_data_quality
UNION ALL SELECT 'Messy text (spaces / capitals)', messy_text_rows,  'Fixed with TRIM + INITCAP'               FROM gold_data_quality
UNION ALL SELECT 'Blank city',                missing_city_rows,     'Filled with Unknown'                      FROM gold_data_quality
UNION ALL SELECT 'Blank payment method',      missing_payment_rows,  'Filled with Unknown'                      FROM gold_data_quality
UNION ALL SELECT 'Blank fare amount',         missing_fare_rows,     'Calculated as distance x rate'            FROM gold_data_quality
UNION ALL SELECT 'Blank customer rating',     missing_rating_rows,   'Kept as NULL (AVG skips it)'              FROM gold_data_quality
UNION ALL SELECT 'Blank customer_id',         missing_customer_rows, 'Kept as NULL'                             FROM gold_data_quality;
