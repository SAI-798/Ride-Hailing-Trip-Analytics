-- =====================================================================
-- 02_silver.sql   |   Add to the PIPELINE as a SQL file
-- LAYER : SILVER = cleaned, trusted data.
-- Objects created (in this order):
--   1. trips_labeled          helper VIEW  - every row gets a reject_reason
--   2. silver_trips_clean     good rows, one per trip_id
--   3. silver_trips_rejected  bad rows, WITH the reason (never deleted silently)
--   4. silver_trips_duplicates extra copies of the same trip_id (also kept)
--
-- CLEANING RULES (see README for the "why" of each)
--   IDs (trip_id, customer_id, driver_id) : TRIM only. NEVER INITCAP.
--   Descriptive text (city, zone, region, vehicle, channel, trip type,
--     payment status)                      : INITCAP(TRIM(x)); blank -> 'Unknown'
--   payment_method                         : TRIM only; blank -> 'Unknown'.
--                                            NEVER INITCAP (UPI would become Upi)
--   Numbers and dates                      : TRY_CAST (bad value -> NULL, no crash)
--   Blank fare                             : distance_km x rate_per_km
--   Blank rating / customer_id             : stay NULL (AVG skips NULL)
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. HELPER VIEW: one row per bronze row, typed + cleaned + labelled.
--    reject_reason IS NULL  -> the row is valid
--    copy_number = 1        -> first copy of this trip_id; >1 = duplicate
-- A TEMPORARY view exists only inside the pipeline (it is not a table).
-- ---------------------------------------------------------------
CREATE TEMPORARY VIEW trips_labeled
COMMENT 'Typed and cleaned bronze rows with reject_reason (NULL = valid) and copy_number'
AS
WITH typed AS (
  SELECT
    NULLIF(TRIM(trip_id), '')                                   AS trip_id,
    NULLIF(TRIM(customer_id), '')                               AS customer_id,
    NULLIF(TRIM(driver_id), '')                                 AS driver_id,
    TRY_CAST(TRIM(trip_date) AS DATE)                           AS trip_date,
    TRY_CAST(TRIM(pickup_hour) AS INT)                          AS pickup_hour,
    COALESCE(INITCAP(NULLIF(TRIM(city), '')), 'Unknown')            AS city,
    COALESCE(INITCAP(NULLIF(TRIM(pickup_zone), '')), 'Unknown')     AS pickup_zone,
    COALESCE(INITCAP(NULLIF(TRIM(region), '')), 'Unknown')          AS region,
    COALESCE(INITCAP(NULLIF(TRIM(vehicle_type), '')), 'Unknown')    AS vehicle_type,
    COALESCE(INITCAP(NULLIF(TRIM(booking_channel), '')), 'Unknown') AS booking_channel,
    COALESCE(INITCAP(NULLIF(TRIM(trip_type), '')), 'Unknown')       AS trip_type,
    COALESCE(INITCAP(NULLIF(TRIM(payment_status), '')), 'Unknown')  AS payment_status,
    COALESCE(NULLIF(TRIM(payment_method), ''), 'Unknown')           AS payment_method,  -- no INITCAP!
    TRY_CAST(TRIM(distance_km) AS DECIMAL(10,2))                AS distance_km,
    TRY_CAST(TRIM(duration_min) AS INT)                         AS duration_min,
    TRY_CAST(TRIM(rate_per_km) AS DECIMAL(10,2))                AS rate_per_km,
    TRY_CAST(NULLIF(TRIM(fare_amount), '') AS DECIMAL(12,2))    AS fare_amount_raw,
    COALESCE(TRY_CAST(NULLIF(TRIM(discount_amount), '') AS DECIMAL(12,2)), 0) AS discount_amount,
    TRY_CAST(NULLIF(TRIM(driver_payout), '') AS DECIMAL(12,2))  AS driver_payout,
    TRY_CAST(NULLIF(TRIM(customer_rating), '') AS INT)          AS customer_rating,
    distance_km                                                 AS raw_distance_km,  -- original text, kept for rejected rows
    rate_per_km                                                 AS raw_rate_per_km,
    source_file,
    ingested_at
  FROM bronze_ride_trips
),
filled AS (
  SELECT
    *,
    ROUND(COALESCE(fare_amount_raw, distance_km * rate_per_km), 2) AS fare_amount,
    (fare_amount_raw IS NULL)                                     AS fare_was_filled
  FROM typed
),
labelled AS (
  SELECT
    *,
    -- first matching rule wins; NULL means the row passed every rule
    CASE
      WHEN trip_id IS NULL                                  THEN 'Missing trip_id'
      WHEN trip_date IS NULL                                THEN 'Missing or invalid trip_date'
      WHEN distance_km IS NULL                              THEN 'Missing or non-numeric distance'
      WHEN distance_km <= 0                                 THEN 'Distance is zero or negative'
      WHEN rate_per_km IS NULL                              THEN 'Missing or non-numeric rate per km'
      WHEN rate_per_km < 0                                  THEN 'Rate per km is negative'
      WHEN driver_payout IS NULL                            THEN 'Missing driver payout'
      WHEN pickup_hour IS NULL OR pickup_hour NOT BETWEEN 0 AND 23 THEN 'Pickup hour outside 0-23'
      ELSE NULL
    END AS reject_reason
  FROM filled
)
SELECT
  *,
  -- 1 = the copy we keep. A VALID copy is preferred over an invalid one.
  ROW_NUMBER() OVER (
    PARTITION BY trip_id
    ORDER BY CASE WHEN reject_reason IS NULL THEN 0 ELSE 1 END, source_file, ingested_at
  ) AS copy_number
