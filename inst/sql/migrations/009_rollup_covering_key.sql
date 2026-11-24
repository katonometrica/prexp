-- 009_rollup_covering_key.sql: the presentation rollup's primary key carries
-- its measures (P2-05; measured in docs/benchmarks.md).
--
-- A chemical's presentations (drug_presentations) read the rollup rows of
-- every presentation of the chemical over the months: for an appliance group
-- of 2,000 presentations, 70,000 rows, one heap page each. With the measures
-- in the key's index, they are an index-only scan of the rows in key order,
-- three times faster. Index-only scans need the table's visibility map set,
-- which the loader's VACUUM after each swap keeps.
ALTER TABLE core.agg_presentation_month DROP CONSTRAINT agg_presentation_month_pkey;
ALTER TABLE core.agg_presentation_month ADD CONSTRAINT agg_presentation_month_pkey
  PRIMARY KEY (presentation_id, year_month, region_code)
  INCLUDE (practices, items, total_quantity, adq_usage, nic, actual_cost);
