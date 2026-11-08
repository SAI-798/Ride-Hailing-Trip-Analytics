-- =====================================================================
-- 01_bronze.sql   |   Add to the PIPELINE as a SQL file
-- LAYER : BRONZE = the raw file, kept exactly as it arrived.
-- WHAT  : a streaming table that reads the CSV and adds 2 audit columns.
-- WHY   : you can always go back to the original data. Nothing is cleaned
--         or deleted here, so every later number can be traced to a row.
-- HOW   : every column is read as STRING on purpose. Typing happens in
--         Silver with TRY_CAST, so one bad value (like "abc" in distance)
--         can never crash the load or disappear silently.
-- Pipeline default catalog = mobility_catalog, default schema = trips,
-- so table names below need no prefix.
-- =====================================================================

CREATE OR REFRESH STREAMING TABLE bronze_ride_trips
COMMENT 'Raw ride trips CSV, all columns as text, plus source_file and ingested_at'
AS
SELECT
  *,
  _metadata.file_name   AS source_file,    -- which file the row came from
  current_timestamp()   AS ingested_at     -- when the pipeline loaded it
FROM STREAM read_files(
  '/Volumes/mobility_catalog/trips/raw_files/',
  format => 'csv',
  header => true,
  schema => 'trip_id STRING, customer_id STRING, driver_id STRING, trip_date STRING, pickup_hour STRING, city STRING, pickup_zone STRING, region STRING, vehicle_type STRING, booking_channel STRING, distance_km STRING, duration_min STRING, rate_per_km STRING, fare_amount STRING, discount_amount STRING, payment_method STRING, payment_status STRING, driver_payout STRING, customer_rating STRING, trip_type STRING'
);
