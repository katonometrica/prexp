-- Make a built month live (spec section 4, step 8; P1-07). Run by
-- swap_month() on the owner connection that prepared and built the month (the
-- month's dimensions and rollup rows are in its temporary tables), in one
-- transaction. {ym} is the month as YYYYMM and {next} the month after it,
-- integers.
--
-- Order matters for the app. The dimensions (dimensions.sql) and the rollup
-- rows are written first: they take no lock that the app's reads wait for. The
-- detach locks the parent table until the commit, so it comes last, followed
-- only by quick renames, the attach and the load log. While the detach waits
-- for that lock, new app queries queue behind it, so each wait is kept short
-- (lock_timeout 1 s, well under the app's 5 s statement timeout) and retried
-- after a pause that lets the queued queries run.

-- name: delete_presentation
DELETE FROM core.agg_presentation_month WHERE year_month = {ym};

-- name: insert_presentation
INSERT INTO core.agg_presentation_month (
  year_month, presentation_id, region_code, practices, items,
  total_quantity, adq_usage, nic, actual_cost
)
SELECT year_month, presentation_id, region_code, practices, items,
       total_quantity, adq_usage, nic, actual_cost
FROM pg_temp.agg_presentation_new;

-- name: delete_chemical
DELETE FROM core.agg_chemical_month WHERE year_month = {ym};

-- name: insert_chemical
INSERT INTO core.agg_chemical_month (
  year_month, chemical_id, region_code, practices, items, adq_usage, nic, actual_cost
)
SELECT year_month, chemical_id, region_code, practices, items, adq_usage, nic, actual_cost
FROM pg_temp.agg_chemical_new;

-- name: delete_practice
DELETE FROM core.agg_practice_month WHERE year_month = {ym};

-- name: insert_practice
INSERT INTO core.agg_practice_month (
  year_month, practice_id, presentations, items, nic, actual_cost
)
SELECT year_month, practice_id, presentations, items, nic, actual_cost
FROM pg_temp.agg_practice_new;

-- name: live_partition
-- The month's current table, if any, and whether it is attached.
SELECT EXISTS (
         SELECT 1 FROM pg_inherits
         WHERE inhrelid = to_regclass('core.prescribing_{ym}')
           AND inhparent = 'core.prescribing'::regclass
       ) AS attached,
       to_regclass('core.prescribing_{ym}') IS NOT NULL AS exists;

-- name: detach
ALTER TABLE core.prescribing DETACH PARTITION core.prescribing_{ym};

-- name: drop_old
DROP TABLE core.prescribing_{ym};

-- name: rename_new
ALTER TABLE core.prescribing_{ym}_new RENAME TO prescribing_{ym};

-- name: attach
-- Instant: the CHECK constraint proves every row belongs, and the indexes
-- match the parent's, so they are adopted rather than built.
ALTER TABLE core.prescribing ATTACH PARTITION core.prescribing_{ym}
  FOR VALUES FROM ({ym}) TO ({next});

-- name: replace_log
UPDATE core.load_log SET status = 'replaced'
WHERE year_month = {ym} AND status = 'loaded';

-- name: loaded_log
UPDATE core.load_log
SET status = 'loaded', source_rows = $2, loaded_rows = $3, file_bytes = $4,
    finished_at = now(), error = NULL
WHERE load_id = $1;
