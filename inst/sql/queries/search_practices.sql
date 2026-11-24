-- fetch_search_practices(q, limit): practices whose name contains q, or whose
-- code starts with it, best match first (spec section 5.2). Leaves out the
-- unidentified prescribers, and practices with no data in the window.
--
-- $1 q, the search text; $2 limit, the number of matches.
--
-- The name match (ILIKE) can use the trigram index on the name. A code typed
-- in full ranks first, then names by trigram similarity to q. q's % and _ are
-- wildcards: the fetch function deals with them.
SELECT practice_id, practice_code, practice_name, postcode, icb_name, region_name
FROM app.v_practice
WHERE (practice_name ILIKE '%' || $1 || '%' OR practice_code LIKE upper($1) || '%')
  AND NOT is_unidentified
  AND last_seen >= (SELECT first_month FROM app.v_window)
ORDER BY CASE WHEN practice_code = upper($1) THEN 2 ELSE similarity(practice_name, $1) END DESC,
         practice_name, practice_id
LIMIT $2;
