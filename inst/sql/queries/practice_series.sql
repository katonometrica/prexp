-- fetch_practice_series(practice_id, months): a practice's monthly totals
-- (spec section 5.2), from the practice x month rollup. A month with no
-- prescribing has no row.
--
-- $1 practice_id; $2 and $3 the first and last month (YYYYMM).
SELECT year_month, presentations, items, nic, actual_cost
FROM app.v_practice_month
WHERE practice_id = $1
  AND year_month BETWEEN $2 AND $3
ORDER BY year_month;
