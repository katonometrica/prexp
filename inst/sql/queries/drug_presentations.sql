-- fetch_drug_presentations(chemical_id, months): national totals over the
-- months of each presentation of one chemical substance, brand or generic
-- (spec section 5.2), from the presentation x region x month rollup. Most
-- items first.
--
-- $1 chemical_id; $2 and $3 the first and last month (YYYYMM).
SELECT presentation_id, bnf_code, bnf_description, is_generic,
       sum(items)::int8 AS items,
       sum(total_quantity) AS total_quantity,
       sum(adq_usage) AS adq_usage,
       sum(nic) AS nic,
       sum(actual_cost) AS actual_cost
FROM app.v_presentation_month
WHERE chemical_id = $1
  AND year_month BETWEEN $2 AND $3
GROUP BY presentation_id, bnf_code, bnf_description, is_generic
ORDER BY items DESC, presentation_id;
