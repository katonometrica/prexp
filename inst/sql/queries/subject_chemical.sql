-- fetch_subject("chemical", code): a chemical substance's id and name by its
-- code, as a report's link names it (spec section 5.5). Not only those with
-- data in the window: dimension rows are never deleted, so that a link keeps
-- its subjects after they leave it. No row for an unknown code.
--
-- $1 chemical_code.
SELECT chemical_id AS id, chemical_code AS code, chemical_name AS name
FROM app.v_chemical
WHERE chemical_code = $1;
