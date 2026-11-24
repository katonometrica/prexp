-- fetch_practice_profile(practice_id): a practice's name, address, ICB and
-- region, as in the latest month loaded (spec section 5.2). No row for an
-- unknown id.
--
-- $1 practice_id.
SELECT practice_id, practice_code, practice_name, address, postcode,
       icb_code, icb_name, region_code, region_name, is_unidentified,
       first_seen, last_seen
FROM app.v_practice
WHERE practice_id = $1;
