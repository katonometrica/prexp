# The schema built by the migrations (spec sections 3.1 to 3.3). Each test gets a
# new database from local_migrated_db().

relations <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT n.nspname AS schema, c.relname AS name, n.nspname || '.' || c.relname AS qualified,
           c.relkind::text AS kind, c.relpersistence::text AS persistence, c.oid::int8 AS oid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('raw', 'core', 'app', 'meta') AND c.relkind IN ('r', 'p', 'v', 'm')
    ORDER BY 3")
}

# has_table_privilege() for one role and a list of privileges, for each relation:
# with all = TRUE every privilege must be held, otherwise any one.
table_privilege <- function(con, oids, role, privileges, all = TRUE) {
  sql <- paste0(
    "SELECT ", if (all) "bool_and" else "bool_or",
    "(has_table_privilege($1, $2::oid, p)) AS ok FROM unnest($3::text[]) AS p"
  )
  vapply(oids, function(oid) {
    DBI::dbGetQuery(
      con, sql,
      params = list(role, oid, paste0("{", paste(privileges, collapse = ","), "}"))
    )$ok
  }, logical(1))
}

test_that("migrate() builds the full schema on an empty database", {
  dbname <- local_migrated_db()
  con <- local_test_db("owner", dbname = dbname)
  rel <- relations(con)

  tables <- rel$qualified[rel$kind %in% c("r", "p")]
  expect_identical(tables, c(
    "core.agg_chemical_month", "core.agg_practice_month", "core.agg_presentation_month",
    "core.dim_chemical", "core.dim_practice", "core.dim_presentation",
    "core.load_log", "core.prescribing", "meta.schema_migrations", "raw.epd_staging"
  ))
  expect_identical(rel$qualified[rel$kind == "v"], paste0("app.", c(
    "v_chemical", "v_chemical_month", "v_practice", "v_practice_month",
    "v_practice_presentation", "v_presentation", "v_presentation_month",
    "v_region", "v_window"
  )))
  # Only views in app
  expect_true(all(rel$kind[rel$schema == "app"] == "v"))
  expect_identical(rel$persistence[rel$qualified == "raw.epd_staging"], "u")
})

