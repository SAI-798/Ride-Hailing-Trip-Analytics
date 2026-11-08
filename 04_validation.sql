-- =====================================================================
-- 04_validation.sql   |   Run in: SQL Editor, AFTER the pipeline finished
-- WHAT : proves the pipeline did what it should.
-- WHY  : "it ran without errors" is not the same as "the numbers are
--        right". These checks catch silent mistakes.
-- HOW  : Part A = one table of PASS/FAIL checks (run this first).
--        Part B = detail queries to investigate when something FAILs.
-- NOTE : the expected numbers (1214, 1168, 22, 24) are for the file
--        ride_trips_raw.csv from this project. A different file will
--        have different numbers; then compare to your own profile.
-- =====================================================================

-- ---------------- PART A: all checks in one result ----------------
SELECT check_name, actual, expected,
       CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
  -- row counts
  SELECT '01 bronze rows loaded' AS check_name,
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.bronze_ride_trips) AS DOUBLE) AS actual, 1214.0 AS expected
  UNION ALL SELECT '02 silver clean rows',     CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean) AS DOUBLE), 1168.0
  UNION ALL SELECT '03 silver rejected rows',  CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_rejected) AS DOUBLE), 22.0
  UNION ALL SELECT '04 duplicate rows (independent count from bronze)',
         CAST((SELECT COUNT(*) - COUNT(DISTINCT TRIM(trip_id)) FROM mobility_catalog.trips.bronze_ride_trips) AS DOUBLE), 24.0
  UNION ALL SELECT '05 duplicates table matches independent count',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_duplicates) AS DOUBLE),
         CAST((SELECT COUNT(*) - COUNT(DISTINCT TRIM(trip_id)) FROM mobility_catalog.trips.bronze_ride_trips) AS DOUBLE)
  UNION ALL SELECT '06 reconciliation difference (bronze - clean - rejected - duplicates)',
         CAST((SELECT reconciliation_diff FROM mobility_catalog.trips.gold_data_quality) AS DOUBLE), 0.0
  UNION ALL SELECT '07 gold_data_quality says reconciliation passed (1 = Yes)',
         CAST((SELECT CASE WHEN reconciliation_passed = 'Yes' THEN 1 ELSE 0 END FROM mobility_catalog.trips.gold_data_quality) AS DOUBLE), 1.0

  -- silver clean: no duplicates, spaces, blanks, bad values
  UNION ALL SELECT '10 duplicate trip_id in clean',
         CAST((SELECT COUNT(*) - COUNT(DISTINCT trip_id) FROM mobility_catalog.trips.silver_trips_clean) AS DOUBLE), 0.0
  UNION ALL SELECT '11 text columns with extra spaces in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean
               WHERE city <> TRIM(city) OR region <> TRIM(region) OR vehicle_type <> TRIM(vehicle_type)
                  OR booking_channel <> TRIM(booking_channel) OR payment_method <> TRIM(payment_method)
                  OR trip_id <> TRIM(trip_id)) AS DOUBLE), 0.0
  UNION ALL SELECT '12 text columns with wrong capitals in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean
               WHERE city <> INITCAP(city) OR region <> INITCAP(region)
                  OR vehicle_type <> INITCAP(vehicle_type) OR booking_channel <> INITCAP(booking_channel)) AS DOUBLE), 0.0
  UNION ALL SELECT '13 blank or NULL city in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean WHERE city IS NULL OR city = '') AS DOUBLE), 0.0
  UNION ALL SELECT '14 blank or NULL payment_method in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean WHERE payment_method IS NULL OR payment_method = '') AS DOUBLE), 0.0
  UNION ALL SELECT '15 payment_method outside UPI/Cash/Card/Wallet/Unknown (catches Upi)',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean
               WHERE payment_method NOT IN ('UPI','Cash','Card','Wallet','Unknown')) AS DOUBLE), 0.0
  UNION ALL SELECT '16 distance <= 0 or NULL in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean WHERE distance_km IS NULL OR distance_km <= 0) AS DOUBLE), 0.0
  UNION ALL SELECT '17 rate < 0 or NULL in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean WHERE rate_per_km IS NULL OR rate_per_km < 0) AS DOUBLE), 0.0
  UNION ALL SELECT '18 NULL fare in clean',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean WHERE fare_amount IS NULL) AS DOUBLE), 0.0
  UNION ALL SELECT '19 fare differs from distance x rate by more than 1 rupee',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean
               WHERE ABS(fare_amount - distance_km * rate_per_km) > 1) AS DOUBLE), 0.0
  UNION ALL SELECT '20 rating outside 1-5 (NULL is allowed)',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean
               WHERE customer_rating IS NOT NULL AND customer_rating NOT BETWEEN 1 AND 5) AS DOUBLE), 0.0
  UNION ALL SELECT '21 blank ratings were NOT turned into 0',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_clean WHERE customer_rating = 0) AS DOUBLE), 0.0
  UNION ALL SELECT '22 rejected rows without a reason',
         CAST((SELECT COUNT(*) FROM mobility_catalog.trips.silver_trips_rejected WHERE reject_reason IS NULL) AS DOUBLE), 0.0

  -- gold totals must equal silver totals
  UNION ALL SELECT '30 gold_monthly trips minus silver clean rows',
         CAST((SELECT SUM(trips) FROM mobility_catalog.trips.gold_monthly_trips)
            - (SELECT COUNT(*)  FROM mobility_catalog.trips.silver_trips_clean) AS DOUBLE), 0.0
  UNION ALL SELECT '31 gold_city trips minus silver clean rows',
         CAST((SELECT SUM(trips) FROM mobility_catalog.trips.gold_city_summary)
            - (SELECT COUNT(*)  FROM mobility_catalog.trips.silver_trips_clean) AS DOUBLE), 0.0
  UNION ALL SELECT '32 gold_vehicle trips minus silver clean rows',
         CAST((SELECT SUM(trips) FROM mobility_catalog.trips.gold_vehicle_summary)
            - (SELECT COUNT(*)  FROM mobility_catalog.trips.silver_trips_clean) AS DOUBLE), 0.0
  UNION ALL SELECT '33 gold_payment trips minus silver clean rows',
         CAST((SELECT SUM(trips) FROM mobility_catalog.trips.gold_payment_summary)
            - (SELECT COUNT(*)  FROM mobility_catalog.trips.silver_trips_clean) AS DOUBLE), 0.0
  UNION ALL SELECT '34 gold_monthly net revenue minus silver (rounded to 2 dp)',
         CAST(ROUND((SELECT SUM(net_revenue) FROM mobility_catalog.trips.gold_monthly_trips)
                  - (SELECT SUM(net_revenue) FROM mobility_catalog.trips.silver_trips_clean), 2) AS DOUBLE), 0.0
  UNION ALL SELECT '35 gold_city net revenue minus silver (rounded to 2 dp)',
         CAST(ROUND((SELECT SUM(net_revenue) FROM mobility_catalog.trips.gold_city_summary)
                  - (SELECT SUM(net_revenue) FROM mobility_catalog.trips.silver_trips_clean), 2) AS DOUBLE), 0.0
  UNION ALL SELECT '36 gold_vehicle net revenue minus silver (rounded to 2 dp)',
         CAST(ROUND((SELECT SUM(net_revenue) FROM mobility_catalog.trips.gold_vehicle_summary)
                  - (SELECT SUM(net_revenue) FROM mobility_catalog.trips.silver_trips_clean), 2) AS DOUBLE), 0.0
  UNION ALL SELECT '37 gold_payment net revenue minus silver (rounded to 2 dp)',
         CAST(ROUND((SELECT SUM(net_revenue) FROM mobility_catalog.trips.gold_payment_summary)
                  - (SELECT SUM(net_revenue) FROM mobility_catalog.trips.silver_trips_clean), 2) AS DOUBLE), 0.0
  UNION ALL SELECT '38 platform earnings = net revenue - driver payout (gold monthly)',
         CAST(ROUND((SELECT SUM(platform_earnings) FROM mobility_catalog.trips.gold_monthly_trips)
                  - ((SELECT SUM(net_revenue) FROM mobility_catalog.trips.gold_monthly_trips)
                   - (SELECT SUM(driver_payout) FROM mobility_catalog.trips.gold_monthly_trips)), 2) AS DOUBLE), 0.0
)
ORDER BY check_name;
-- EXPECTED: every row says PASS.


