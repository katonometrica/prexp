-- Checks of a staged and a built month (spec section 4, steps 4 and 7; P1-07).
-- Run as prexp_loader. Sums are compared as exact numeric text. {ym} is the
-- month as YYYYMM, an integer.

-- name: staged_months
-- Run right after staging, before anything else: the staged file must be the
-- month asked for.
SELECT year_month, count(*)::int4 AS rows FROM raw.epd_staging GROUP BY year_month;

-- name: staging_totals
-- Each value is cast once. ITEMS must be a whole number of at least 1, and every
-- other measure finite and not negative: numeric accepts 'NaN' and 'Infinity',
-- which would sum to the same text on both sides of the comparison. A blank
-- value stays an empty string (FORCE_NOT_NULL in staging), so its cast fails.
SELECT count(*)::int4 AS rows,
       count(*) FILTER (WHERE items < 1)::int4 AS bad_items,
       count(*) FILTER (WHERE NOT (
         total_quantity >= 0 AND total_quantity < 1e15 AND adq_usage >= 0 AND adq_usage < 1e15
         AND nic >= 0 AND nic < 1e15 AND actual_cost >= 0 AND actual_cost < 1e15
       ))::int4 AS bad_measures,
       sum(items)::text AS items,
       trim_scale(sum(total_quantity))::text AS total_quantity,
       trim_scale(sum(adq_usage))::text AS adq_usage,
       trim_scale(sum(nic))::text AS nic,
       trim_scale(sum(actual_cost))::text AS actual_cost
FROM (
  SELECT items::int8 AS items, total_quantity::numeric AS total_quantity,
         adq_usage::numeric AS adq_usage, nic::numeric AS nic, actual_cost::numeric AS actual_cost
  FROM raw.epd_staging
) s;

-- name: staging_pairs
SELECT count(*)::int4 AS pairs
FROM (SELECT 1 FROM raw.epd_staging GROUP BY practice_code, bnf_presentation_code) x;

-- name: new_totals
SELECT count(*)::int4 AS rows,
       sum(items::int8)::text AS items,
       trim_scale(sum(total_quantity))::text AS total_quantity,
       trim_scale(coalesce(sum(adq_usage), 0))::text AS adq_usage,
       trim_scale(sum(nic))::text AS nic,
       trim_scale(sum(actual_cost))::text AS actual_cost
FROM core.prescribing_{ym}_new;
