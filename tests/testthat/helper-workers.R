# The background workers in tests (test-workers.R, test-export.R).

# What a daemon runs first, so that it loads the package these tests run: the
# source under development, or the installed package (as under covr)
worker_setup <- function() {
  if (pkgload::is_dev_package("prexp")) {
    bquote(pkgload::load_all(.(getNamespaceInfo("prexp", "path")), quiet = TRUE))
  } else {
    bquote(.libPaths(.(.libPaths())))
  }
}