FROM labelled;


-- ---------------------------------------------------------------
-- 2. CLEAN TABLE: valid rows, exactly one per trip_id.
-- The CONSTRAINTs are SAFETY NETS. They only COUNT violations in the
-- pipeline page (no DROP). If any shows more than 0, the logic is wrong.
-- ---------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW silver_trips_clean
(
  CONSTRAINT trip_id_present EXPECT (trip_id IS NOT NULL),
  CONSTRAINT valid_distance  EXPECT (distance_km > 0),
  CONSTRAINT valid_rate      EXPECT (rate_per_km >= 0),
  CONSTRAINT city_not_blank  EXPECT (city <> '')
)
COMMENT 'Clean ride trips: one row per trip_id, no bad distance or rate'
AS
SELECT
  trip_id, customer_id, driver_id, trip_date, pickup_hour,
  city, pickup_zone, region, vehicle_type, booking_channel, trip_type,
  distance_km, duration_min, rate_per_km,
  fare_amount, fare_was_filled, discount_amount,
  payment_method, payment_status, driver_payout, customer_rating,
  fare_amount - discount_amount                    AS net_revenue,
  fare_amount - discount_amount - driver_payout    AS platform_earnings,
  source_file, ingested_at
FROM trips_labeled
WHERE copy_number = 1
  AND reject_reason IS NULL;


-- ---------------------------------------------------------------
-- 3. REJECTED TABLE: bad rows are KEPT, with the reason and the
--    original text of distance and rate (before TRY_CAST).
-- ---------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW silver_trips_rejected
COMMENT 'Rows that failed a rule, with reject_reason'
AS
SELECT
  trip_id, customer_id, driver_id, trip_date, city, vehicle_type,
  raw_distance_km, raw_rate_per_km, distance_km, rate_per_km,
  reject_reason, source_file, ingested_at
FROM trips_labeled
WHERE copy_number = 1
  AND reject_reason IS NOT NULL;


-- ---------------------------------------------------------------
-- 4. DUPLICATES TABLE: the extra copies we did not keep.
-- ---------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW silver_trips_duplicates
COMMENT 'Extra copies of a trip_id that were removed from the clean table'
AS
SELECT
  trip_id, copy_number, reject_reason, source_file, ingested_at
FROM trips_labeled
WHERE copy_number > 1;
