# Helpers for the tests of the app's queries and fetch functions

# The id of a chemical, presentation or practice code
id_of <- function(con, kind, code) {
  sql <- switch(kind,
    chemical = "SELECT chemical_id FROM app.v_chemical WHERE chemical_code = $1",
    presentation = "SELECT presentation_id FROM app.v_presentation WHERE bnf_code = $1",
    practice = "SELECT practice_id FROM app.v_practice WHERE practice_code = $1"
  )
  DBI::dbGetQuery(con, sql, params = list(code))[[1]]
}
