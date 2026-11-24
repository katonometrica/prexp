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
  # Gone from the fact table, its table and indexes too, the rollups and the
  # window
  kept <- months[-1]
  expect_identical(partitions(con), paste0("prescribing_", kept))
  expect_identical(fact_months(con), kept)
  expect_loaded_as_oracle(con, kept)
  log <- load_log(con)
  expect_identical(log$year_month, months)
  expect_identical(log$status, c("dropped", rep("loaded", 12)))
  app <- local_test_db("app", dbname = dbname)
  expect_identical(
    DBI::dbGetQuery(app, "SELECT first_month, last_month, months FROM app.v_window"),
    data.frame(first_month = 202510L, last_month = 202609L, months = 12L)
  )
  # No dimension row is lost or re-dated. Every fixture month has the same
  # codes, so none leaves the window here; the one-line months below have some
  # that do.
  expect_identical(dimension_rows(con), dimensions)

  # Reloading the first month of the full window drops nothing
  res <- suppressMessages(load_fixture(months[2], dbname))
  expect_identical(res$dropped, integer())
  expect_identical(partitions(con), paste0("prescribing_", kept))
  expect_loaded_as_oracle(con, kept)
  expect_identical(load_log(con)$status, c("dropped", "replaced", rep("loaded", 12)))

  # The dropped month, now older than the full window, is refused, and nothing
  # changes or is recorded
  before <- core_state(con)
  log <- load_log(con)
  expect_error(
    load_fixture(months[1], dbname),
    paste(
      "202509 would be dropped as soon as it was loaded: the window keeps the most recent",
      "12 months (PREXP_WINDOW_MONTHS), from 202510 on."
    ),
    fixed = TRUE
  )
  expect_identical(core_state(con), before)
  expect_identical(load_log(con), log)
  # Before the portal is asked for the file
  testthat::local_mocked_bindings(month_resource = function(year_month) stop("looked up"))
  expect_error(
    load_month(202508L, dbname = dbname), "202508 would be dropped as soon as it was loaded",
    fixed = TRUE
  )
})

# Loads one source line as a month, for one practice; other source columns can
# be given, as in source_line()
load_line <- function(ym, practice, dbname, ...) {
  line <- source_line(
    YEAR_MONTH = sprintf('"%d-%02d"', ym %/% 100L, ym %% 100L),
    PRACTICE_CODE = sprintf('"%s"', practice), ...
  )
  csv <- local_source_file(c(source_header(), line), zip = FALSE)
  suppressMessages(load_month(ym, file = csv, dbname = dbname))
}

test_that("codes that leave the window keep their rows; a smaller window drops several", {
  dbname <- local_migrated_db()
  con <- local_test_db("owner", dbname = dbname)
  withr::local_envvar(PREXP_WINDOW_MONTHS = "2")
  # The first month's practice, chemical and presentation are its own
  load_line(
    209901L, "A00001", dbname,
    BNF_CHEMICAL_SUBSTANCE_CODE = '"0212000Y0"', BNF_CHEMICAL_SUBSTANCE = '"Simvastatin"',
    BNF_PRESENTATION_CODE = '"0212000Y0AAADAD"',
    BNF_PRESENTATION_NAME = '"Simvastatin 40mg tablets"', SNOMED_CODE = '"320000000000001"'
  )
  load_line(209902L, "A00002", dbname)
  expect_identical(load_line(209903L, "A00003", dbname)$dropped, 209901L)
  expect_identical(partitions(con), c("prescribing_209902", "prescribing_209903"))
  expect_identical(fact_months(con), c(209902L, 209903L))
  # Their rows stay, with their dates
  dimension <- function(table, code) {
    DBI::dbGetQuery(con, paste0(
      "SELECT ", code, " AS code, first_seen, last_seen FROM core.", table, " ORDER BY 1"
    ))
  }
  expect_identical(dimension("dim_practice", "practice_code"), data.frame(
    code = c("A00001", "A00002", "A00003"),
    first_seen = c(209901L, 209902L, 209903L), last_seen = c(209901L, 209902L, 209903L)
  ))
  expect_identical(dimension("dim_chemical", "chemical_code"), data.frame(
    code = c("0212000B0", "0212000Y0"), first_seen = c(209902L, 209901L),
    last_seen = c(209903L, 209901L)
  ))
  expect_identical(dimension("dim_presentation", "bnf_code"), data.frame(
    code = c("0212000B0AAABAB", "0212000Y0AAADAD"), first_seen = c(209902L, 209901L),
    last_seen = c(209903L, 209901L)
  ))

  # Made smaller, the window still holds two months until the next new one,
  # and keeps the most recent
  withr::local_envvar(PREXP_WINDOW_MONTHS = "1")
  expect_error(
    load_line(209901L, "A00001", dbname),
    paste(
      "209901 would be dropped as soon as it was loaded: the window keeps the most recent",
      "1 month (PREXP_WINDOW_MONTHS), from 209903 on."
    ),
    fixed = TRUE
  )
  # The next new month drops every month beyond it, oldest first
  expect_identical(load_line(209905L, "A00005", dbname)$dropped, c(209902L, 209903L))
  expect_identical(partitions(con), "prescribing_209905")
  expect_identical(fact_months(con), 209905L)
  expect_identical(load_log(con)$status, c("dropped", "dropped", "dropped", "loaded"))
  for (rollup in c("agg_presentation_month", "agg_chemical_month", "agg_practice_month")) {
    months <- DBI::dbGetQuery(con, paste0("SELECT DISTINCT year_month FROM core.", rollup))
    expect_identical(months$year_month, 209905L, label = rollup)
  }
  expect_identical(nrow(DBI::dbGetQuery(con, "SELECT 1 FROM core.dim_practice")), 4L)
})

