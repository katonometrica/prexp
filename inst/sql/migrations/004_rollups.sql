-- 004_rollups.sql: monthly rollups of the fact table (spec section 3.2),
-- rebuilt one month at a time by the loader's swap (P1-07).
--
-- region_code is the practice's region when the month was loaded ('-' when
-- unknown or for the national unidentified prescriber). practices and
-- presentations count the distinct prescribers and presentations behind a row.
-- total_quantity is only kept per presentation, whose unit is fixed, and
-- adq_usage only where daily quantities of one substance can be added.

-- Drug series at presentation level, without touching the fact table
CREATE TABLE core.agg_presentation_month (
  year_month int4 NOT NULL,
  presentation_id int4 NOT NULL,
  region_code text NOT NULL,
  practices int4 NOT NULL,
  items int8 NOT NULL,
  total_quantity numeric NOT NULL,
  adq_usage numeric,
  nic numeric NOT NULL,
  actual_cost numeric NOT NULL,
  PRIMARY KEY (presentation_id, year_month, region_code)
);
CREATE INDEX agg_presentation_month_month_idx ON core.agg_presentation_month
  (year_month, region_code);

-- Drug series at chemical level, and the regional comparison
CREATE TABLE core.agg_chemical_month (
  year_month int4 NOT NULL,
  chemical_id int4 NOT NULL,
  region_code text NOT NULL,
  practices int4 NOT NULL,
  items int8 NOT NULL,
  adq_usage numeric,
  nic numeric NOT NULL,
  actual_cost numeric NOT NULL,
  PRIMARY KEY (chemical_id, year_month, region_code)
);
CREATE INDEX agg_chemical_month_month_idx ON core.agg_chemical_month
  (year_month, region_code);

-- Practice monthly totals
CREATE TABLE core.agg_practice_month (
  year_month int4 NOT NULL,
  practice_id int4 NOT NULL,
  presentations int4 NOT NULL,
  items int8 NOT NULL,
  nic numeric NOT NULL,
  actual_cost numeric NOT NULL,
  PRIMARY KEY (practice_id, year_month)
);
CREATE INDEX agg_practice_month_month_idx ON core.agg_practice_month (year_month);
