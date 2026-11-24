# Database settings, connections and migrations.
#
# Settings come only from environment variables:
#
#   PREXP_DB_HOST          host name, required
#   PREXP_DB_PORT          port, default 5432
#   PREXP_DB_NAME          database, required unless a function is given one
#   PREXP_<ROLE>_USER      login name, default prexp_<role>
#   PREXP_<ROLE>_PASSWORD  password, required
#
# <ROLE> is OWNER, LOADER or APP. The migrations grant privileges to the roles
# by their default names, and default privileges only cover objects created by
# prexp_owner itself. So set a *_USER variable only to log in as a member of
# the loader or app role, and never for the owner. A member of the app role
# also needs the app role's settings (docker/db/init/02-database.sql), which a
# member does not inherit: app connections must be read-only, or they are
# refused.

# Advisory lock keys, as (namespace, key). The namespace is "prex" in ASCII.
# Advisory locks are local to each database. Give every new job its own key.
migration_lock <- c(1886545272L, 1L)

#' Connection settings for one role, from environment variables
#'
#' @param role `"app"`, `"loader"` or `"owner"`.
#' @param dbname Database name. Defaults to `PREXP_DB_NAME`.
#' @return A list with `host`, `port`, `dbname`, `user` and `password`.
#' @noRd
db_config <- function(role = c("app", "loader", "owner"), dbname = NULL) {
  role <- match.arg(role)
  prefix <- paste0("PREXP_", toupper(role))
  required <- c("PREXP_DB_HOST", "PREXP_DB_NAME", paste0(prefix, "_PASSWORD"))
  if (!is.null(dbname)) {
    required <- setdiff(required, "PREXP_DB_NAME")
  }
  values <- Sys.getenv(required, names = TRUE)
  absent <- required[!nzchar(values)]
  if (length(absent) > 0L) {
    stop("Missing environment variables: ", toString(absent), ".", call. = FALSE)
  }
  if (is.null(dbname)) {
    dbname <- values[["PREXP_DB_NAME"]]
  }
  list(
    host = values[["PREXP_DB_HOST"]],
    port = Sys.getenv("PREXP_DB_PORT", "5432"),
    dbname = dbname,
    user = Sys.getenv(paste0(prefix, "_USER"), paste0("prexp_", role)),
    password = values[[paste0(prefix, "_PASSWORD")]]
  )
}

#' Connect to the prexp database as one of its roles
#'
#' Settings come from environment variables: `PREXP_DB_HOST`, `PREXP_DB_PORT`
#' (default 5432), `PREXP_DB_NAME`, and for each role `PREXP_<ROLE>_USER`
#' (default `prexp_<role>`) and `PREXP_<ROLE>_PASSWORD`, where `<ROLE>` is
#' `APP`, `LOADER` or `OWNER`. A missing variable stops with its name, never
#' its value.
#'
#' An app connection must be read-only by the server's settings for its login
#' or database, as `prexp_app`'s role settings make it, and its login must not
#' be a superuser or able to use the schemas the loader writes. Otherwise the
#' connection is closed and `db_connect()` stops, so the app never runs with
#' the loader's or the owner's login.
#'
#' @param role `"app"` (read-only, the default), `"loader"` or `"owner"`.
#' @param dbname Database name. Defaults to `PREXP_DB_NAME`.
#' @param ... Other libpq connection parameters, as strings, for example
#'   `connect_timeout = "5"`.
#' @return A DBI connection. Close it with [DBI::dbDisconnect()].
#' @seealso [db_pool()], the app's pool of connections.
#' @export
db_connect <- function(role = c("app", "loader", "owner"), dbname = NULL, ...) {
  role <- match.arg(role)
  cfg <- db_config(role, dbname)
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = cfg$host,
    port = cfg$port,
    dbname = cfg$dbname,
    user = cfg$user,
    password = cfg$password,
    application_name = paste0("prexp-", role),
    ...
  )
  if (role == "app") {
    check_read_only(con)
  }
  con
}

