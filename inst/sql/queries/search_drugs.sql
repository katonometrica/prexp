-- fetch_search_drugs(q, limit): chemical substances and presentations whose
-- name matches q, or whose BNF code starts with it, best match first (spec
-- section 5.2). Only codes with data in the window.
--
-- $1 q, the search text as typed, two characters or more: a single character
-- matches too many names, and the app ignores it (spec section 5.4); $2 limit,
-- the number of matches, a positive whole number (NULL would mean no limit).
-- In the patterns, q's \, % and _ are escaped, \ first, so that every
-- character matches itself: '1%' finds "1% cream", not every name with a 1.
-- The backslashes are written in E'' strings, which read the same whatever
-- standard_conforming_strings is.
--
-- A name matches when it contains q, or, for two characters, when it starts
-- with q or has a word, after a space, that does: nearly every name contains a
-- pair of letters ('le' is in every "tablets"), so a short search lists the
-- names that begin like it. A code typed in full ranks first, then names that
-- contain q, by trigram similarity to q; then the matches by code alone, and
-- rows without a name. similarity() is not computed for a name without q in
-- it: a code prefix such as '23' matches thousands of appliances by code.
--
-- In a plan made with the value, as the app's are (RPostgres sends unnamed
-- statements), the search CTE is inlined, its pattern folded into a constant,
-- and each side of the match uses an index: the trigram index on the name for
-- ILIKE, including for two characters, whose word starts pg_trgm reads as
-- padded trigrams, and the code prefix index (migration 008) for LIKE. The
-- time goes on ranking the names with similarity(), about 6 us each. A
-- generic plan cannot use either index without the value, and scans the
-- dimensions.
WITH search AS NOT MATERIALIZED (
  SELECT $1::text AS q,
         replace(replace(replace($1::text, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') AS pattern
)
SELECT level, id, code, name, chemical_id, chemical_name, is_generic
FROM (
  SELECT 'chemical' AS level, c.chemical_id AS id, c.chemical_code AS code,
         c.chemical_name AS name, c.chemical_id, c.chemical_name,
         NULL::boolean AS is_generic,
         CASE WHEN c.chemical_code = upper(s.q) THEN 2
              WHEN strpos(lower(c.chemical_name), lower(s.q)) = 0 THEN 0
              ELSE coalesce(similarity(c.chemical_name, s.q), 0) END AS score
  FROM app.v_chemical c, search s
  WHERE (CASE WHEN length(s.q) < 3
              THEN c.chemical_name ILIKE s.pattern || '%'
                OR c.chemical_name ILIKE '% ' || s.pattern || '%'
              ELSE c.chemical_name ILIKE '%' || s.pattern || '%' END
         OR c.chemical_code LIKE upper(s.pattern) || '%')
    AND c.last_seen >= (SELECT first_month FROM app.v_window)
  UNION ALL
  SELECT 'presentation', p.presentation_id, p.bnf_code, p.bnf_description,
         p.chemical_id, p.chemical_name, p.is_generic,
         CASE WHEN p.bnf_code = upper(s.q) THEN 2
              WHEN strpos(lower(p.bnf_description), lower(s.q)) = 0 THEN 0
              ELSE coalesce(similarity(p.bnf_description, s.q), 0) END
  FROM app.v_presentation p, search s
  WHERE (CASE WHEN length(s.q) < 3
              THEN p.bnf_description ILIKE s.pattern || '%'
                OR p.bnf_description ILIKE '% ' || s.pattern || '%'
              ELSE p.bnf_description ILIKE '%' || s.pattern || '%' END
         OR p.bnf_code LIKE upper(s.pattern) || '%')
    AND p.last_seen >= (SELECT first_month FROM app.v_window)
) AS matches
ORDER BY score DESC, level, name, id
LIMIT $2;
