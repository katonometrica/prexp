-- The month's dimensions (spec section 4, steps 5 and 8; P1-06). Run on the
-- owner connection that builds and swaps the month: the temporary tables live in
-- its session. {ym} is the month as YYYYMM, an integer checked before it is put
-- in the text.
--
-- Step 5, prepare_dimensions(), changes nothing in core: it works out the
-- month's chemicals, presentations and practices from staging, with their ids
-- (existing ones, or new ones taken from the identity sequences, whose values
-- are never rolled back, so a failed load only leaves a gap). The build joins
-- staging to these tables. Step 8, apply_dimensions(), writes them to core
-- inside the swap transaction, so the app sees a month's new codes and names
-- only together with its data, and a failed load leaves core as it was.
--
-- Within a month a practice's attributes depend only on its code, and a
-- presentation's only on its code (docs/dataset.md), so min() just picks the
-- one value. The source writes empty values as '', loaded as NULL. first_seen
-- and last_seen widen to include the month. Names, ICB and region are replaced
-- only by a month at least as recent as last_seen, so reloading an old month
-- never brings back old details; the month's rollups use the same rule.

-- name: drop_month_tables
DROP TABLE IF EXISTS pg_temp.month_chemical, pg_temp.month_presentation, pg_temp.month_practice;

-- name: month_chemical
CREATE TEMP TABLE month_chemical AS
SELECT s.chemical_code, s.chemical_name, d.chemical_id, d.chemical_id IS NULL AS is_new
FROM (
  SELECT bnf_chemical_substance_code AS chemical_code,
         nullif(min(bnf_chemical_substance), '') AS chemical_name
  FROM raw.epd_staging
  GROUP BY bnf_chemical_substance_code
) s
LEFT JOIN core.dim_chemical d ON d.chemical_code = s.chemical_code;

-- name: new_chemical_ids
UPDATE pg_temp.month_chemical
SET chemical_id = nextval(pg_get_serial_sequence('core.dim_chemical', 'chemical_id'))
WHERE is_new;

-- name: month_presentation
-- Chapter, section and paragraph come from the code ('05', '0501', '050101');
-- the chapter name from BNF_CHAPTER_PLUS_CODE ('05: Infections'). Characters 10
-- and 11 are AA for a generic; appliance chapters 20 to 23 do not follow that
-- rule, so is_generic is NULL for them. rollup_chemical_id is the chemical the
-- month's rollups count the presentation under: a newer month's, if one is
-- loaded.
CREATE TEMP TABLE month_presentation AS
SELECT s.bnf_code, s.bnf_description, c.chemical_id,
       left(s.bnf_code, 2) AS bnf_chapter, s.bnf_chapter_name,
       left(s.bnf_code, 4) AS bnf_section, left(s.bnf_code, 6) AS bnf_paragraph,
       CASE WHEN left(s.bnf_code, 2) BETWEEN '20' AND '23' THEN NULL
            ELSE substr(s.bnf_code, 10, 2) = 'AA' END AS is_generic,
       d.presentation_id, d.presentation_id IS NULL AS is_new,
       CASE WHEN d.last_seen > {ym} THEN d.chemical_id ELSE c.chemical_id END AS rollup_chemical_id
FROM (
  SELECT bnf_presentation_code AS bnf_code,
         nullif(min(bnf_presentation_name), '') AS bnf_description,
         min(bnf_chemical_substance_code) AS chemical_code,
         nullif(min(substring(bnf_chapter_plus_code FROM '^[0-9]+: (.*)$')), '') AS bnf_chapter_name
  FROM raw.epd_staging
  GROUP BY bnf_presentation_code
) s
JOIN pg_temp.month_chemical c ON c.chemical_code = s.chemical_code
LEFT JOIN core.dim_presentation d ON d.bnf_code = s.bnf_code;

-- name: new_presentation_ids
UPDATE pg_temp.month_presentation
SET presentation_id = nextval(pg_get_serial_sequence('core.dim_presentation', 'presentation_id'))
WHERE is_new;

-- name: month_practice
-- rollup_region is the region the month's rollups count the practice under:
-- a newer month's, if one is loaded; '-' when unknown.
CREATE TEMP TABLE month_practice AS
SELECT s.*, d.practice_id, d.practice_id IS NULL AS is_new,
       coalesce(CASE WHEN d.last_seen > {ym} THEN d.region_code ELSE s.region_code END, '-')
         AS rollup_region