#' The app's pool of read-only connections
#'
#' Opens a pool of connections as the app role, with the settings
#' [db_connect()] reads. The app creates it once per process, and each fetch
#' borrows a connection from it (spec section 5.4). Every connection the pool
#' opens is checked as [db_connect()] checks an app connection: read-only by
#' the server's settings, as the `prexp_app` role's settings make it, and not a
#' superuser's or a login that can use the loader's schemas. If one fails, it
#' is closed and the pool stops with an error of class `prexp_writable_login`.
#' The pool opens its first connection at once, even with `minSize = 0`, so
#' the app refuses to start with the loader's or the owner's login rather than
#' failing at its first query.
#'
#' Close the pool with [pool::poolClose()] when the app stops.
#'
#' @param dbname Database name. Defaults to `PREXP_DB_NAME`.
#' @param ... Other arguments to [pool::dbPool()], such as `maxSize` or
#'   `idleTimeout`, and libpq connection parameters, as strings. `onCreate` is
#'   taken: it runs the read-only check.
#' @return A pool, which DBI functions such as [DBI::dbGetQuery()] accept in
#'   place of a connection.
#' @export
db_pool <- function(dbname = NULL, ...) {
  cfg <- db_config("app", dbname)
  pool <- pool::dbPool(
    RPostgres::Postgres(),
    host = cfg$host,
    port = cfg$port,
    dbname = cfg$dbname,
    user = cfg$user,
    password = cfg$password,
    application_name = "prexp-app",
    onCreate = check_read_only,
    ...
  )
  # The checkout is its own step: as poolReturn()'s argument, its error would
  # come back wrapped by S4 method dispatch.
  tryCatch(
    {
      con <- pool::poolCheckout(pool)
      pool::poolReturn(con)
    },
    error = function(e) {
      pool::poolClose(pool)
      stop(e)
    }
  )
  pool
}

