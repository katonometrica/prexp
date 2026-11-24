-- 008_query_tuning.sql: an index per code and a view, tuned against the full
-- window (P2-05; measured in docs/benchmarks.md).

-- Code prefixes. The database's collation is not C, so the unique indexes on
-- the codes cannot serve LIKE 'ABC%'; these can. With the trigram index on the
-- name, a search for three characters or more (name contains q, or code starts
-- with it) becomes a BitmapOr of the two indexes instead of a sequential scan
-- of the dimension.
CREATE INDEX dim_chemical_code_prefix ON core.dim_chemical (chemical_code text_pattern_ops);
CREATE INDEX dim_presentation_code_prefix ON core.dim_presentation (bnf_code text_pattern_ops);
CREATE INDEX dim_practice_code_prefix ON core.dim_practice (practice_code text_pattern_ops);

-- A practice's prescribing by presentation, with a LEFT JOIN now: a query that
-- uses no presentation column, such as a practice's top drugs, which names only
-- the page it returns, skips the join, since the dimension's primary key makes
-- it removable, instead of probing the dimension for every fact row. Every
-- fact row has its presentation: the loader builds the rows from the dimension,
-- whose rows are never deleted.
CREATE OR REPLACE VIEW app.v_practice_presentation AS
SELECT f.year_month, f.practice_id, f.presentation_id,
       p.bnf_code, p.bnf_description, p.chemical_id, p.is_generic,
       f.items, f.total_quantity, f.adq_usage, f.nic, f.actual_cost
FROM core.prescribing f
LEFT JOIN core.dim_presentation p ON p.presentation_id = f.presentation_id;
