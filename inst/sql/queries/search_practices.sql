-- fetch_search_practices(q, limit): practices whose name matches q, or whose
-- code starts with it, best match first (spec section 5.2). Leaves out the
-- unidentified prescribers, and practices with no data in the window.
--
-- $1 q, the search text as typed, two characters or more; $2 limit, the
-- number of matches, a positive whole number (NULL would mean no limit). In
-- the patterns, q's \, % and _ are escaped, \ first, so that every character
-- matches itself. The backslashes are written in E'' strings, which read the
-- same whatever standard_conforming_strings is.
--
-- A name matches as in the drug search: it contains q, or, for two
-- characters, starts with q or has a word, after a space, that does. A code
-- typed in full ranks first, then names that contain q, by trigram similarity
-- to q; then matches by code alone, and practices without a name.
--
-- In a plan made with the value, as the app's are, the search CTE is inlined,
-- its pattern folded into a constant, and each side of the match uses an
-- index: the trigram index on the name for ILIKE, the code prefix index
-- (migration 008) for LIKE. A generic plan scans the practices.
WITH search AS NOT MATERIALIZED (
  SELECT $1::text AS q,
         replace(replace(replace($1::text, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') AS pattern
)
SELECT p.practice_id, p.practice_code, p.practice_name, p.postcode, p.icb_name,
       p.region_name
FROM app.v_practice p, search s
WHERE (CASE WHEN length(s.q) < 3
            THEN p.practice_name ILIKE s.pattern || '%'
              OR p.practice_name ILIKE '% ' || s.pattern || '%'
            ELSE p.practice_name ILIKE '%' || s.pattern || '%' END
       OR p.practice_code LIKE upper(s.pattern) || '%')
  AND NOT p.is_unidentified
  AND p.last_seen >= (SELECT first_month FROM app.v_window)
ORDER BY CASE WHEN p.practice_code = upper(s.q) THEN 2
              WHEN strpos(lower(p.practice_name), lower(s.q)) = 0 THEN 0
              ELSE coalesce(similarity(p.practice_name, s.q), 0) END DESC,
         p.practice_name, p.practice_id
LIMIT $2;