# Stops unless the connection is one the app may use:
# - read-only by default, from the server's settings for the login or the
#   database, as prexp_app's role settings make it. A client can ask for the
#   same default with PGOPTIONS or the options parameter, and then set it off
#   again, so a setting from the client does not count.
# - not a superuser's, which no privilege limits;
# - unable to use the core and raw schemas, which the loader writes.
# A refused connection is closed first: the pool calls this on each new
# connection, before handing it out, and would otherwise leak it.
check_read_only <- function(con) {
  session <- DBI::dbGetQuery(con, "
    SELECT current_user AS login, s.setting AS read_only, s.source, r.rolsuper AS superuser,
           coalesce(has_schema_privilege(to_regnamespace('core')::oid, 'USAGE'), false)
             OR coalesce(has_schema_privilege(to_regnamespace('raw')::oid, 'USAGE'), false)
             AS loader_schemas
    FROM pg_settings s
    JOIN pg_roles r ON r.rolname = current_user
    WHERE s.name = 'default_transaction_read_only'")
  problem <- if (!identical(session$read_only, "on")) {
    paste0("has default_transaction_read_only = ", session$read_only)
  } else if (!session$source %in% c("user", "database", "database user")) {
    paste0("is read-only only because the client asked (source: ", session$source, ")")
  } else if (isTRUE(session$superuser)) {
    "is a superuser"
  } else if (isTRUE(session$loader_schemas)) {
    "can use the core or raw schema, which the loader writes"
  }
  if (!is.null(problem)) {
    DBI::dbDisconnect(con)
    stop(structure(
      class = c("prexp_writable_login", "error", "condition"),
      list(
        message = paste0(
          "The app must connect read-only, but ", session$login, " ", problem,
          ". Log in as prexp_app (PREXP_APP_USER), or as a login with its settings ",
          "and privileges."
        ),
        call = NULL
      )
    ))
  }
  invisible(con)
}

#' Apply pending database migrations
#'
#' Applies the numbered SQL files in `dir` that are not yet recorded in
#' `meta.schema_migrations`, in numeric order, each in its own transaction,
#' and records each file's version and checksum. It holds an advisory lock
#' while it runs, so two runs never overlap. Before applying anything it checks
#' every file that was already applied: a changed or missing file stops it,
#' because applied files are never edited.
#'
#' Run it as the owner role: `migrate()` refuses any other login, because the
#' default privileges in the migrations only cover objects `prexp_owner`
#' creates. A migration file must not contain transaction control (`BEGIN`,
#' `COMMIT`) or commands that cannot run in a transaction, such as
#' `CREATE INDEX CONCURRENTLY`. Its row-returning statements must all return the
#' same columns, because the file is read as one result; wrap calls whose result is
#' not needed in `DO $$ BEGIN PERFORM ...; END $$`. Checksums ignore line endings
#' and a byte-order mark, so Windows and Linux checkouts of a file agree.
#'
#' @param con A single connection (not a pool) as the owner role. By default
#'   `migrate()` opens one with `db_connect("owner")` and closes it when done.
#' @param dir Folder of migration files, named like `001_schemas.sql`.
#' @return The versions applied by this call, invisibly. An empty integer
#'   vector means the database was already up to date.
#' @export
migrate <- function(con = NULL, dir = system.file("sql/migrations", package = "prexp")) {
  files <- migration_files(dir)
  if (is.null(con)) {
    con <- db_connect("owner")
    on.exit(DBI::dbDisconnect(con), add = TRUE)
  }
  # The lock, the transactions and the ledger must share one session, which a
  # pool cannot promise.
  if (!inherits(con, "PqConnection")) {
    stop("migrate() needs a single RPostgres connection, not a pool.", call. = FALSE)
  }
  login <- DBI::dbGetQuery(con, "SELECT current_user AS login")$login
  if (!identical(login, "prexp_owner")) {
    stop(
      "migrate() must run as prexp_owner, not ", login,
      ": the migrations' default privileges only cover objects prexp_owner creates.",
      call. = FALSE
    )
  }
  lock_migrations(con)
  on.exit(unlock_migrations(con), add = TRUE, after = FALSE)
  create_migration_table(con)
  pending <- pending_migrations(con, files, dir)
  for (i in seq_len(nrow(pending))) {
    apply_migration(con, pending[i, ])
  }
  invisible(pending$version)
}

# The migration files in `dir`, ordered by the number before the first
# underscore, with their SQL and its SHA-256 checksum.
migration_files <- function(dir) {
  if (!dir.exists(dir)) {
    stop("Migration folder not found: '", dir, "'.", call. = FALSE)
  }
  name <- list.files(dir, pattern = "[.]sql$")
  bad <- !grepl("^[0-9]+_.+[.]sql$", name)
  if (any(bad)) {
    stop(
      "Migration files must be named like 001_name.sql: ", toString(name[bad]),
      call. = FALSE
    )
  }
  version <- as.integer(sub("_.*$", "", name))
  repeated <- version %in% version[duplicated(version)]
  if (any(repeated)) {
    stop(
      "Migration files share a version number: ", toString(name[repeated]),
      call. = FALSE
    )
  }
  sql <- vapply(file.path(dir, name), read_migration, character(1), USE.NAMES = FALSE)
  files <- data.frame(version = version, file = name, sql = sql)
  files$checksum <- vapply(files$sql, sql_checksum, character(1), USE.NAMES = FALSE)
  files[order(files$version), , drop = FALSE]
}

# readLines() accepts LF, CRLF and CR line endings, so Windows and Linux
# checkouts of a file give the same text. A UTF-8 byte-order mark, which some
# Windows editors write, is dropped: the server would reject it, and it would
# change the checksum. The resulting text is both hashed and run.
read_migration <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (length(lines) > 0L) {
    lines[[1L]] <- sub("^\ufeff", "", lines[[1L]])
  }
  paste(lines, collapse = "\n")
}

