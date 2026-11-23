# Helpers for the loader's tests: fixture hashes, staging rows, reading the
# loaded tables back as text, and comparing them with the oracle.

# The SHA-256 of a fixture month's CSV, as the portal publishes it for a month
fixture_sha256 <- function(ym) {
  dir <- withr::local_tempdir()
  csv <- utils::unzip(fixture_file(ym), exdir = dir, unzip = "internal")
  unname(tools::sha256sum(csv))
}
