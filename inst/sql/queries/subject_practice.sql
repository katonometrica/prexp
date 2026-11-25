-- fetch_subject("practice", code): a practice's id and name by its code, as a
-- report's link names it (spec section 5.5). Not only those with data in the
-- window: dimension rows are never deleted, so that a link keeps its
-- subjects after they leave it. Not the unidentified prescribers, which the
-- search does not find either. No row for an unknown code.
--
-- $1 practice_code.
SELECT practice_id AS id, practice_code AS code, practice_name AS name
FROM app.v_practice
WHERE practice_code = $1 AND NOT is_unidentified;
