# migrate() and the migration files. Tests marked "no database" run anywhere;
# the others each get a new, empty database from local_temp_db(), because
# migrations change the schema, and skip when no database is reachable.

installed_migrations <- function() {
  migration_files(system.file("sql/migrations", package = "prexp"))
}

write_sql <- function(dir, name, sql) {
  writeBin(charToRaw(sql), file.path(dir, name))
}

test_that("migration files are ordered by their number (no database)", {
  dir <- withr::local_tempdir()
  for (name in c("10_c.sql", "2_b.sql", "001_a.sql")) {
    write_sql(dir, name, "SELECT 1;\n")
  }
  files <- migration_files(dir)
  expect_identical(files$version, c(1L, 2L, 10L))
  expect_identical(files$file, c("001_a.sql", "2_b.sql", "10_c.sql"))
})

test_that("missing folders, bad names and repeated numbers are refused (no database)", {
  dir <- withr::local_tempdir()
  expect_error(migration_files(file.path(dir, "nowhere")), "not found")
  write_sql(dir, "schemas.sql", "SELECT 1;\n")
  expect_error(migration_files(dir), "schemas.sql", fixed = TRUE)
  unlink(file.path(dir, "schemas.sql"))
  write_sql(dir, "001_a.sql", "SELECT 1;\n")
  write_sql(dir, "1_b.sql", "SELECT 1;\n")
  expect_error(migration_files(dir), "share a version number")
})

test_that("line endings do not change a checksum (no database)", {
  lf <- withr::local_tempdir()
  crlf <- withr::local_tempdir()
  write_sql(lf, "001_a.sql", "CREATE TABLE t (x int);\nSELECT 1;\n")
  write_sql(crlf, "001_a.sql", "CREATE TABLE t (x int);\r\nSELECT 1;\r\n")
  expect_identical(migration_files(lf)$checksum, migration_files(crlf)$checksum)
  write_sql(lf, "001_a.sql", "CREATE TABLE t (x bigint);\nSELECT 1;\n")
  expect_false(identical(migration_files(lf)$checksum, migration_files(crlf)$checksum))
})

