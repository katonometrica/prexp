#' Version of the installed prexp package
#'
#' A placeholder from the package skeleton, kept as a smoke test of the build.
#'
#' @return The version as a string, for example `"0.0.0.9000"`.
#' @export
#' @examples
#' prexp_version()
prexp_version <- function() {
  as.character(utils::packageVersion("prexp"))
}
