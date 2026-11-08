-- =====================================================================
-- 00_setup.sql   |   Run in: SQL Editor (NOT inside the pipeline)
-- WHAT : creates the storage places, then lets you preview the CSV.
-- WHY  : the pipeline reads from a Unity Catalog Volume (a folder in
--        Databricks), so the folder must exist before the pipeline runs.
-- Run the statements one at a time (select a statement, press Run).
-- =====================================================================

-- STEP 1: catalog -> schema -> volume (think: drive -> folder -> sub-folder)
CREATE CATALOG IF NOT EXISTS mobility_catalog;
CREATE SCHEMA  IF NOT EXISTS mobility_catalog.trips;
CREATE VOLUME  IF NOT EXISTS mobility_catalog.trips.raw_files;

-- If CREATE CATALOG fails on Databricks Free Edition (see "Common errors"
-- in docs/databricks_guide.md), use the built-in catalog instead:
--   CREATE SCHEMA IF NOT EXISTS workspace.trips;
--   CREATE VOLUME IF NOT EXISTS workspace.trips.raw_files;
-- and replace "mobility_catalog" with "workspace" in every file.

-- STEP 2: upload ride_trips_raw.csv by clicking (no SQL):
--   Catalog (left menu) > mobility_catalog > trips > raw_files > Upload to this volume

-- STEP 3: confirm the file is there
LIST '/Volumes/mobility_catalog/trips/raw_files/';

-- STEP 4: preview 10 rows, exactly as stored in the file.
-- Look for: spaces around city names, MIXED capitals, blank cells.
SELECT *
FROM read_files(
  '/Volumes/mobility_catalog/trips/raw_files/',
  format => 'csv',
  header => true
)
LIMIT 10;

-- STEP 5: count the rows. EXPECTED: 1214
SELECT COUNT(*) AS rows_in_file
FROM read_files(
  '/Volumes/mobility_catalog/trips/raw_files/',
  format => 'csv',
  header => true
);
