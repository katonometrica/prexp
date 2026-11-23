-- Build a month outside the partitioned table (spec section 4, step 6; P1-07).
-- Run by build_month() on the owner connection that prepared the month's
-- dimensions (step 5): it joins staging to their temporary tables, so the live
-- dimensions are not read and nothing in core changes until the swap.
-- Creating the table, its indexes and VACUUM need ownership. {ym} is the month
-- as YYYYMM, an integer checked before it is put in the text.

-- name: analyze_staging
ANALYZE raw.epd_staging;

-- name: drop_new
DROP TABLE IF EXISTS core.prescribing_{ym}_new;

-- name: create_new
-- A plain table shaped like the parent. The CHECK constraint lets the attach
-- skip its validation scan; NOT NULL on year_month comes from the parent.
CREATE TABLE core.prescribing_{ym}_new (
  LIKE core.prescribing INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
  CONSTRAINT prescribing_{ym}_month CHECK (year_month = {ym})
);

-- name: insert_new
-- One row per practice x presentation: the sums of every source row, exact.
-- An ADQ_USAGE sum of 0 means no ADQ is defined, stored as NULL.
INSERT INTO core.prescribing_{ym}_new (
  year_month, practice_id, presentation_id, items, total_quantity, adq_usage, nic, actual_cost
)
SELECT {ym}, pr.practice_id, p.presentation_id,
       sum(s.items::int4)::int4,
       sum(s.total_quantity::numeric),
       nullif(sum(s.adq_usage::numeric), 0),
       sum(s.nic::numeric),
       sum(s.actual_cost::numeric)
FROM raw.epd_staging s
JOIN pg_temp.month_practice pr ON pr.practice_code = s.practice_code
JOIN pg_temp.month_presentation p ON p.bnf_code = s.bnf_presentation_code
GROUP BY pr.practice_id, p.presentation_id;

-- name: parent_indexes
-- The parent's index definitions, so the new table's indexes match them
-- exactly and are adopted when it is attached, even after a migration changes
-- them.
SELECT c.relname AS name, pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'core.prescribing'::regclass
ORDER BY c.relname;

-- name: vacuum_new
-- Sets the visibility map, so lookups are index-only scans. Cannot run in a
-- transaction.
VACUUM (ANALYZE) core.prescribing_{ym}_new;

-- name: drop_rollups
DROP TABLE IF EXISTS pg_temp.agg_presentation_new, pg_temp.agg_chemical_new,
  pg_temp.agg_practice_new;

-- name: rollup_presentation
-- The month's rollup rows, computed now so the swap only copies them. A fact
-- row is one practice and one presentation, so count(*) counts practices. The
-- region and the chemical are the ones the month's dimensions give the rollups:
-- a newer loaded month's, if there is one (dimensions.sql).
CREATE TEMP TABLE agg_presentation_new AS
SELECT f.year_month, f.presentation_id, pr.rollup_region AS region_code,
       count(*)::int4 AS practices, sum(f.items)::int8 AS items,
       sum(f.total_quantity) AS total_quantity, sum(f.adq_usage) AS adq_usage,
       sum(f.nic) AS nic, sum(f.actual_cost) AS actual_cost
FROM core.prescribing_{ym}_new f
JOIN pg_temp.month_practice pr ON pr.practice_id = f.practice_id
GROUP BY f.year_month, f.presentation_id, pr.rollup_region;

-- name: rollup_chemical
CREATE TEMP TABLE agg_chemical_new AS
SELECT f.year_month, p.rollup_chemical_id AS chemical_id, pr.rollup_region AS region_code,
       count(DISTINCT f.practice_id)::int4 AS practices, sum(f.items)::int8 AS items,
       sum(f.adq_usage) AS adq_usage, sum(f.nic) AS nic, sum(f.actual_cost) AS actual_cost
FROM core.prescribing_{ym}_new f
JOIN pg_temp.month_presentation p ON p.presentation_id = f.presentation_id
JOIN pg_temp.month_practice pr ON pr.practice_id = f.practice_id
GROUP BY f.year_month, p.rollup_chemical_id, pr.rollup_region;

-- name: rollup_practice
CREATE TEMP TABLE agg_practice_new AS
SELECT f.year_month, f.practice_id, count(*)::int4 AS presentations,
       sum(f.items)::int8 AS items, sum(f.nic) AS nic, sum(f.actual_cost) AS actual_cost
FROM core.prescribing_{ym}_new f
GROUP BY f.year_month, f.practice_id;
