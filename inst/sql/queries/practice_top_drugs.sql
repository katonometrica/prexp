-- fetch_practice_top_drugs(practice_id, months, by, limit, after): a
-- practice's presentations over the months, ranked by items, NIC or actual
-- cost, one page at a time (spec section 5.2). Reads the fact table through
-- app.v_practice_presentation; the practice index holds every fact column
-- used, so each month is an index-only scan of one partition. The names are
-- joined to the page only.
--
-- $1 practice_id; $2 and $3 the first and last month (YYYYMM); $4 the
-- ranking measure, 'items', 'nic' or 'actual_cost'; $5 the page size; $6 and
-- $7 the total and presentation_id of the last row of the previous page, both
-- NULL for the first page (keyset paging: a page starts strictly after them).
WITH totals AS (
  SELECT presentation_id,
         sum(items)::int8 AS items,
         sum(adq_usage) AS adq_usage,
         sum(nic) AS nic,
         sum(actual_cost) AS actual_cost
  FROM app.v_practice_presentation
  WHERE practice_id = $1
    AND year_month BETWEEN $2 AND $3
  GROUP BY presentation_id
), page AS (
  SELECT *
  FROM (
    SELECT t.*,
           CASE $4::text
             WHEN 'items' THEN t.items::numeric
             WHEN 'nic' THEN t.nic
             WHEN 'actual_cost' THEN t.actual_cost
           END AS total
    FROM totals t
  ) AS ranked
  WHERE $6::numeric IS NULL
     OR (total, presentation_id) < ($6::numeric, $7::int4)
  ORDER BY total DESC, presentation_id DESC
  LIMIT $5
)
SELECT g.presentation_id, p.bnf_code, p.bnf_description, p.chemical_id, p.chemical_name,
       p.is_generic, g.items, g.adq_usage, g.nic, g.actual_cost, g.total
FROM page g
JOIN app.v_presentation p ON p.presentation_id = g.presentation_id
ORDER BY g.total DESC, g.presentation_id DESC;
