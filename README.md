# prexp: Prescription Explorer

An R package containing a Shiny app for exploring a rolling twelve months of the English Prescribing Dataset (EPD) with SNOMED codes, backed by PostgreSQL 18 and running on R 4.6.1. Look up a drug, a practice or a region, pin what you find to a report with notes, and export it to PowerPoint, Word or Excel.

Work in progress: the design is in [docs/spec.md](docs/spec.md), and the work is tracked in the [milestones](https://github.com/katonometrica/prexp/milestones).

## Run locally

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
5. The app, once it exists: `docker compose --profile app up -d --build app`, then
   <http://localhost:3838>.

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

### R packages

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

### The full twelve months

The default database settings suit a laptop. For the full window (21 GB of tables and
indexes, and about 10 GB more while a month loads), set `PREXP_DB_CONFIG=full` and
`PREXP_DB_SHM_SIZE=8gb` in `.env`, then run `docker compose up -d --wait db`, which
recreates the database container with `docker/db/postgresql.full.conf`; the data stays.
That file is sized for a machine that gives Docker about 100 GB of memory and 16 CPUs,
and `docs/benchmarks.md` records the machine it was measured on. Load the window from the
RStudio console with `prexp::load_window()`: it loads the most recent published months
that are missing, oldest first, about three minutes a month on that machine.
`prexp::load_month(202609)` loads or reloads one month. The database keeps the
`PREXP_WINDOW_MONTHS` most recent months (12 by default): loading a newer month drops
the oldest. `prexp::check_plans()` then checks every app query's plan and time against
the window, and stops with an error if one fails; `docs/benchmarks.md` has the results.

### Stop and reset

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

## Data

[English Prescribing Dataset (EPD) with SNOMED Code](https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code), published by the NHS Business Services Authority under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

NHSBSA Copyright 2021-2026

What the loader relies on about the files (format, grain, measures, prescribers) is in [docs/dataset.md](docs/dataset.md).

Contains public sector information licensed under the Open Government Licence v3.0.

## Licence

Code: MIT, copyright Katonométrica, see [LICENSE.md](LICENSE.md). Data: Open Government Licence v3.0.
