-- fetch_search_drugs(q, limit): chemical substances and presentations whose
-- name matches q, or whose BNF code starts with it, best match first (spec
-- section 5.2). Only codes with data in the window.
--
-- $1 q, the search text, two characters or more: a single character matches
-- too many names, and the app ignores it (spec section 5.4); $2 limit, the
-- number of matches, a positive whole number (NULL would mean no limit). In q,
-- \ is LIKE's escape character and % and _ its wildcards: the fetch function
-- refuses shorter text and escapes the three, \ first. The length rule below
-- counts q as passed, escapes included.
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
-- statements), each side of the match uses an index: the trigram index on the
-- name for ILIKE, including for two characters, whose word starts pg_trgm
-- reads as padded trigrams, and the code prefix index (migration 008) for
-- LIKE. The time goes on ranking the names with similarity(), about 6 us
-- each. A generic plan cannot use either index without the value, and scans
-- the dimensions.
SELECT level, id, code, name, chemical_id, chemical_name, is_generic
FROM (
  SELECT 'chemical' AS level, chemical_id AS id, chemical_code AS code,
         chemical_name AS name, chemical_id, chemical_name, NULL::boolean AS is_generic,
         CASE WHEN chemical_code = upper($1) THEN 2
              WHEN strpos(lower(chemical_name), lower($1)) = 0 THEN 0
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
              WHEN strpos(lower(bnf_description), lower($1)) = 0 THEN 0
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
