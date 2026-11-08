-- =====================================================================
-- dashboard_queries.sql
-- One DATASET per query. In the dashboard: Data tab > Create from SQL.
-- Name each dataset EXACTLY as the "-- DATASET:" label.
-- Rule: the dashboard reads ONLY gold_* tables (never bronze or silver).
-- Change "mobility_catalog" if you used another catalog (e.g. workspace).
-- =====================================================================

-- ============ PAGE 1: OVERVIEW ============

-- DATASET: ds_kpi          (4 counter cards)
SELECT
  SUM(trips)             AS total_trips,
  SUM(net_revenue)       AS net_revenue,
  SUM(total_km)          AS total_km,
  SUM(platform_earnings) AS platform_earnings
FROM mobility_catalog.trips.gold_monthly_trips;

-- DATASET: ds_monthly      (line chart)
SELECT trip_month, trips, net_revenue, platform_earnings
FROM mobility_catalog.trips.gold_monthly_trips
ORDER BY trip_month;

-- DATASET: ds_city         (bar chart + region filter)
SELECT region, city, trips, net_revenue, avg_fare_per_trip
FROM mobility_catalog.trips.gold_city_summary;


-- ============ PAGE 2: PRODUCTS AND PAYMENTS ============

-- DATASET: ds_vehicle      (trips/revenue bars + rating bars)
SELECT vehicle_type, trips, total_km, net_revenue, avg_rating, rated_trips
FROM mobility_catalog.trips.gold_vehicle_summary;

-- DATASET: ds_payment      (bar chart by payment method)
SELECT payment_method,
       SUM(trips)          AS trips,
       SUM(net_revenue)    AS net_revenue,
       SUM(pending_amount) AS pending_amount
FROM mobility_catalog.trips.gold_payment_summary
GROUP BY payment_method;

-- DATASET: ds_channel      (bar chart by booking channel)
SELECT booking_channel,
       SUM(trips)       AS trips,
       SUM(net_revenue) AS net_revenue
FROM mobility_catalog.trips.gold_payment_summary
GROUP BY booking_channel;

-- DATASET: ds_pending      (counter card)
SELECT SUM(pending_amount) AS pending_amount,
       SUM(pending_trips)  AS pending_trips
FROM mobility_catalog.trips.gold_payment_summary;


-- ============ PAGE 3: DATA QUALITY ============

-- DATASET: ds_dq           (cards)
SELECT bronze_rows, clean_rows, rejected_rows, duplicate_rows,
       reconciliation_diff, reconciliation_passed
FROM mobility_catalog.trips.gold_data_quality;

-- DATASET: ds_issues       (bar chart + table)
SELECT issue, rows_affected, action_taken
FROM mobility_catalog.trips.gold_data_issues
ORDER BY rows_affected DESC;
