-- fetch_subject("presentation", code): a presentation's id and name by its
-- BNF code, as a report's link names it (spec section 5.5). Not only those
-- with data in the window: dimension rows are never deleted, so that a link
-- keeps its subjects after they leave it. No row for an unknown code.
--
-- $1 bnf_code.
SELECT presentation_id AS id, bnf_code AS code, bnf_description AS name
FROM app.v_presentation
WHERE bnf_code = $1;
