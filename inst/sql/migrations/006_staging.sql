-- 006_staging.sql: the staging table for one monthly file (spec section 3.2).
--
-- Every column is text, in the source's order, named as the source header in
-- lower case (inst/extdata/epd_columns.csv). The loader streams the CSV in
-- with COPY, truncating first, and converts types when it builds the month.
-- No key: the source has duplicate rows, and every row is summed.
--
-- Unlogged, because it is rebuilt from the file on every load. Autovacuum is
-- off: the table is truncated after each load, and an automatic vacuum of a
-- freshly staged month would only compete with the build. The loader runs
-- ANALYZE itself before the build.

CREATE UNLOGGED TABLE raw.epd_staging (
  year_month text,
  regional_office_name text,
  regional_office_code text,
  icb_name text,
  icb_code text,
  pco_name text,
  pco_code text,
  practice_name text,
  practice_code text,
  address_1 text,
  address_2 text,
  address_3 text,
  address_4 text,
  postcode text,
  bnf_chemical_substance_code text,
  bnf_chemical_substance text,
  bnf_presentation_code text,
  bnf_presentation_name text,
  bnf_chapter_plus_code text,
  quantity text,
  items text,
  total_quantity text,
  adq_usage text,
  nic text,
  actual_cost text,
  unidentified text,
  snomed_code text
) WITH (autovacuum_enabled = false);
