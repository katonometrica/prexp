# The fetch timing log is off for the test run (spec section 5.4); test-log.R
# turns it on where it tests it.
withr::local_envvar(PREXP_LOG = "off", .local_envir = testthat::teardown_env())