-- ---------------- PART B: detail queries (run when a check fails) ----------------

-- B1. Layer counts side by side
SELECT 'bronze' AS layer, COUNT(*) AS row_count FROM mobility_catalog.trips.bronze_ride_trips
UNION ALL SELECT 'silver_clean',      COUNT(*) FROM mobility_catalog.trips.silver_trips_clean
UNION ALL SELECT 'silver_rejected',   COUNT(*) FROM mobility_catalog.trips.silver_trips_rejected
UNION ALL SELECT 'silver_duplicates', COUNT(*) FROM mobility_catalog.trips.silver_trips_duplicates;

-- B2. Which trip_ids appear more than once in bronze?
SELECT TRIM(trip_id) AS trip_id, COUNT(*) AS copies
FROM mobility_catalog.trips.bronze_ride_trips
GROUP BY TRIM(trip_id)
HAVING COUNT(*) > 1
ORDER BY copies DESC, trip_id;

-- B3. Every distinct value in the cleaned text columns (look for near-duplicates)
SELECT 'city' AS col, city AS value, COUNT(*) AS n FROM mobility_catalog.trips.silver_trips_clean GROUP BY city
UNION ALL SELECT 'vehicle_type',    vehicle_type,    COUNT(*) FROM mobility_catalog.trips.silver_trips_clean GROUP BY vehicle_type
UNION ALL SELECT 'booking_channel', booking_channel, COUNT(*) FROM mobility_catalog.trips.silver_trips_clean GROUP BY booking_channel
UNION ALL SELECT 'payment_method',  payment_method,  COUNT(*) FROM mobility_catalog.trips.silver_trips_clean GROUP BY payment_method
ORDER BY col, value;
-- EXPECTED: 8 cities + Unknown, 5 vehicle types, 3 channels, UPI/Cash/Card/Wallet/Unknown.

-- B4. Rejected rows and their reasons
SELECT reject_reason, COUNT(*) AS rows_rejected
FROM mobility_catalog.trips.silver_trips_rejected
GROUP BY reject_reason;
-- EXPECTED: Distance is zero or negative = 13, Rate per km is negative = 9.

SELECT * FROM mobility_catalog.trips.silver_trips_rejected ORDER BY reject_reason, trip_id;

-- B5. Rows where the fare was blank and we calculated it
SELECT COUNT(*) AS fares_filled FROM mobility_catalog.trips.silver_trips_clean WHERE fare_was_filled;

-- B6. Reconciliation row exactly as the dashboard reads it
SELECT * FROM mobility_catalog.trips.gold_data_quality;
