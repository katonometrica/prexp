# The report's pure functions (P5-01): items added, removed, moved and noted,
# the report's limits, each view's parameters, the link's encoding, and
# clamping to the data window.

report_window <- tibble::tibble(
  first_month = 202510L, last_month = 202609L, months = 12L, loaded_at = Sys.time()
)

drug_params <- function(...) {
  utils::modifyList(list(
    level = "chemical", id = 57L, code = "0212000B0", label = "Atorvastatin",
    months = c(202510L, 202609L), measure = "items"
  ), list(...))
}

practice_params <- function(...) {
  utils::modifyList(list(
    id = 12L, code = "N81655", label = "THE SURGERY", months = c(202601L, 202609L),
    measure = "nic"
  ), list(...))
}

region_params <- function(...) {
  utils::modifyList(list(
    level = "presentation", id = 300L, code = "0212000B0AAABAB",
    label = "Atorvastatin 20mg tablets", months = c(202510L, 202609L),
    measure = "total_quantity"
  ), list(...))
}

# Text compressed and written as a link is, for links this app did not make
pack <- function(x) {
  raw <- memCompress(if (is.raw(x)) x else charToRaw(x), type = "gzip")
  sub("=+$", "", gsub("[\r\n]", "", chartr("+/", "-_", jsonlite::base64_enc(raw))))
}

# A link of these items, written as JSON
packed <- function(items) {
  pack(as.character(jsonlite::toJSON(
    list(v = 1L, items = items),
    auto_unbox = TRUE, null = "null", na = "null"
  )))
}

# A link's JSON, before it is packed
packed_json <- function(items) {
  as.character(jsonlite::toJSON(list(v = 1L, items = items), auto_unbox = TRUE))
}

link_item <- function(...) {
  utils::modifyList(list(view = "drug", params = drug_params(), note = ""), list(...))
}

# A link whose one item has `json` written in place of its view
with_view <- function(json) {
  params <- jsonlite::toJSON(drug_params(), auto_unbox = TRUE)
  pack(paste0(
    "{\"v\":1,\"items\":[{\"view\":", json, ",\"params\":", params, ",\"note\":\"\"}]}"
  ))
}

# A link whose one item has `note` written as its note's JSON string
with_note <- function(note) {
  params <- jsonlite::toJSON(drug_params(), auto_unbox = TRUE)
  pack(paste0(
    "{\"v\":1,\"items\":[{\"view\":\"drug\",\"params\":", params, ",\"note\":\"", note, "\"}]}"
  ))
}

# English prose: 500 characters of R's own copy of the GPL, a different part
# for each note
prose <- function(i) {
  text <- paste(readLines(file.path(R.home("share"), "licenses", "GPL-2")), collapse = " ")
  text <- gsub(" +", " ", gsub("[[:cntrl:]]", " ", text))
  substr(text, 1000L + (i - 1L) * 600L, 1000L + (i - 1L) * 600L + 499L)
}

test_that("items are added with their parameters checked, in order, each with an id of its own", {
  spec <- new_report()
  expect_identical(spec, list(items = list(), next_id = 1L))
  # Months and ids given as doubles come back as integers
  spec <- report_add(spec, "drug", drug_params(id = 57, months = c(202510, 202609)))
  spec <- report_add(spec, "practice", practice_params())
  spec <- report_add(spec, "region", region_params())
  expect_identical(item_ids(spec), 1:3)
  first <- spec$items[[1]]
  expect_identical(names(first), c("id", "view", "params", "note", "clamped"))
  expect_identical(first$view, "drug")
  expect_identical(first$params, drug_params())
  expect_identical(first$note, "")
  expect_false(first$clamped)
  expect_identical(
    names(spec$items[[2]]$params), c("id", "code", "label", "months", "measure")
  )
  # No id is given twice, even after its item is removed
  spec <- report_add(report_remove(spec, 2L), "drug", drug_params())
  expect_identical(item_ids(spec), c(1L, 3L, 4L))
  spec <- report_add(report_remove(spec, 4L), "drug", drug_params())
  expect_identical(item_ids(spec), c(1L, 3L, 5L))
  for (id in item_ids(spec)) {
    spec <- report_remove(spec, id)
  }
  expect_identical(item_ids(report_add(spec, "drug", drug_params())), 6L)
})

test_that("a report holds at most 15 items", {
  spec <- new_report()
  for (i in 1:15) {
    spec <- report_add(spec, "drug", drug_params())
  }
  expect_length(spec$items, 15L)
  expect_error(
    report_add(spec, "drug", drug_params()), "at most 15 items",
    class = "prexp_report_limit"
  )
})

