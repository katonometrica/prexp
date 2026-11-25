# The app for the end-to-end flows (e2e-flows.R): the installed package, as
# the app image runs it, with its background workers, on the database that
# PREXP_E2E_DB names. Not PREXP_DB_NAME: in the dev container every new R
# process takes that from Renviron.site, which rocker writes from the
# container's environment, so the app would open the database of the stack.
# Through `::`, not library(): shinytest2 makes library() load the package
# from its source, which starts no workers.
dbname <- Sys.getenv("PREXP_E2E_DB")
if (!nzchar(dbname)) {
  stop("Set PREXP_E2E_DB to the database the flows run on.", call. = FALSE)
}
Sys.setenv(PREXP_DB_NAME = dbname)
prexp::run_app()