test_that("migrate() builds the schemas, extension and grants on an empty database", {
  dbname <- local_temp_db()
  withr::local_envvar(PREXP_DB_NAME = dbname)
  applied <- suppressMessages(migrate())
  expect_identical(applied, installed_migrations()$version)

  con <- local_test_db("owner", dbname = dbname)
  schemas <- DBI::dbGetQuery(con, "
    SELECT nspname FROM pg_namespace
    WHERE nspname IN ('raw', 'core', 'app', 'meta')
    ORDER BY nspname")$nspname
  expect_identical(schemas, c("app", "core", "meta", "raw"))
  extension <- DBI::dbGetQuery(con, "
    SELECT count(*)::int AS n FROM pg_extension WHERE extname = 'pg_trgm'")$n
  expect_identical(extension, 1L)

  access <- DBI::dbGetQuery(con, "
    SELECT r.rolname, s.nspname,
           has_schema_privilege(r.rolname, s.nspname, 'USAGE') AS can_use,
           has_schema_privilege(r.rolname, s.nspname, 'CREATE') AS can_create
    FROM unnest(ARRAY['prexp_app', 'prexp_loader']) AS r(rolname)
    CROSS JOIN unnest(ARRAY['app', 'core', 'meta', 'raw']) AS s(nspname)
    ORDER BY r.rolname, s.nspname")
  # The app role uses app only. The loader uses app, core and raw, not meta.
  expect_identical(access$can_use, c(TRUE, FALSE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE))
  expect_false(any(access$can_create))
})

test_that("tables and views created later by the owner get the default privileges", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  suppressMessages(migrate(con))
  DBI::dbExecute(con, "
    CREATE TABLE raw.staged (x int);
    CREATE TABLE core.fact (id int GENERATED ALWAYS AS IDENTITY, x int);
    CREATE SEQUENCE core.counter;
    CREATE VIEW app.v_fact AS SELECT x FROM core.fact;", immediate = TRUE)
  checks <- DBI::dbGetQuery(con, "
    SELECT n, has_table_privilege(who, what, priv) AS granted, expected
    FROM (VALUES
      (1, 'prexp_loader', 'raw.staged', 'INSERT', true),
      (2, 'prexp_loader', 'raw.staged', 'TRUNCATE', true),
      (3, 'prexp_loader', 'core.fact', 'SELECT', true),
      (4, 'prexp_loader', 'core.fact', 'UPDATE', true),
      (5, 'prexp_loader', 'core.fact', 'DELETE', true),
      (6, 'prexp_loader', 'app.v_fact', 'SELECT', true),
      (7, 'prexp_app', 'app.v_fact', 'SELECT', true),
      (8, 'prexp_app', 'app.v_fact', 'INSERT', false),
      (9, 'prexp_app', 'core.fact', 'SELECT', false),
      (10, 'prexp_app', 'raw.staged', 'SELECT', false)
    ) AS v(n, who, what, priv, expected)
    ORDER BY n")
  expect_identical(checks$granted, checks$expected)
  sequence <- DBI::dbGetQuery(con, "
    SELECT has_sequence_privilege('prexp_loader', 'core.counter', 'USAGE') AS loader,
           has_sequence_privilege('prexp_app', 'core.counter', 'USAGE') AS app")
  expect_identical(c(sequence$loader, sequence$app), c(TRUE, FALSE))
})

test_that("a second migrate() applies nothing", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  suppressMessages(migrate(con))
  ledger <- "SELECT version, checksum, applied_at FROM meta.schema_migrations ORDER BY version"
  before <- DBI::dbGetQuery(con, ledger)
  expect_silent(applied <- migrate(con))
  expect_identical(applied, integer())
  expect_identical(DBI::dbGetQuery(con, ledger), before)
})

test_that("editing an applied file stops migrate() with the file's name", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  dir <- withr::local_tempdir()
  write_sql(dir, "001_first.sql", "CREATE TABLE t1 (x int);\n")
  suppressMessages(migrate(con, dir))
  write_sql(dir, "001_first.sql", "CREATE TABLE t1 (x bigint);\n")
  write_sql(dir, "002_second.sql", "CREATE TABLE t2 (x int);\n")
  expect_error(migrate(con, dir), "001_first.sql", fixed = TRUE)
  # Nothing was applied after the check failed.
  expect_true(DBI::dbGetQuery(con, "SELECT to_regclass('public.t2') IS NULL AS absent")$absent)
})

test_that("an applied file missing from the folder stops migrate()", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  dir <- withr::local_tempdir()
  write_sql(dir, "001_first.sql", "CREATE TABLE t1 (x int);\n")
  suppressMessages(migrate(con, dir))
  unlink(file.path(dir, "001_first.sql"))
  write_sql(dir, "002_second.sql", "CREATE TABLE t2 (x int);\n")
  expect_error(migrate(con, dir), "missing from")
})

test_that("a failing migration is rolled back, and the error names its file", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  dir <- withr::local_tempdir()
  write_sql(dir, "001_broken.sql", "CREATE TABLE t1 (x int);\nSELECT 1 / 0;\n")
  expect_error(migrate(con, dir), "001_broken.sql", fixed = TRUE)
  state <- DBI::dbGetQuery(con, "
    SELECT to_regclass('public.t1') IS NULL AS no_table,
           (SELECT count(*) FROM meta.schema_migrations)::int AS recorded")
  expect_true(state$no_table)
  expect_identical(state$recorded, 0L)
})

test_that("migrate() refuses to run while another session holds its lock", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  other <- local_test_db("owner", dbname = dbname)
  locked <- DBI::dbGetQuery(
    other, "SELECT pg_try_advisory_lock($1, $2) AS locked",
    params = as.list(migration_lock)
  )$locked
  expect_true(locked)
  expect_error(migrate(con), "Another migrate() is running", fixed = TRUE)
})

test_that("a byte-order mark does not change a checksum or reach the server (no database)", {
  plain <- withr::local_tempdir()
  bom <- withr::local_tempdir()
  write_sql(plain, "001_a.sql", "CREATE TABLE t (x int);\n")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("CREATE TABLE t (x int);\n")),
           file.path(bom, "001_a.sql"))
  expect_identical(migration_files(bom)$checksum, migration_files(plain)$checksum)
  expect_identical(migration_files(bom)$sql, "CREATE TABLE t (x int);")
})

test_that("migrate() refuses anything but a single connection (no database)", {
  expect_error(migrate(list()), "not a pool", fixed = TRUE)
})

test_that("migrate() refuses to run as any role but prexp_owner", {
  dbname <- local_temp_db()
  con <- local_test_db("loader", dbname = dbname)
  expect_error(migrate(con), "must run as prexp_owner, not prexp_loader", fixed = TRUE)
})

test_that("a pending file numbered below the last applied one stops migrate()", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  dir <- withr::local_tempdir()
  write_sql(dir, "001_first.sql", "CREATE TABLE t1 (x int);\n")
  write_sql(dir, "003_third.sql", "CREATE TABLE t3 (x int);\n")
  suppressMessages(migrate(con, dir))
  write_sql(dir, "002_second.sql", "CREATE TABLE t2 (x int);\n")
  expect_error(migrate(con, dir), "002_second.sql", fixed = TRUE)
  expect_true(DBI::dbGetQuery(con, "SELECT to_regclass('public.t2') IS NULL AS absent")$absent)
})

test_that("every statement after a row-returning one is applied", {
  dbname <- local_temp_db()
  con <- local_test_db("owner", dbname = dbname)
  dir <- withr::local_tempdir()
  write_sql(dir, "001_rows.sql", paste(
    "CREATE SEQUENCE s;",
    "SELECT setval('s', 41);",
    "CREATE TABLE after_rows (x int);",
    "INSERT INTO after_rows VALUES (nextval('s'));",
    sep = "\n"
  ))
  suppressMessages(migrate(con, dir))
  expect_identical(DBI::dbGetQuery(con, "SELECT x FROM after_rows")$x, 42L)
})
