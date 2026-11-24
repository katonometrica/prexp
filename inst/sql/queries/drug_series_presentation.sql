-- fetch_drug_series(level = "presentation"): national monthly totals of one
-- presentation (spec section 5.2), from the presentation x region x month
-- rollup summed over the regions. Every measure is returned, total quantity
-- too, since one presentation has one unit; the fetch function picks one. A
-- month with no prescribing has no row.
--
-- $1 presentation_id; $2 and $3 the first and last month (YYYYMM).
SELECT year_month,
       sum(practices)::int4 AS practices,
       sum(items)::int8 AS items,
       sum(total_quantity) AS total_quantity,
       sum(adq_usage) AS adq_usage,
       sum(nic) AS nic,
       sum(actual_cost) AS actual_cost
FROM app.v_presentation_month
WHERE presentation_id = $1
  AND year_month BETWEEN $2 AND $3
GROUP BY year_month
ORDER BY year_month;
