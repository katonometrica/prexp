-- fetch_search_drugs(q, limit): chemical substances and presentations whose
-- name matches q, or whose BNF code starts with it, best match first (spec
-- section 5.2). Only codes with data in the window.
--
-- $1 q, the search text; $2 limit, the number of matches, a positive whole
-- number (NULL would mean no limit). In q, \ is LIKE's escape character and %
-- and _ its wildcards: the fetch function escapes the three, \ first, and
-- refuses empty text, which would match every name.
--
-- A name matches when it contains q, or for one or two characters when one of
-- its words starts with q: nearly every name contains a pair of letters ('le'
-- is in every "tablets"), so a short search lists the names that begin like
-- it, and stays fast. A code typed in full ranks first, then names by trigram
-- similarity to q; a row without a name ranks last.
--
-- In a plan made with the value, as the app's are (RPostgres sends unnamed
-- statements), three characters or more use an index on each side of the
-- match: the trigram index on the name for ILIKE, the code prefix index
-- (migration 008) for LIKE. Shorter text scans the dimensions, since trigrams
-- need three characters, and so does a generic plan, which cannot use the
-- prefix index without the value.
SELECT level, id, code, name, chemical_id, chemical_name, is_generic
FROM (
  SELECT 'chemical' AS level, chemical_id AS id, chemical_code AS code,
         chemical_name AS name, chemical_id, chemical_name, NULL::boolean AS is_generic,
         CASE WHEN chemical_code = upper($1) THEN 2
              ELSE coalesce(similarity(chemical_name, $1), 0) END AS score
  FROM app.v_chemical
  WHERE (CASE WHEN length($1) < 3
              THEN chemical_name ILIKE $1 || '%' OR chemical_name ILIKE '% ' || $1 || '%'
              ELSE chemical_name ILIKE '%' || $1 || '%' END
         OR chemical_code LIKE upper($1) || '%')
    AND last_seen >= (SELECT first_month FROM app.v_window)
  UNION ALL
  SELECT 'presentation', presentation_id, bnf_code, bnf_description, chemical_id,
         chemical_name, is_generic,
         CASE WHEN bnf_code = upper($1) THEN 2
              ELSE coalesce(similarity(bnf_description, $1), 0) END
  FROM app.v_presentation
  WHERE (CASE WHEN length($1) < 3
              THEN bnf_description ILIKE $1 || '%' OR bnf_description ILIKE '% ' || $1 || '%'
              ELSE bnf_description ILIKE '%' || $1 || '%' END
         OR bnf_code LIKE upper($1) || '%')
    AND last_seen >= (SELECT first_month FROM app.v_window)
) AS matches
ORDER BY score DESC, level, name, id
LIMIT $2;