test_that("a reader's lock holds up the drop, which waits, retries, and gives up unchanged", {
  withr::local_envvar(PREXP_WINDOW_MONTHS = "1")
  dbname <- local_loaded_db(202608L)
  owner <- local_test_db("owner", dbname = dbname)
  # A guard: a swap that stopped bounding its lock waits would hang here
  DBI::dbExecute(owner, "SET statement_timeout = '30s'")
  loader <- local_test_db("loader", dbname = dbname)
  staged <- stage_month(fixture_file(202609L), dbname = dbname)
  check_staged_month(loader, 202609L)
  prepare_dimensions(owner, 202609L)
  suppressMessages(build_month(owner, 202609L))
  checked <- check_month(loader, 202609L, staged$rows)
  load_id <- start_load(loader, 202609L, NA_character_, NULL)
  before <- core_state(owner)

  # An app query in an open transaction holds a lock on the oldest month's
  # partition. Attaching the new month does not wait for it; detaching the
  # oldest does.
  app <- local_test_db("app", dbname = dbname)
  DBI::dbBegin(app)
  DBI::dbGetQuery(app, "SELECT count(*) FROM app.v_practice_presentation")
  swap <- function() {
    swap_month(owner, 202609L, load_id, staged$rows, checked$loaded_rows, 1, window = 1L,
               lock_timeout = "200ms", attempts = 2L, pause = 0)
  }
  expect_message(
    expect_error(swap(), "lock timeout"),
    "waited too long for a lock (attempt 1 of 2)", fixed = TRUE
  )
  expect_identical(core_state(owner), before)
  expect_identical(load_log(owner)$status, c("loaded", "running"))

  # Once the reader has finished, the same swap goes through
  DBI::dbRollback(app)
  expect_message(dropped <- swap(), "Dropped 202608 to keep the window at 1 month", fixed = TRUE)
  expect_identical(dropped, 202608L)
  expect_identical(partitions(owner), "prescribing_202609")
  expect_identical(load_log(owner)$status, c("dropped", "loaded"))
})

test_that("a load stopped after its swap committed says the month is loaded", {
  # RPostgres turns Ctrl-C during the wait for the COMMIT's reply into an
  # error; DBI turns an interrupt condition into a NULL from dbWithTransaction()
  stops <- list(
    error = function() stop("Interrupted."),
    interrupt = function() signalCondition(structure(class = c("interrupt", "condition"), list()))
  )
  real_commit <- DBI::dbCommit
  withr::local_envvar(PREXP_WINDOW_MONTHS = "1")
  for (how in names(stops)) {
    dbname <- local_loaded_db(202608L)
    con <- local_test_db("owner", dbname = dbname)
    # Only the swap's COMMIT is cut short: its transaction has made the load
    # loaded
    cut_short <- function(conn, ...) {
      swap <- DBI::dbGetQuery(conn, "
        SELECT count(*) > 0 AS swap FROM core.load_log
        WHERE year_month = 202609 AND status = 'loaded'")$swap
      if (!swap) {
        return(real_commit(conn, ...))
      }
      DBI::dbExecute(conn, "COMMIT")
      stops[[how]]()
    }
    expect_error(
      testthat::with_mocked_bindings(
        suppressMessages(load_fixture(202609L, dbname)),
        dbCommit = cut_short, .package = "DBI"
      ),
      paste(
        "The load of 202609 was stopped after its swap committed: 202609 is loaded, and",
        "202608 left the window."
      ),
      fixed = TRUE, label = how
    )
    expect_identical(partitions(con), "prescribing_202609", label = how)
    expect_identical(load_log(con)$status, c("dropped", "loaded"), label = how)
  }
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