test_that("a note holds at most 500 characters of UTF-8 text, with tabs and line breaks", {
  spec <- report_add(new_report(), "drug", drug_params())
  spec <- report_set_note(spec, 1L, strrep("a", 500L))
  expect_identical(nchar(spec$items[[1]]$note), 500L)
  # Characters, not bytes: 500 of two bytes each fit
  accented <- strrep(intToUtf8(0xe9), 500L)
  expect_identical(report_set_note(spec, 1L, accented)$items[[1]]$note, accented)
  expect_identical(report_set_note(spec, 1L, "a\tb\nc\r\nd")$items[[1]]$note, "a\tb\nc\r\nd")
  expect_error(
    report_set_note(spec, 1L, strrep("a", 501L)), "at most 500 characters; this one has 501",
    class = "prexp_report_limit"
  )
  refused <- function(note, message) {
    expect_error(report_set_note(spec, 1L, note), message, class = "prexp_invalid_argument")
  }
  refused(NA_character_, "`note`")
  refused(c("a", "b"), "`note`")
  refused(1, "`note`")
  refused(rawToChar(as.raw(c(0x61, 0xff))), "UTF-8")
  # No character the exports' XML cannot hold
  for (bad in c(1L, 8L, 11L, 27L, 31L, 127L, 133L, 159L, 65534L, 65535L)) {
    refused(paste0("a", intToUtf8(bad), "b"), "control characters")
  }
  expect_error(report_set_note(spec, 2L, "x"), "no item 2", class = "prexp_invalid_argument")
})

test_that("items move up and down, stopping at either end, and are removed", {
  spec <- new_report()
  for (i in 1:3) {
    spec <- report_add(spec, "drug", drug_params())
  }
  expect_identical(item_ids(report_move(spec, 3L, -1)), c(1L, 3L, 2L))
  expect_identical(item_ids(report_move(spec, 1L, 1L)), c(2L, 1L, 3L))
  expect_identical(item_ids(report_move(spec, 1L, 2L)), c(2L, 3L, 1L))
  expect_identical(item_ids(report_move(spec, 1L, -1L)), 1:3)
  expect_identical(item_ids(report_move(spec, 3L, 5L)), 1:3)
  # Past the integers too
  expect_identical(item_ids(report_move(spec, 1L, 1e10)), c(2L, 3L, 1L))
  expect_identical(item_ids(report_move(spec, 3L, -3e9)), c(3L, 1L, 2L))
  expect_identical(item_ids(report_move(spec, 2L, .Machine$integer.max)), c(1L, 3L, 2L))
  expect_identical(item_ids(report_remove(spec, 2L)), c(1L, 3L))
  emptied <- report_remove(report_remove(report_remove(spec, 1L), 2L), 3L)
  expect_identical(emptied, list(items = list(), next_id = 4L))
  for (by in list(0.5, NA, Inf, -Inf, "1", c(1, 1))) {
    expect_error(report_move(spec, 1L, by), "`by`", class = "prexp_invalid_argument")
  }
  expect_error(report_move(spec, 9L, 1L), "no item 9", class = "prexp_invalid_argument")
  expect_error(report_remove(spec, "x"), "`id`", class = "prexp_invalid_argument")
})

test_that("each view takes its own parameters, and checks their values", {
  expect_identical(validate_item("region", region_params())$params, region_params())
  expect_identical(validate_item("practice", practice_params())$view, "practice")
  refused <- function(view, params, message) {
    expect_error(validate_item(view, params), message, class = "prexp_invalid_argument")
  }
  # Missing, extra or unnamed parameters
  refused(
    "drug", drug_params(level = NULL),
    "A drug item takes level, id, code, label, months, measure; it was given id, code"
  )
  refused("practice", c(practice_params(), list(level = "chemical")), "A practice item takes id")
  refused("drug", list(), "given none")
  refused("drug", list(1, 2), "named list")
  refused("drug", "x", "named list")
  refused("drug", c(drug_params(), list(id = 1L)), "it was given")
  refused("variation", drug_params(), "`view`")
  # Values
  refused("drug", drug_params(level = "bnf"), "`level`")
  refused("drug", drug_params(measure = "total_quantity"), "only valid for a single presentation")
  refused("practice", practice_params(measure = "adq_usage"), "`measure`")
  refused("drug", drug_params(id = 0), "`id`")
  refused("drug", drug_params(months = c(202609L, 202510L)), "`months`")
  refused("drug", drug_params(code = "02-12"), "`code`")
  refused("drug", drug_params(code = 212), "`code`")
  for (label in list(
    "", strrep("a", 201L), "a\nb", NA_character_, 1, intToUtf8(c(97L, 65535L)),
    intToUtf8(c(97L, 65534L)), intToUtf8(c(97L, 133L))
  )) {
    refused("drug", drug_params(label = label), "`label`")
  }
  expect_identical(
    validate_item("drug", drug_params(label = strrep("a", 200L)))$params$label, strrep("a", 200L)
  )
  # A missing code stays missing
  expect_identical(validate_item("drug", drug_params(code = NA))$params$code, NA_character_)
})

