# The app's queries (spec section 5.2; P2-03): one SQL file per query in
# inst/sql/queries/. Each must prepare as the app role, which can read the app
# views and nothing else, with the parameter types the fetch functions bind.

query_files <- function() {
  list.files(system.file("sql", "queries", package = "prexp"), pattern = "[.]sql$",
             full.names = TRUE)
}

test_that("every query prepares as the app role, with the parameter types expected", {
  dbname <- local_migrated_db()
  con <- local_test_db("app", dbname = dbname)
  months <- c("integer", "integer", "integer")
  expected <- list(
    window = character(),
    search_drugs = c("text", "bigint"),
    search_practices = c("text", "bigint"),
    drug_series_chemical = months,
    drug_series_presentation = months,
    drug_presentations = months,
    practice_profile = "integer",
    practice_series = months,
    practice_top_drugs = c(months, "text", "bigint", "numeric", "integer"),
    region_comparison_chemical = months,
    region_comparison_presentation = months
  )
  files <- query_files()
  expect_setequal(sub("[.]sql$", "", basename(files)), names(expected))
  for (file in files) {
    query <- sub("[.]sql$", "", basename(file))
    sql <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    prepared <- tryCatch(
      {
        DBI::dbExecute(con, paste("PREPARE prexp_query AS", sql))
        TRUE
      },
      error = function(e) conditionMessage(e)
    )
    expect_true(isTRUE(prepared), label = paste(query, "prepares:", prepared))
    if (isTRUE(prepared)) {
      types <- DBI::dbGetQuery(con, "
        SELECT unnest(parameter_types)::text AS type FROM pg_prepared_statements
        WHERE name = 'prexp_query'")$type
      expect_identical(types, expected[[query]], label = query)
      DBI::dbExecute(con, "DEALLOCATE prexp_query")
    }
  }
})
