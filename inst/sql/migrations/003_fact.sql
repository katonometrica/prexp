-- 003_fact.sql: the fact table (spec section 3.2).
--
-- One row per month x practice x presentation: the loader sums the source rows,
-- which are per SNOMED product and quantity per item (docs/dataset.md). The
-- measures are exact numeric, so the load check reconciles to the penny.
--
-- Partitioned by range on year_month, one partition per month
-- (core.prescribing_202609), attached by the loader (P1-07). There is no
-- default partition: it would make every attach scan it.
--
-- No foreign keys: attaching a partition would have to check every row.
-- The loader builds the rows from the dimensions, which are never deleted.

CREATE TABLE core.prescribing (
  -- YYYYMM; the source sends the text 'YYYY-MM'
  year_month int4 NOT NULL,
  practice_id int4 NOT NULL,
  presentation_id int4 NOT NULL,
  items int4 NOT NULL,
  -- In the presentation's own unit: never summed across presentations
  total_quantity numeric NOT NULL,
  -- NULL where the presentation has no ADQ (the source writes 0)
  adq_usage numeric,
  -- Pounds
  nic numeric NOT NULL,
  actual_cost numeric NOT NULL
) PARTITION BY RANGE (year_month);

-- Defined on the parent, so a new partition's matching indexes are adopted
-- when it is attached, instead of being built again. Both cover their lookups
-- (index-only scans), which needs the visibility map set by VACUUM, which the
-- loader runs on each new partition.
CREATE INDEX prescribing_presentation_idx ON core.prescribing
  (presentation_id, year_month)
  INCLUDE (practice_id, items, total_quantity, adq_usage, nic, actual_cost);
CREATE INDEX prescribing_practice_idx ON core.prescribing
  (practice_id, year_month)
  INCLUDE (presentation_id, items, adq_usage, nic, actual_cost);
