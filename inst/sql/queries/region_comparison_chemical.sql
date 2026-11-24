-- fetch_region_comparison(level = "chemical"): totals over the months per NHS
-- region for one chemical substance (spec section 5.2), from the chemical x
-- region x month rollup. Region '-' holds prescribers with no region, such as
-- the national unidentified prescriber.
--
-- $1 chemical_id; $2 and $3 the first and last month (YYYYMM), $2 <= $3:
-- reversed, they match no month, which would read as no prescribing.
SELECT a.region_code, r.region_name,
       sum(a.items)::int8 AS items,
       sum(a.adq_usage) AS adq_usage,
       sum(a.nic) AS nic,
       sum(a.actual_cost) AS actual_cost
FROM app.v_chemical_month a
LEFT JOIN app.v_region r ON r.region_code = a.region_code
WHERE a.chemical_id = $1
  AND a.year_month BETWEEN $2 AND $3
GROUP BY a.region_code, r.region_name
ORDER BY a.region_code;
