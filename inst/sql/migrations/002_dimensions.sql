-- 002_dimensions.sql: the chemical, presentation and practice dimensions
-- (spec section 3.2), filled from staging by the loader's upsert (P1-06).
--
-- Codes are the source's own. The integer ids are this database's keys, used by
-- the fact table and the rollups. Dimension rows are never deleted, so shared
-- links never point at a missing key. first_seen and last_seen are the first
-- and last month (YYYYMM) a code was loaded for; names, ICB and region come
-- from the latest month loaded, so every month shows today's names and
-- geography. The source's empty strings are loaded as NULL.

CREATE TABLE core.dim_chemical (
  chemical_id int4 GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- BNF_CHEMICAL_SUBSTANCE_CODE: 9 characters, or 4 for appliance chapters 20 to 23
  chemical_code text NOT NULL UNIQUE,
  chemical_name text,
  first_seen int4 NOT NULL,
  last_seen int4 NOT NULL,
  CHECK (first_seen <= last_seen)
);

-- No SNOMED code: a presentation can have several.
CREATE TABLE core.dim_presentation (
  presentation_id int4 GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- BNF_PRESENTATION_CODE: 15 characters, or 11 for appliance chapters 20 to 23
  bnf_code text NOT NULL UNIQUE,
  bnf_description text,
  chemical_id int4 NOT NULL REFERENCES core.dim_chemical (chemical_id),
  -- From the code: chapter '05', section '0501', paragraph '050101'
  bnf_chapter text NOT NULL,
  -- From BNF_CHAPTER_PLUS_CODE ('05: Infections')
  bnf_chapter_name text,
  bnf_section text NOT NULL,
  bnf_paragraph text NOT NULL,
  -- Characters 10 and 11 of the code are AA; NULL for appliance chapters 20 to 23,
  -- whose codes do not follow that rule
  is_generic boolean,
  first_seen int4 NOT NULL,
  last_seen int4 NOT NULL,
  CHECK (first_seen <= last_seen)
);

-- Prescribers: GP practices and other prescribing organisations. Keyed on the
-- code, never the name.
CREATE TABLE core.dim_practice (
  practice_id int4 GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- 6 characters; '-' for the national unidentified prescriber
  practice_code text NOT NULL UNIQUE,
  practice_name text,
  -- ADDRESS_1 to ADDRESS_4, the non-empty ones joined with ', '
  address text,
  postcode text,
  icb_code text,
  icb_name text,
  region_code text,
  region_name text,
  -- UNIDENTIFIED = 'Y' ('UNIDENTIFIED DOCTORS'). Their rows stay in the fact
  -- table, so totals reconcile; views leave them out of practice lists.
  is_unidentified boolean NOT NULL,
  first_seen int4 NOT NULL,
  last_seen int4 NOT NULL,
  CHECK (first_seen <= last_seen)
);

CREATE INDEX dim_presentation_chemical_idx ON core.dim_presentation (chemical_id);

-- Search by name (pg_trgm is in public, migration 001)
CREATE INDEX dim_chemical_name_trgm ON core.dim_chemical
  USING gin (chemical_name public.gin_trgm_ops);
CREATE INDEX dim_presentation_description_trgm ON core.dim_presentation
  USING gin (bnf_description public.gin_trgm_ops);
CREATE INDEX dim_practice_name_trgm ON core.dim_practice
  USING gin (practice_name public.gin_trgm_ops);