test_that("a report's link brings back the same report, its items numbered from 1", {
  spec <- new_report()
  spec <- report_add(spec, "drug", drug_params())
  spec <- report_add(spec, "practice", practice_params(code = NA))
  spec <- report_add(spec, "region", region_params())
  spec <- report_set_note(spec, 1L, "Statins rose in winter.\nCheck again in March.")
  note <- paste0("Caf", intToUtf8(0xe9), " \"quotes\" & <tags> \\ back \\u0000 \t tab")
  spec <- report_set_note(spec, 3L, note)
  link <- encode_report(spec)
  expect_match(link, "^[A-Za-z0-9_-]+$")
  expect_identical(decode_report(link), spec)
  expect_identical(decode_report(encode_report(new_report())), new_report())
  # Without the practice the ids are 1 and 3, and the link numbers them 1 and
  # 2: an id names an item only within a session
  spec <- report_remove(spec, 2L)
  opened <- decode_report(encode_report(spec))
  expect_identical(item_ids(opened), 1:2)
  expect_identical(opened$next_id, 3L)
  expect_identical(
    lapply(opened$items, function(item) item[c("view", "params", "note")]),
    lapply(spec$items, function(item) item[c("view", "params", "note")])
  )
  # The clamped mark stays out of the link
  clamped <- clamp_report(spec, tibble::tibble(first_month = 202601L, last_month = 202609L))
  expect_true(clamped$items[[1]]$clamped)
  expect_false(decode_report(encode_report(clamped))$items[[1]]$clamped)
})

test_that("a link that is not a whole, valid report is refused whole", {
  link <- encode_report(report_add(new_report(), "drug", drug_params()))
  refused <- function(text, message) {
    expect_error(decode_report(text), message, class = "prexp_invalid_report")
  }
  refused(substr(link, 1L, nchar(link) - 10L), "cut short")
  refused(paste0(link, "!"), "characters that base64url does not use")
  refused("", "cut short")
  refused(NA_character_, "one string")
  refused(c(link, link), "one string")
  refused(1, "one string")
  refused(strrep("A", 7501L), "longer than 7500 characters")
  # Compressed, but not this app's report
  refused(pack("not json"), "this app's format")
  refused(pack(as.raw(c(0xff, 0xfe, 0x7b))), "this app's format")
  refused(pack("{\"v\":2,\"items\":[]}"), "this app's format")
  refused(pack("{\"v\":1}"), "this app's format")
  refused(pack("{\"v\":1,\"items\":[],\"more\":1}"), "this app's format")
  refused(pack("[1,2]"), "this app's format")
  # Nested deeper than a report: refused before it is read
  refused(pack("{\"v\":1,\"items\":[[[[[[]]]]]]}"), "this app's format")
  # A NUL byte, or an escape of U+0000 or of half a surrogate pair, which R
  # strings cannot hold: refused, not cut short or changed
  refused(pack(as.raw(c(0x7b, 0x00, 0x7d))), "this app's format")
  refused(pack(c(charToRaw("{\"v\":1,\"items\":[]}"), as.raw(0L))), "this app's format")
  refused(with_note("a\\u0000b"), "this app's format")
  refused(with_note("\\ud800"), "this app's format")
  refused(with_note("\\\\\\uDC00"), "this app's format")
  # The same written as text, a backslash then u0000, is a note like any other
  expect_identical(decode_report(with_note("a\\\\u0000b"))$items[[1]]$note, "a\\u0000b")
  # Small, but more than 65,536 bytes once unpacked
  refused(pack(strrep(" ", 70000L)), "unpacks to more than 65536 bytes")
  # One item that fails a check fails the whole link
  expect_identical(decode_report(packed(list(link_item())))$items[[1]]$params, drug_params())
  bad <- link_item(params = drug_params(level = "x"))
  refused(packed(list(link_item(), bad)), "not valid: `level`")
  refused(packed(list(link_item(note = strrep("a", 501L)))), "limits: A note holds")
  refused(packed(rep(list(link_item()), 16L)), "limits: A report holds")
  refused(packed(list(c(link_item(), list(more = 1L)))), "a view, parameters and a note")
  refused(packed(list(c(link_item(), list(id = 1L)))), "a view, parameters and a note")
  refused(packed(list(link_item(note = NULL))), "a view, parameters and a note")
  refused(packed(list(5L)), "a view, parameters and a note")
  refused(packed(list(link_item(params = "x"))), "named list")
  # Months nested a level deeper are deeper than a report
  months <- drug_params(months = list(list(202510L), 202609L))
  refused(packed(list(link_item(params = months))), "this app's format")
})

