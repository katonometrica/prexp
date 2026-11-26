# Development

How to work on prexp: the development stack, R packages, the tests and the browser flows, and the full twelve months. To only try the app, the [README](../README.md)'s one-command demo is enough.

## The development stack

Everything runs in Docker: PostgreSQL 18 and RStudio Server on R 4.6.1. R does not need
to be installed on the host. On Windows use Docker Desktop with the WSL 2 backend; the
repository can stay on a Windows drive, because the database and the downloaded data live
in Docker volumes, not in the bind mount.

1. Copy `.env.example` to `.env` and replace every `change-me` with a random string of
   letters and digits, for example the output of `openssl rand -hex 24`. `.env` is
   ignored by git; never commit it.
2. From the repository root run `docker compose up -d --build --wait`. The first build
   downloads R packages and RStudio and takes several minutes.
3. Open <http://localhost:8787>. RStudio opens without a sign-in, as user `rstudio`.
   Open the project with File > Open Project > `~/prexp/prexp.Rproj`.
4. In the RStudio terminal `psql` reaches the database (`db:5432`), for example
   `PGPASSWORD="$PREXP_APP_PASSWORD" psql -U prexp_app -c 'show statement_timeout'`.
   From the host it is `localhost:5432`.
5. The app, built from your working tree: `docker compose --profile app up -d --build app`,
   then <http://localhost:3838>.

All ports listen on 127.0.0.1 only. If one is taken, change `HOST_PORT_DB`,
`HOST_PORT_RSTUDIO` or `HOST_PORT_APP` in `.env`. For R commands from the host, run them
as the RStudio user, for example `docker compose exec -u rstudio rstudio R`.

**No sign-in, and what that means.** Other machines cannot reach RStudio, but any
program on this machine can, including a malicious web page in your browser through a
DNS-rebinding attack (most current browsers block this). RStudio holds the database
passwords and can write to the repository. Stop it when you are not using it
(`docker compose stop rstudio`), or bring the sign-in back: in `compose.yaml`, replace
`DISABLE_AUTH: "true"` with `PASSWORD: ${RSTUDIO_PASSWORD}` and set `RSTUDIO_PASSWORD`
in `.env`.

**On Linux** (Docker Engine, not Docker Desktop), set `HOST_UID` and `HOST_GID` in `.env`
to the output of `id -u` and `id -g`, so RStudio can write to the bind-mounted
repository.

In the RStudio container, R reads the `PREXP_*` settings from the container environment
when it starts (rocker copies them into `Renviron.site`), so setting a variable on the
command line does not reach R. To work on another database, pass it as an argument, for
example `prexp::migrate(prexp::db_connect("owner", dbname = "prexp_test"))`.

## R packages

`renv.lock` lists every package version. The images install exactly those versions into
R's site library, and renv is never switched on inside a container.

- To add a package, with the project open: install it with `install.packages("pkg")`,
  add it to `DESCRIPTION` with `usethis::use_package("pkg")` (or
  `usethis::use_package("pkg", "Suggests")` for test and CI tools), then run
  `renv::snapshot(project = "~/prexp", library = .libPaths(), prompt = FALSE)`. Commit
  `DESCRIPTION` and `renv.lock` together and rebuild: `docker compose build`. If
  `renv::sysreqs()` lists a system library that `docker/Dockerfile` lacks, add it in the
  same pull request.
- devtools, usethis and roxygen2 come with the development image and are not in
  `renv.lock`.

## Tests

From the project in RStudio, `devtools::test()` runs the suite. The tests connect to the
stack's `prexp_test` database, make the databases they need, and drop them at the end;
with no database reachable, the tests that need one are skipped, each saying why. CI runs
the suite under coverage (`covr::package_coverage(type = "tests")`) and fails below 85%,
or if any function has no coverage.

## End-to-end flows

`tests/testthat/e2e-flows.R` drives the app in Google Chrome, which the development
image includes, on the fixture database. The test suite leaves it out. To run it, from
the RStudio terminal in `~/prexp`, install the package, which the app's background
workers load, then run the file (`NOT_CRAN=true`, or shinytest2 skips every flow):

```sh
R CMD INSTALL --no-docs .
NOT_CRAN=true Rscript -e 'testthat::test_file("tests/testthat/e2e-flows.R",
  package = "prexp", load_package = "installed")'
```

## The full twelve months

The default database settings suit a laptop. For the full window (21 GB of tables and
indexes, and about 10 GB more while a month loads), set `PREXP_DB_CONFIG=full` and
`PREXP_DB_SHM_SIZE=8gb` in `.env`, then run `docker compose up -d --wait db`, which
recreates the database container with `docker/db/postgresql.full.conf`; the data stays.
That file is sized for a machine that gives Docker about 100 GB of memory and 16 CPUs,
and `docs/benchmarks.md` records the machine it was measured on. Production needs far
less: it runs the same twelve months on 4 CPUs and 15 GB, with
`docker/db/postgresql.prod.conf` ([docs/server.md](server.md)). Load the window from the
RStudio console with `prexp::load_window()`: it loads the most recent published months
that are missing, oldest first, about three minutes a month on that machine.
`prexp::load_month(202609)` loads or reloads one month. The database keeps the
`PREXP_WINDOW_MONTHS` most recent months (12 by default): loading a newer month drops
the oldest. `prexp::check_plans()` then checks every app query's plan and time against
the window, and stops with an error if one fails; `docs/benchmarks.md` has the results.

## Stop and reset

- `docker compose down` stops everything and keeps all data.
- `docker compose down -v` also deletes the database and the downloaded source files.
  The next `up` creates a new database.
- To reset only the database: `docker compose down`, then `docker volume rm prexp_pgdata`,
  then `docker compose up -d --wait`.
- The passwords in `.env` are set when the database volume is created. After changing
  them, first run `docker compose up -d`, which recreates the containers with the new
  values, then apply them to the existing database with
  `docker compose exec db bash /docker-entrypoint-initdb.d/01-roles.sh`. In Git Bash,
  prefix that command with `MSYS_NO_PATHCONV=1`, or Git Bash rewrites the path.

