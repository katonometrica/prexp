-- fetch_search_practices(q, limit): practices whose name matches q, or whose
-- code starts with it, best match first (spec section 5.2). Leaves out the
-- unidentified prescribers, and practices with no data in the window.
--
-- $1 q, the search text; $2 limit, the number of matches, a positive whole
-- number (NULL would mean no limit). In q, \ is LIKE's escape character and %
-- and _ its wildcards: the fetch function escapes the three, \ first, and
-- refuses empty text, which would match every name.
--
-- A name matches when it contains q, or for one or two characters when one of
-- its words starts with q, as in the drug search. A code typed in full ranks
-- first, then names by trigram similarity to q; a practice without a name
-- ranks last.
--
-- In a plan made with the value, as the app's are, three characters or more
-- use an index on each side of the match: the trigram index on the name for
-- ILIKE, the code prefix index (migration 008) for LIKE. Shorter text scans
-- the practices, and so does a generic plan.
SELECT practice_id, practice_code, practice_name, postcode, icb_name, region_name
FROM app.v_practice
WHERE (CASE WHEN length($1) < 3
            THEN practice_name ILIKE $1 || '%' OR practice_name ILIKE '% ' || $1 || '%'
            ELSE practice_name ILIKE '%' || $1 || '%' END
       OR practice_code LIKE upper($1) || '%')
  AND NOT is_unidentified
  AND last_seen >= (SELECT first_month FROM app.v_window)
ORDER BY CASE WHEN practice_code = upper($1) THEN 2
              ELSE coalesce(similarity(practice_name, $1), 0) END DESC,
         practice_name, practice_id
LIMIT $2;
