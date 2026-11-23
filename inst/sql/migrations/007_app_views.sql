-- 007_app_views.sql: the views the app reads (spec section 3.3), all but
-- v_variation (v2).
--
-- The app role can use schema app and nothing else. Views run with their
-- owner's privileges, so the app reads core through them without any grant on
-- core. SELECT on each view comes from the default privileges in migration
-- 001, for prexp_app and for prexp_loader, which runs the app's queries in the
-- plan check.

-- The loaded months: the date range, and the cache key. One row, with NULLs and
-- months = 0 before the first load.
CREATE VIEW app.v_window AS
SELECT min(year_month) AS first_month,
       max(year_month) AS last_month,
       count(*)::int4 AS months,
       max(finished_at) AS loaded_at
FROM core.load_log
WHERE status = 'loaded';

CREATE VIEW app.v_chemical AS
SELECT chemical_id, chemical_code, chemical_name, first_seen, last_seen
FROM core.dim_chemical;

CREATE VIEW app.v_presentation AS
SELECT p.presentation_id, p.bnf_code, p.bnf_description,
       p.chemical_id, c.chemical_code, c.chemical_name,
       p.bnf_chapter, p.bnf_chapter_name, p.bnf_section, p.bnf_paragraph,
       p.is_generic, p.first_seen, p.last_seen
FROM core.dim_presentation p
JOIN core.dim_chemical c ON c.chemical_id = p.chemical_id;

CREATE VIEW app.v_practice AS
SELECT practice_id, practice_code, practice_name, address, postcode,
       icb_code, icb_name, region_code, region_name, is_unidentified,
       first_seen, last_seen
FROM core.dim_practice;

-- Region names for the rollups' region_code: from the most recently seen
-- practice in each region.
CREATE VIEW app.v_region AS
SELECT DISTINCT ON (region_code) region_code, region_name
FROM core.dim_practice
WHERE region_code IS NOT NULL
ORDER BY region_code, last_seen DESC, practice_id;

CREATE VIEW app.v_presentation_month AS
SELECT a.year_month, a.presentation_id, a.region_code,
       p.bnf_code, p.bnf_description, p.chemical_id, p.is_generic,
       a.practices, a.items, a.total_quantity, a.adq_usage, a.nic, a.actual_cost
FROM core.agg_presentation_month a
JOIN core.dim_presentation p ON p.presentation_id = a.presentation_id;

CREATE VIEW app.v_chemical_month AS
SELECT a.year_month, a.chemical_id, a.region_code,
       c.chemical_code, c.chemical_name,
       a.practices, a.items, a.adq_usage, a.nic, a.actual_cost
FROM core.agg_chemical_month a
JOIN core.dim_chemical c ON c.chemical_id = a.chemical_id;

CREATE VIEW app.v_practice_month AS
SELECT year_month, practice_id, presentations, items, nic, actual_cost
FROM core.agg_practice_month;

-- A practice's prescribing by presentation. A query that leaves out
-- total_quantity can use the practice index alone (index-only scan).
CREATE VIEW app.v_practice_presentation AS
SELECT f.year_month, f.practice_id, f.presentation_id,
       p.bnf_code, p.bnf_description, p.chemical_id, p.is_generic,
       f.items, f.total_quantity, f.adq_usage, f.nic, f.actual_cost
FROM core.prescribing f
JOIN core.dim_presentation p ON p.presentation_id = f.presentation_id;
