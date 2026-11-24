# The rolling window (spec section 4; P2-01): a new month that takes the
# window beyond PREXP_WINDOW_MONTHS drops the oldest in the same swap, a reload
# drops nothing, and a month older than a full window is refused before
# anything is done.

test_that("the window size comes from PREXP_WINDOW_MONTHS, 12 by default", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = NA)
  expect_identical(window_months(), 12L)
  withr::local_envvar(PREXP_WINDOW_MONTHS = "")
  expect_identical(window_months(), 12L)
  withr::local_envvar(PREXP_WINDOW_MONTHS = " 6 ")
  expect_identical(window_months(), 6L)
  for (bad in c("0", "-1", "1.5", "twelve", "1e3")) {
    withr::local_envvar(PREXP_WINDOW_MONTHS = bad)
    expect_error(window_months(), "PREXP_WINDOW_MONTHS must be a whole number", fixed = TRUE)
  }
})

test_that("a new month beyond a full window drops the oldest, and only then", {
  year <- 202501:202512
  # Room left: nothing goes
  expect_identical(window_drops(integer(), 202609L, 12L), integer())
  expect_identical(window_drops(year[1:6], 202507L, 12L), integer())
  # Full: the oldest goes
  expect_identical(window_drops(year, 202601L, 12L), 202501L)
  # A gap in a full window is filled, and the oldest goes
  expect_identical(window_drops(c(year[-6], 202601L), 202506L, 12L), 202501L)
  # A reload never drops anything, even beyond the window
  expect_identical(window_drops(year, 202505L, 12L), integer())
  expect_identical(window_drops(year, 202505L, 3L), integer())
  # A month older than a full window would drop itself
  expect_identical(window_drops(year, 202412L, 12L), 202412L)
  # A smaller window drops every month beyond it, oldest first
  expect_identical(window_drops(year, 202601L, 6L), year[1:7])
})

dimension_rows <- function(con) {
  DBI::dbGetQuery(con, "
    SELECT 'chemical' AS dimension, count(*)::int AS n, min(first_seen) AS first_seen
    FROM core.dim_chemical
    UNION ALL
    SELECT 'presentation', count(*)::int, min(first_seen) FROM core.dim_presentation
    UNION ALL
    SELECT 'practice', count(*)::int, min(first_seen) FROM core.dim_practice")
}

test_that("the thirteenth month drops the first; a reload drops nothing; older is refused", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = NA)
  months <- fixture_months()
  dbname <- local_loaded_db(months[1:12])
  con <- local_test_db("owner", dbname = dbname)
  dimensions <- dimension_rows(con)
  expect_identical(unique(dimensions$first_seen), 202509L)

  messages <- testthat::capture_messages(res <- load_fixture(months[13], dbname))
  expect_identical(res$dropped, 202509L)
  expect_true("Dropped 202509 to keep the window at 12 months\n" %in% messages)
  # Gone from the fact table, the rollups and the window
  kept <- months[-1]
  expect_identical(partitions(con), paste0("prescribing_", kept))
  expect_loaded_as_oracle(con, kept)
  log <- load_log(con)
  expect_identical(log$year_month, months)
  expect_identical(log$status, c("dropped", rep("loaded", 12)))
  app <- local_test_db("app", dbname = dbname)
  expect_identical(
    DBI::dbGetQuery(app, "SELECT first_month, last_month, months FROM app.v_window"),
    data.frame(first_month = 202510L, last_month = 202609L, months = 12L)
  )
  # Every chemical, presentation and practice keeps its row, first seen in the
  # month that was dropped
  expect_identical(dimension_rows(con), dimensions)

  # Reloading month 5 drops nothing
  res <- suppressMessages(load_fixture(months[5], dbname))
  expect_identical(res$dropped, integer())
  expect_identical(partitions(con), paste0("prescribing_", kept))
  expect_loaded_as_oracle(con, kept)
  expect_identical(
    load_log(con)$status, c("dropped", rep("loaded", 3), "replaced", rep("loaded", 9))
  )

  # The dropped month, now older than the full window, is refused, and nothing
  # changes or is recorded
  before <- core_state(con)
  log <- load_log(con)
  expect_error(
    load_fixture(months[1], dbname),
    paste(
      "202509 is older than 202510, the first month of the window, which is full",
      "(12 months, PREXP_WINDOW_MONTHS): it would be dropped as soon as it was loaded."
    ),
    fixed = TRUE
  )
  expect_identical(core_state(con), before)
  expect_identical(load_log(con), log)
  # Before the portal is asked for the file
  testthat::local_mocked_bindings(month_resource = function(year_month) stop("looked up"))
  expect_error(load_month(202508L, dbname = dbname), "202508 is older than 202510", fixed = TRUE)
})

# Loads one source line as a month, for one practice
load_line <- function(ym, practice, dbname) {
  line <- source_line(
    YEAR_MONTH = sprintf('"%d-%02d"', ym %/% 100L, ym %% 100L),
    PRACTICE_CODE = sprintf('"%s"', practice)
  )
  csv <- local_source_file(c(source_header(), line), zip = FALSE)
  suppressMessages(load_month(ym, file = csv, dbname = dbname))
}

test_that("a practice that leaves the window keeps its row; a smaller window drops several", {
  dbname <- local_migrated_db()
  con <- local_test_db("owner", dbname = dbname)
  withr::local_envvar(PREXP_WINDOW_MONTHS = "2")
  load_line(209901L, "A00001", dbname)
  load_line(209902L, "A00002", dbname)
  expect_identical(load_line(209903L, "A00003", dbname)$dropped, 209901L)
  expect_identical(partitions(con), c("prescribing_209902", "prescribing_209903"))
  expect_identical(
    DBI::dbGetQuery(con, "
      SELECT practice_code, first_seen, last_seen FROM core.dim_practice ORDER BY 1"),
    data.frame(
      practice_code = c("A00001", "A00002", "A00003"),
      first_seen = c(209901L, 209902L, 209903L), last_seen = c(209901L, 209902L, 209903L)
    )
  )

  # Made smaller, the window drops every month beyond it, oldest first
  withr::local_envvar(PREXP_WINDOW_MONTHS = "1")
  expect_identical(load_line(209905L, "A00005", dbname)$dropped, c(209902L, 209903L))
  expect_identical(partitions(con), "prescribing_209905")
  expect_identical(load_log(con)$status, c("dropped", "dropped", "dropped", "loaded"))
  for (rollup in c("agg_presentation_month", "agg_chemical_month", "agg_practice_month")) {
    months <- DBI::dbGetQuery(con, paste0("SELECT DISTINCT year_month FROM core.", rollup))
    expect_identical(months$year_month, 209905L, label = rollup)
  }
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT 1 FROM core.dim_practice")), 4L)
})

test_that("a failure after the drop rolls it back with the rest of the swap", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "1")
  dbname <- local_loaded_db(202608L)
  con <- local_test_db("owner", dbname = dbname)
  before <- core_state(con)
  real_drop <- drop_partition
  testthat::local_mocked_bindings(drop_partition = function(con, month) {
    real_drop(con, month)
    stop("injected failure")
  })
  expect_error(suppressMessages(load_fixture(202609L, dbname)), "injected failure")
  expect_identical(core_state(con), before)
  expect_identical(load_log(con)$status, c("loaded", "failed"))
})