test_that("a link nested thousands deep is refused at once, and cannot crash the app", {
  deep <- function(n) paste0(strrep("[", n), "1", strrep("]", n))
  started <- Sys.time()
  expect_error(
    decode_report(with_view(deep(3000L))), "this app's format",
    class = "prexp_invalid_report"
  )
  expect_lt(as.numeric(Sys.time() - started, units = "secs"), 1)
  # The checks themselves describe a list by its shape, never printing it all
  nested <- 1
  for (i in 1:3000) {
    nested <- list(nested)
  }
  started <- Sys.time()
  for (check in list(function(x) validate_choice(x, "drug", "view"), validate_id)) {
    expect_error(check(nested), "a list of length 1", class = "prexp_invalid_argument")
  }
  expect_lt(as.numeric(Sys.time() - started, units = "secs"), 1)
  expect_identical(json_depth("{\"a\":\"[[[{{{\",\"b\":[1,{\"c\":\"\\\"]\"}]}"), 3L)
  expect_identical(json_depth("1"), 0L)
})

test_that("a link stays within 7,500 characters: prose fits, a note or pin past it is refused", {
  labels <- c(
    "Atorvastatin", "Metformin hydrochloride", "Amoxicillin", "Omeprazole", "Sertraline",
    "Levothyroxine sodium", "Ramipril", "Lansoprazole", "Amlodipine", "Simvastatin",
    "ST WERBURGH'S MEDICAL PRACTICE HOMELESS", "Colecalciferol", "Salbutamol",
    "Wound Management & Other Dressings", "Bisoprolol fumarate"
  )
  spec <- new_report()
  for (i in 1:15) {
    view <- c("drug", "practice", "region")[(i - 1L) %% 3L + 1L]
    params <- switch(view,
      drug = drug_params(id = 1000L + i, label = labels[i]),
      practice = practice_params(id = 5000L + i, code = sprintf("N%05d", i), label = labels[i]),
      region = region_params(id = 9000L + i, label = labels[i])
    )
    spec <- report_add(spec, view, params)
    spec <- report_set_note(spec, i, prose(i))
  }
  expect_true(all(vapply(spec$items, function(item) nchar(item$note), 1L) == 500L))
  link <- encode_report(spec)
  expect_lt(nchar(link), 7500L)
  expect_identical(decode_report(link), spec)
  # Notes that compress poorly reach the link's limit first: the note that
  # would pass it is refused, and every report kept has a link that fits
  refusals <- 0L
  for (i in 1:15) {
    symbols <- withr::with_seed(i, intToUtf8(sample(0x4E00:0x9FFF, 500L, replace = TRUE)))
    noted <- tryCatch(report_set_note(spec, i, symbols), prexp_report_limit = function(e) e)
    if (inherits(noted, "prexp_report_limit")) {
      expect_match(conditionMessage(noted), "shorten its notes", fixed = TRUE)
      refusals <- refusals + 1L
    } else {
      spec <- noted
    }
    expect_lte(nchar(encode_report(spec)), 7500L)
  }
  expect_gt(refusals, 0L)
  # A pin that would pass it is refused too, here with a link of at most
  # 200 characters
  local_mocked_bindings(report_limits = function() {
    list(items = 15L, note = 500L, label = 200L, link = 200L, json = 65536L)
  })
  small <- new_report()
  repeat {
    pinned <- tryCatch(
      report_add(small, "drug", drug_params(id = 100L + length(small$items))),
      prexp_report_limit = function(e) e
    )
    if (inherits(pinned, "prexp_report_limit")) break
    small <- pinned
  }
  expect_match(conditionMessage(pinned), "more than the 200 a link can have", fixed = TRUE)
  expect_gt(length(small$items), 0L)
  expect_lt(length(small$items), 15L)
  expect_lte(nchar(encode_report(small)), 200L)
})

