-- fetch_practice_top_drugs(practice_id, months, by, limit, after): a
-- practice's presentations over the months, ranked by items, NIC or actual
-- cost, one page at a time (spec section 5.2). Reads the fact table through
-- app.v_practice_presentation; the practice index holds every fact column
-- used, so each month is an index-only scan of one partition. The names are
-- joined to the page only, though until migration 008 (P2-05) the view still
-- joins the presentations to every fact row.
--
-- $1 practice_id; $2 and $3 the first and last month (YYYYMM), $2 <= $3; $4
-- the ranking measure, 'items', 'nic' or 'actual_cost' (anything else ranks
-- nothing: every total is NULL); $5 the page size, a positive whole number;
-- $6 the presentation_id of the last row of the previous page, NULL for the
-- first page.
--
-- Keyset paging on (total, presentation_id): a page starts strictly after the
-- previous page's last row. Its total is looked up here, exactly, rather than
-- passed back: a numeric total read into R is a double, which would come back
-- a little above or below the decimal and repeat or skip rows.
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
), ranked AS (
  SELECT t.*,
         CASE $4::text
           WHEN 'items' THEN t.items::numeric
           WHEN 'nic' THEN t.nic
           WHEN 'actual_cost' THEN t.actual_cost
         END AS total
  FROM totals t
), page AS (
  SELECT *
  FROM ranked
  WHERE $6::int4 IS NULL
     OR (total, presentation_id) <
        ((SELECT r.total FROM ranked r WHERE r.presentation_id = $6::int4), $6::int4)
  ORDER BY total DESC, presentation_id DESC
  LIMIT $5
)
SELECT g.presentation_id, p.bnf_code, p.bnf_description, p.chemical_id, p.chemical_name,
       p.is_generic, g.items, g.adq_usage, g.nic, g.actual_cost, g.total
FROM page g
JOIN app.v_presentation p ON p.presentation_id = g.presentation_id
ORDER BY g.total DESC, g.presentation_id DESC;