test_that("the fact table is partitioned by month, with its indexes on the parent", {
  dbname <- local_migrated_db()
  con <- local_test_db("owner", dbname = dbname)
  part <- DBI::dbGetQuery(con, "
    SELECT pg_get_partkeydef('core.prescribing'::regclass) AS key,
           (SELECT count(*)::int FROM pg_inherits
            WHERE inhparent = 'core.prescribing'::regclass) AS partitions")
  expect_identical(part$key, "RANGE (year_month)")
  # No partitions yet, and so no default partition either
  expect_identical(part$partitions, 0L)

  idx <- DBI::dbGetQuery(con, "
    SELECT indexname, indexdef FROM pg_indexes
    WHERE schemaname = 'core' AND tablename = 'prescribing'
    ORDER BY indexname")
  expect_identical(idx$indexname, c("prescribing_practice_idx", "prescribing_presentation_idx"))
  expect_match(
    idx$indexdef[1],
    "(practice_id, year_month) INCLUDE (presentation_id, items, adq_usage, nic, actual_cost)",
    fixed = TRUE
  )
  expect_match(
    idx$indexdef[2],
    paste(
      "(presentation_id, year_month)",
      "INCLUDE (practice_id, items, total_quantity, adq_usage, nic, actual_cost)"
    ),
    fixed = TRUE
  )
})

test_that("staging has one text column per source column, in the source's order", {
  dbname <- local_migrated_db()
  con <- local_test_db("owner", dbname = dbname)
  cols <- DBI::dbGetQuery(con, "
    SELECT column_name, data_type FROM information_schema.columns
    WHERE table_schema = 'raw' AND table_name = 'epd_staging'
    ORDER BY ordinal_position")
  source <- utils::read.csv(system.file("extdata", "epd_columns.csv", package = "prexp"))
  expect_identical(cols$column_name, tolower(source$name))
  expect_true(all(cols$data_type == "text"))
})

test_that("the app role reads every app view, and nothing in core, raw or meta", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  rel <- relations(owner)
  in_app <- rel$schema == "app"
  can_select <- table_privilege(owner, rel$oid, "prexp_app", "SELECT")
  expect_true(all(can_select[in_app]))
  expect_false(any(can_select[!in_app]))
  # Simple views are updatable, so the app must not hold any write privilege on them
  writes <- c("INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER")
  expect_false(any(table_privilege(owner, rel$oid, "prexp_app", writes, all = FALSE)))

  app <- local_test_db("app", dbname = dbname)
  for (view in rel$qualified[in_app]) {
    expect_no_error(DBI::dbGetQuery(app, paste("SELECT * FROM", view, "LIMIT 0")))
  }
  for (table in c("core.dim_practice", "core.prescribing", "core.load_log", "raw.epd_staging")) {
    expect_error(
      DBI::dbGetQuery(app, paste("SELECT 1 FROM", table, "LIMIT 1")),
      "permission denied"
    )
  }
})

test_that("the loader writes raw and core, but cannot change or drop the tables", {
  dbname <- local_migrated_db()
  owner <- local_test_db("owner", dbname = dbname)
  rel <- relations(owner)
  writable <- rel[rel$schema %in% c("raw", "core"), ]
  dml <- c("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE")
  can_write <- table_privilege(owner, writable$oid, "prexp_loader", dml)
  expect_true(all(can_write), label = toString(writable$qualified[!can_write]))

  loader <- local_test_db("loader", dbname = dbname)
  # The identity columns work for the loader, and the app views read the result
  DBI::dbWithTransaction(loader, {
    DBI::dbExecute(loader, "
      INSERT INTO core.dim_chemical (chemical_code, chemical_name, first_seen, last_seen)
      VALUES ('0212000B0', 'Atorvastatin', 202609, 202609)")
    DBI::dbExecute(loader, "
      INSERT INTO core.dim_presentation (bnf_code, bnf_description, chemical_id, bnf_chapter,
        bnf_section, bnf_paragraph, is_generic, first_seen, last_seen)
      SELECT '0212000B0AAABAB', 'Atorvastatin 20mg tablets', chemical_id, '02', '0212',
        '021200', true, 202609, 202609
      FROM core.dim_chemical WHERE chemical_code = '0212000B0'")
    DBI::dbExecute(loader, "INSERT INTO core.load_log (year_month) VALUES (202609)")
    DBI::dbExecute(loader, "INSERT INTO raw.epd_staging (year_month) VALUES ('2026-09')")
    DBI::dbExecute(loader, "TRUNCATE raw.epd_staging")
    presentations <- DBI::dbGetQuery(loader, "SELECT chemical_name FROM app.v_presentation")
    expect_identical(presentations$chemical_name, "Atorvastatin")
    DBI::dbBreak()
  })
  expect_error(DBI::dbExecute(loader, "DROP TABLE raw.epd_staging"), "must be owner")
  expect_error(
    DBI::dbExecute(loader, "ALTER TABLE core.prescribing ADD COLUMN x int"),
    "must be owner"
  )
  expect_error(
    DBI::dbExecute(loader, "CREATE TABLE core.prescribing_209901 (LIKE core.prescribing)"),
    "permission denied"
  )
})

test_that("only one load of a month can be live", {
  dbname <- local_migrated_db()
  loader <- local_test_db("loader", dbname = dbname)
  # Literal SQL: RPostgres leaves a failed parameterised statement's result open
  insert <- function(status) {
    DBI::dbExecute(loader, paste0(
      "INSERT INTO core.load_log (year_month, status) VALUES (202609, '", status, "')"
    ), immediate = TRUE)
  }
  insert("loaded")
  insert("failed")
  expect_error(insert("loaded"), "load_log_live_month")
  expect_error(insert("done"), "check constraint")
  window <- DBI::dbGetQuery(loader, "SELECT first_month, last_month, months FROM app.v_window")
  expect_identical(window$months, 1L)
  expect_identical(window$first_month, 202609L)
})
