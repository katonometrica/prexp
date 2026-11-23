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
3. Open <http://localhost:8787> and sign in as `rstudio` with `RSTUDIO_PASSWORD`. The
   repository is at `~/prexp`.
4. In the RStudio terminal `psql` reaches the database (`db:5432`), for example
   `PGPASSWORD="$PREXP_APP_PASSWORD" psql -U prexp_app -c 'show statement_timeout'`.
   From the host it is `localhost:5432`.
5. The app, once it exists: `docker compose --profile app up -d --build app`, then
   <http://localhost:3838>.

All ports listen on 127.0.0.1 only. If one is taken, change `HOST_PORT_DB`,
`HOST_PORT_RSTUDIO` or `HOST_PORT_APP` in `.env`. For R commands from the host, run them
as the RStudio user, for example `docker compose exec -u rstudio rstudio R`.

In the RStudio container, R reads the `PREXP_*` settings from the container environment
when it starts (rocker copies them into `Renviron.site`), so setting a variable on the
command line does not reach R. To work on another database, pass it as an argument, for
example `prexp::migrate(prexp::db_connect("owner", dbname = "prexp_test"))`.

### R packages

`renv.lock` lists every package version. The images install exactly those versions into
R's site library, and renv is never switched on inside a container.

- To add a package: add it to `DESCRIPTION` (`usethis::use_package("pkg")`, or
  `usethis::use_package("pkg", "Suggests")` for test and CI tools), install it with
  `install.packages("pkg")`, then run
  `renv::snapshot(project = "~/prexp", library = .libPaths(), prompt = FALSE)`. Commit
  `DESCRIPTION` and `renv.lock` together and rebuild: `docker compose build`. If
  `renv::sysreqs()` lists a system library that `docker/Dockerfile` lacks, add it in the
  same pull request.
- devtools, usethis and roxygen2 come with the development image and are not in
  `renv.lock`.

### Stop and reset

- `docker compose down` stops everything and keeps all data.
- `docker compose down -v` also deletes the database and the downloaded source files.
  The next `up` creates a new database.
- To reset only the database: `docker compose down`, then `docker volume rm prexp_pgdata`,
  then `docker compose up -d --wait`.

## Data

[English Prescribing Dataset (EPD) with SNOMED Code](https://opendata.nhsbsa.net/dataset/english-prescribing-dataset-epd-with-snomed-code), published by the NHS Business Services Authority under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).

NHSBSA Copyright 2021-2026

Contains public sector information licensed under the Open Government Licence v3.0.

## Licence

Code: MIT, copyright Katonométrica, see [LICENSE.md](LICENSE.md). Data: Open Government Licence v3.0.
