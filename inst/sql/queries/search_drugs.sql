-- fetch_search_drugs(q, limit): chemical substances and presentations whose
-- name contains q, or whose BNF code starts with it, best match first (spec
-- section 5.2). Only codes with data in the window.
--
-- $1 q, the search text; $2 limit, the number of matches, a positive whole
-- number (NULL would mean no limit). In q, \ is LIKE's escape character and %
-- and _ its wildcards: the fetch function escapes the three, \ first, and
-- refuses empty text, which would match every name.
--
-- A code typed in full ranks first, then names by trigram similarity to q; a
-- row without a name ranks last. The name match alone could use the trigram
-- index on each name, but OR'ed with the code prefix, which no index serves
-- until migration 008 (P2-05), each search scans the dimensions.
SELECT level, id, code, name, chemical_id, chemical_name, is_generic
FROM (
  SELECT 'chemical' AS level, chemical_id AS id, chemical_code AS code,
         chemical_name AS name, chemical_id, chemical_name, NULL::boolean AS is_generic,
         CASE WHEN chemical_code = upper($1) THEN 2
              ELSE coalesce(similarity(chemical_name, $1), 0) END AS score
  FROM app.v_chemical
  WHERE (chemical_name ILIKE '%' || $1 || '%' OR chemical_code LIKE upper($1) || '%')
    AND last_seen >= (SELECT first_month FROM app.v_window)
  UNION ALL
  SELECT 'presentation', presentation_id, bnf_code, bnf_description, chemical_id,
         chemical_name, is_generic,
         CASE WHEN bnf_code = upper($1) THEN 2
              ELSE coalesce(similarity(bnf_description, $1), 0) END
  FROM app.v_presentation
  WHERE (bnf_description ILIKE '%' || $1 || '%' OR bnf_code LIKE upper($1) || '%')
    AND last_seen >= (SELECT first_month FROM app.v_window)
) AS matches
ORDER BY score DESC, level, name, id
LIMIT $2;