sql_checksum <- function(sql) {
  tools::sha256sum(bytes = charToRaw(sql))
}

lock_migrations <- function(con) {
  locked <- DBI::dbGetQuery(
    con, "SELECT pg_try_advisory_lock($1, $2) AS locked",
    params = as.list(migration_lock)
  )$locked
  if (!isTRUE(locked)) {
    stop(
      "Another migrate() is running on this database. Try again when it has finished.",
      call. = FALSE
    )
  }
}

# Errors are ignored: closing the session releases the lock anyway.
unlock_migrations <- function(con) {
  try(
    DBI::dbGetQuery(con, "SELECT pg_advisory_unlock($1, $2)", params = as.list(migration_lock)),
    silent = TRUE
  )
  invisible()
}

# Checked first, because CREATE ... IF NOT EXISTS on an existing object sends
# a NOTICE, which RPostgres prints as a message on every run.
create_migration_table <- function(con) {
  found <- DBI::dbGetQuery(
    con, "SELECT to_regclass('meta.schema_migrations') IS NOT NULL AS found"
  )$found
  if (!found) {
    DBI::dbExecute(con, "
      CREATE SCHEMA IF NOT EXISTS meta;
      CREATE TABLE meta.schema_migrations (
        version integer PRIMARY KEY,
        checksum text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      );", immediate = TRUE)
  }
}

# Stops if an applied migration is missing or has changed; otherwise returns
# the files not applied yet.
pending_migrations <- function(con, files, dir) {
  applied <- DBI::dbGetQuery(
    con, "SELECT version, checksum FROM meta.schema_migrations ORDER BY version"
  )
  gone <- setdiff(applied$version, files$version)
  if (length(gone) > 0L) {
    stop(
      "Applied migrations are missing from ", dir, ": version ", toString(gone),
      ". Is this an older version of prexp?",
      call. = FALSE
    )
  }
  known <- match(files$version, applied$version)
  changed <- !is.na(known) & files$checksum != applied$checksum[known]
  if (any(changed)) {
    stop(
      "Applied migration files have changed: ", toString(files$file[changed]),
      ". Applied files are never edited: restore them and add a new migration.",
      call. = FALSE
    )
  }
  pending <- files[is.na(known), , drop = FALSE]
  # A pending file numbered below the last applied one would run after newer
  # migrations, for example when two branches merged in the other order.
  late <- pending$version < max(c(0L, applied$version))
  if (any(late)) {
    stop(
      "Pending migrations are numbered below the last applied one (",
      max(applied$version), "): ", toString(pending$file[late]),
      ". Renumber them after the last applied migration.",
      call. = FALSE
    )
  }
  pending
}

# One file in one transaction. With immediate = TRUE, RPostgres sends the file
# through the simple query protocol, which runs several statements in one call
# and stops at the first error. That mode takes no parameters, so the record of
# the migration is a separate, parameterised statement. The result is drained
# before it is cleared: clearing an unfinished result cancels the statements
# after a row-returning one (for example SELECT setval(...)).
apply_migration <- function(con, file) {
  tryCatch(
    DBI::dbWithTransaction(con, {
      run_sql_file(con, file$sql)
      DBI::dbExecute(
        con, "INSERT INTO meta.schema_migrations (version, checksum) VALUES ($1, $2)",
        params = list(file$version, file$checksum)
      )
    }),
    error = function(e) {
      stop(
        "Migration ", file$file, " failed and was rolled back: ", conditionMessage(e),
        call. = FALSE
      )
    }
  )
  message("Applied migration ", file$file)
}

run_sql_file <- function(con, sql) {
  rs <- DBI::dbSendQuery(con, sql, immediate = TRUE)
  on.exit(DBI::dbClearResult(rs), add = TRUE)
  if (!DBI::dbHasCompleted(rs)) {
    DBI::dbFetch(rs, n = -1)
  }
  invisible()
}