test_that("clamping moves each item's months into the window, and marks the ones it moves", {
  spec <- new_report()
  spec <- report_add(spec, "drug", drug_params(months = c(202510L, 202609L)))
  spec <- report_add(spec, "drug", drug_params(months = c(202401L, 202512L)))
  spec <- report_add(spec, "practice", practice_params(months = c(202601L, 202612L)))
  spec <- report_add(spec, "region", region_params(months = c(202301L, 202306L)))
  spec <- report_add(spec, "region", region_params(months = c(202701L, 202703L)))
  clamped <- clamp_report(spec, report_window)
  expect_identical(
    lapply(clamped$items, function(item) item$params$months),
    list(
      c(202510L, 202609L), c(202510L, 202512L), c(202601L, 202609L),
      c(202510L, 202609L), c(202510L, 202609L)
    )
  )
  expect_identical(
    vapply(clamped$items, function(item) item$clamped, TRUE), c(FALSE, TRUE, TRUE, TRUE, TRUE)
  )
  # Nothing else changes, and clamping again changes nothing
  expect_identical(clamped$items[[2]]$params[-5L], spec$items[[2]]$params[-5L])
  expect_identical(clamp_report(clamped, report_window), clamped)
  # No months loaded: the report as it is
  expect_identical(clamp_report(spec, report_window[0L, ]), spec)
  expect_identical(clamp_report(spec, NULL), spec)
  expect_identical(
    clamp_report(spec, tibble::tibble(first_month = NA_integer_, last_month = NA_integer_)), spec
  )
})

test_that("a link that unpacks to a URL or a file's path is refused, never fetched or read", {
  started <- Sys.time()
  expect_error(
    decode_report(pack("http://127.0.0.1:9/report.json")), "this app's format",
    class = "prexp_invalid_report"
  )
  # A file holding a report: its path is not a report
  held <- withr::local_tempfile(fileext = ".json")
  writeLines(packed_json(list(link_item())), held)
  expect_error(decode_report(pack(held)), "this app's format", class = "prexp_invalid_report")
  expect_lt(as.numeric(Sys.time() - started, units = "secs"), 1)
})

test_that("invalid JSON is refused at once: unclosed strings, comments, a byte-order mark", {
  started <- Sys.time()
  quotes <- paste0("\"", strrep("\\\"", 32000L))
  expect_error(decode_report(pack(quotes)), "this app's format", class = "prexp_invalid_report")
  expect_lt(as.numeric(Sys.time() - started, units = "secs"), 1)
  valid <- packed_json(list(link_item()))
  for (json in list(paste0("/*x*/", valid), paste0(valid, "//"), paste0(valid, "/*\"*/"))) {
    expect_error(decode_report(pack(json)), "this app's format", class = "prexp_invalid_report")
  }
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(valid))
  expect_error(decode_report(pack(bom)), "this app's format", class = "prexp_invalid_report")
  expect_identical(decode_report(pack(valid))$items[[1]]$params, drug_params())
})

test_that("a move that would make the link too long is refused: order changes compression", {
  spec <- new_report()
  for (i in 1:15) {
    spec <- report_add(spec, "drug", drug_params(id = 100L + i, label = paste("Drug", i)))
    symbols <- withr::with_seed(i, intToUtf8(sample(0x4E00:0x9FFF, 40L, replace = TRUE)))
    spec <- report_set_note(spec, i, paste(substr(prose(i), 1L, 459L), symbols))
  }
  # A move that makes this report's link longer
  base <- nchar(encode_report(spec))
  moves <- expand.grid(id = item_ids(spec), by = c(-14L, -1L, 1L, 14L))
  lengths <- vapply(seq_len(nrow(moves)), function(i) {
    nchar(encode_report(report_move(spec, moves$id[i], moves$by[i])))
  }, 1L)
  expect_true(any(lengths > base))
  longer <- moves[which.max(lengths), ]
  # With the link's limit at this report's length, that move is refused and
  # the report kept as it was; a move that shortens it is not
  local_mocked_bindings(report_limits = function() {
    list(items = 15L, note = 500L, label = 200L, link = base, json = 65536L)
  })
  expect_error(
    report_move(spec, longer$id, longer$by), "more than the", class = "prexp_report_limit"
  )
  shorter <- moves[which.min(lengths), ]
  expect_lte(nchar(encode_report(report_move(spec, shorter$id, shorter$by))), base)
})
