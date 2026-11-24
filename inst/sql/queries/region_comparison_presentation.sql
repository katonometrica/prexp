-- fetch_region_comparison(level = "presentation"): totals over the months per
-- NHS region for one presentation (spec section 5.2), from the presentation x
-- region x month rollup. Region '-' holds prescribers with no region, such as
-- the national unidentified prescriber.
--
-- $1 presentation_id; $2 and $3 the first and last month (YYYYMM).
SELECT a.region_code, r.region_name,
       sum(a.items)::int8 AS items,
       sum(a.total_quantity) AS total_quantity,
       sum(a.adq_usage) AS adq_usage,
       sum(a.nic) AS nic,
       sum(a.actual_cost) AS actual_cost
FROM app.v_presentation_month a
LEFT JOIN app.v_region r ON r.region_code = a.region_code
WHERE a.presentation_id = $1
  AND a.year_month BETWEEN $2 AND $3
GROUP BY a.region_code, r.region_name
ORDER BY a.region_code;
