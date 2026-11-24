-- fetch_search_practices(q, limit): practices whose name matches q, or whose
-- code starts with it, best match first (spec section 5.2). Leaves out the
-- unidentified prescribers, and practices with no data in the window.
--
-- $1 q, the search text, two characters or more; $2 limit, the number of
-- matches, a positive whole number (NULL would mean no limit). In q, \ is
-- LIKE's escape character and % and _ its wildcards: the fetch function
-- refuses shorter text and escapes the three, \ first.
--
-- A name matches as in the drug search: it contains q, or, for two
-- characters, starts with q or has a word, after a space, that does. A code
-- typed in full ranks first, then names that contain q, by trigram similarity
-- to q; then matches by code alone, and practices without a name.
--
-- In a plan made with the value, as the app's are, each side of the match uses
-- an index: the trigram index on the name for ILIKE, the code prefix index
-- (migration 008) for LIKE. A generic plan scans the practices.
SELECT practice_id, practice_code, practice_name, postcode, icb_name, region_name
FROM app.v_practice
WHERE (CASE WHEN length($1) < 3
            THEN practice_name ILIKE $1 || '%' OR practice_name ILIKE '% ' || $1 || '%'
            ELSE practice_name ILIKE '%' || $1 || '%' END
       OR practice_code LIKE upper($1) || '%')
  AND NOT is_unidentified
  AND last_seen >= (SELECT first_month FROM app.v_window)
ORDER BY CASE WHEN practice_code = upper($1) THEN 2
              WHEN strpos(lower(practice_name), lower($1)) = 0 THEN 0
              ELSE coalesce(similarity(practice_name, $1), 0) END DESC,
         practice_name, practice_id
LIMIT $2;