FROM (
  SELECT practice_code,
         nullif(min(practice_name), '') AS practice_name,
         nullif(concat_ws(', ',
           nullif(min(address_1), ''), nullif(min(address_2), ''),
           nullif(min(address_3), ''), nullif(min(address_4), '')), '') AS address,
         nullif(min(postcode), '') AS postcode,
         nullif(min(icb_code), '') AS icb_code,
         nullif(min(icb_name), '') AS icb_name,
         nullif(min(regional_office_code), '') AS region_code,
         nullif(min(regional_office_name), '') AS region_name,
         bool_or(unidentified = 'Y') AS is_unidentified
  FROM raw.epd_staging
  GROUP BY practice_code
) s
LEFT JOIN core.dim_practice d ON d.practice_code = s.practice_code;

-- name: new_practice_ids
UPDATE pg_temp.month_practice
SET practice_id = nextval(pg_get_serial_sequence('core.dim_practice', 'practice_id'))
WHERE is_new;

-- name: analyze_month_tables
-- Autovacuum never analyses temporary tables; the build joins them to staging.
ANALYZE pg_temp.month_chemical, pg_temp.month_presentation, pg_temp.month_practice;

-- name: update_chemicals
UPDATE core.dim_chemical d
SET chemical_name = CASE WHEN {ym} >= d.last_seen THEN m.chemical_name ELSE d.chemical_name END,
    first_seen = least(d.first_seen, {ym}),
    last_seen = greatest(d.last_seen, {ym})
FROM pg_temp.month_chemical m
WHERE NOT m.is_new AND d.chemical_id = m.chemical_id;

-- name: insert_chemicals
INSERT INTO core.dim_chemical (chemical_id, chemical_code, chemical_name, first_seen, last_seen)
OVERRIDING SYSTEM VALUE
SELECT chemical_id, chemical_code, chemical_name, {ym}, {ym}
FROM pg_temp.month_chemical
WHERE is_new;

-- name: update_presentations
UPDATE core.dim_presentation d
SET bnf_description = CASE WHEN {ym} >= d.last_seen THEN m.bnf_description ELSE d.bnf_description END,
    chemical_id = CASE WHEN {ym} >= d.last_seen THEN m.chemical_id ELSE d.chemical_id END,
    bnf_chapter_name = CASE WHEN {ym} >= d.last_seen THEN m.bnf_chapter_name ELSE d.bnf_chapter_name END,
    first_seen = least(d.first_seen, {ym}),
    last_seen = greatest(d.last_seen, {ym})
FROM pg_temp.month_presentation m
WHERE NOT m.is_new AND d.presentation_id = m.presentation_id;

-- name: insert_presentations
INSERT INTO core.dim_presentation (
  presentation_id, bnf_code, bnf_description, chemical_id, bnf_chapter, bnf_chapter_name,
  bnf_section, bnf_paragraph, is_generic, first_seen, last_seen
)
OVERRIDING SYSTEM VALUE
SELECT presentation_id, bnf_code, bnf_description, chemical_id, bnf_chapter, bnf_chapter_name,
       bnf_section, bnf_paragraph, is_generic, {ym}, {ym}
FROM pg_temp.month_presentation
WHERE is_new;

-- name: update_practices
UPDATE core.dim_practice d
SET practice_name = CASE WHEN {ym} >= d.last_seen THEN m.practice_name ELSE d.practice_name END,
    address = CASE WHEN {ym} >= d.last_seen THEN m.address ELSE d.address END,
    postcode = CASE WHEN {ym} >= d.last_seen THEN m.postcode ELSE d.postcode END,
    icb_code = CASE WHEN {ym} >= d.last_seen THEN m.icb_code ELSE d.icb_code END,
    icb_name = CASE WHEN {ym} >= d.last_seen THEN m.icb_name ELSE d.icb_name END,
    region_code = CASE WHEN {ym} >= d.last_seen THEN m.region_code ELSE d.region_code END,
    region_name = CASE WHEN {ym} >= d.last_seen THEN m.region_name ELSE d.region_name END,
    is_unidentified = CASE WHEN {ym} >= d.last_seen THEN m.is_unidentified ELSE d.is_unidentified END,
    first_seen = least(d.first_seen, {ym}),
    last_seen = greatest(d.last_seen, {ym})
FROM pg_temp.month_practice m
WHERE NOT m.is_new AND d.practice_id = m.practice_id;

-- name: insert_practices
INSERT INTO core.dim_practice (
  practice_id, practice_code, practice_name, address, postcode, icb_code, icb_name,
  region_code, region_name, is_unidentified, first_seen, last_seen
)
OVERRIDING SYSTEM VALUE
SELECT practice_id, practice_code, practice_name, address, postcode, icb_code, icb_name,
       region_code, region_name, is_unidentified, {ym}, {ym}
FROM pg_temp.month_practice
WHERE is_new;
