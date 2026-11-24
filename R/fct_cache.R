# The app's cache of fetch results (spec section 5.4; P4-07): one cachem
# memory cache for the process, shared by every session, so a request another
# session made is not fetched again.
#
# The cache sits around the fetch functions the views call, not on the views'
# reactives with shiny::bindCache(): bindCache() keeps an error as it keeps a
# value, so one session's passing database error would be served to every
# session asking the same, until the cache dropped it. Here an error is never
# kept: the next request fetches again.

#' The app's cache
#'
#' @param max_size The most it holds, in bytes; the least recently used
#'   entries go first.
#' @return A [cachem::cache_mem()].
#' @noRd
app_cache <- function(max_size = 200 * 1024^2) {
  cachem::cache_mem(max_size = max_size)
}

#' A fetch whose results are kept in the cache
#'
#' @param cache The app's cache, from [app_cache()].
#' @param name The fetch's name, part of the key.
#' @param fetch The fetch function.
#' @param window A function giving the data window, part of the key: a month
#'   loaded changes the window, so the entries of the months before are not
#'   used again, and the cache drops them as it fills.
#' @return A function taking the fetch's arguments.
#' @noRd
cache_fetch <- function(cache, name, fetch, window) {
  force(cache)
  force(name)
  force(fetch)
  force(window)
  function(...) {
    key <- cache_key(list(name, list(...), window()))
    found <- cache$get(key)
    if (!cachem::is.key_missing(found)) {
      return(found)
    }
    value <- fetch(...)
    cache$set(key, value)
    value
  }
}

# A key for the cache: the SHA-256 of the request as JSON, in the lowercase
# hex digits cachem's keys allow
cache_key <- function(request) {
  json <- jsonlite::toJSON(
    request,
    auto_unbox = TRUE, digits = NA, na = "null", null = "null", POSIXt = "ISO8601"
  )
  tools::sha256sum(bytes = charToRaw(enc2utf8(as.character(json))))
}
