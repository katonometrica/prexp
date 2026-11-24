# The loader's tests assume the default window of 12 months, whatever
# PREXP_WINDOW_MONTHS the session has (.env passes it to the rstudio container,
# whose R reads it at startup); test-window.R sets its own where it needs one.
withr::local_envvar(PREXP_WINDOW_MONTHS = NA, .local_envir = testthat::teardown_env())
