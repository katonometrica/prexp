-- fetch_search_practices(q, limit): practices whose name contains q, or whose
-- code starts with it, best match first (spec section 5.2). Leaves out the
-- unidentified prescribers, and practices with no data in the window.
--
-- $1 q, the search text; $2 limit, the number of matches, a positive whole
-- number (NULL would mean no limit). In q, \ is LIKE's escape character and %
-- and _ its wildcards: the fetch function escapes the three, \ first, and
-- refuses empty text, which would match every name.
--
-- A code typed in full ranks first, then names by trigram similarity to q; a
-- practice without a name ranks last. For three characters or more, each side
-- of the match has its index: the trigram index on the name for ILIKE, the
-- code prefix index (migration 008) for LIKE. Shorter text scans the
-- practices, since trigrams need three characters.
SELECT practice_id, practice_code, practice_name, postcode, icb_name, region_name
FROM app.v_practice
WHERE (practice_name ILIKE '%' || $1 || '%' OR practice_code LIKE upper($1) || '%')
  AND NOT is_unidentified
  AND last_seen >= (SELECT first_month FROM app.v_window)
ORDER BY CASE WHEN practice_code = upper($1) THEN 2
              ELSE coalesce(similarity(practice_name, $1), 0) END DESC,
         practice_name, practice_id
LIMIT $2;
