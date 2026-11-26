# Prescription Explorer: technical spec

How Prescription Explorer is built, at the level needed to write and work tickets. The goal and scope come first; the tickets are this repository's GitHub issues, one milestone per phase (section 9).

The source data's format and grain were checked in phase 0; the findings are in [dataset.md](dataset.md).

## Goal and scope

Prescription Explorer is an R Shiny app, built as the R package `prexp`, for exploring a rolling twelve months of NHS England prescribing data, about 220 million source rows (about 113 million after aggregation), with lookups answered in under 300 ms. Users explore through guided views, pin what they find, add notes, and export a report as PowerPoint, Word or Excel. The data is the English Prescribing Dataset (EPD) with SNOMED Code from the NHS Business Services Authority (NHSBSA), published monthly under the Open Government Licence 3.0.

**In scope for v1**

- Drug lookup: search by name or BNF code, then monthly items, quantity and cost
- Practice lookup: search by name or code, then top drugs and monthly totals
- Regional comparison of one drug across regions
- Report builder: pin views, add a note to each, reorder, and export (section 5.5)
- Shareable link that restores the selections, pinned items and notes
- CSV export of the current view

**Out of scope for v1**

- Econometric models. v2 starts with the practice variation model (section 10), on the same schema
- Free-form pivots or ad hoc analysis. Exploration is limited to the guided views, so every query stays on an index or a rollup
- Logins, user accounts and reports saved on the server. Reports persist only through the shareable link

**Targets**

| Measure | Target |
| --- | --- |
| Lookup latency, p95, warm database | Under 300 ms |
| Each app query in psql | Under 50 ms, no sequential scan on the fact table |
| Report export, any format | Under 10 s, run as a background task |
| Test coverage | 85% or more, enforced in CI |
| Rows loaded | About 220 million source rows for twelve months, about 113 million after aggregation |

## 1. Versions

| Component | Version | Notes |
| --- | --- | --- |
| R | 4.6.1 | The same version in development, CI and production |
| Base image | `rocker/r-ver:4.6.1`, pinned by digest | Ubuntu 24.04 (noble). Pulled from `ghcr.io/rocker-org/r-ver`, the same image as on Docker Hub. Frozen since R 4.6.2 came out (29 October 2026), so the base stage runs `apt-get upgrade` for operating system fixes. Moving to R 4.6.2 also moves to Ubuntu 26.04, which changes the package repository URLs and some apt package names |
| RStudio Server (development only) | 2026.10.1+239 | Rocker's pin for R 4.6.1, added on top of the base image with the rocker install script. Browser IDE at `localhost:8787` |
| PostgreSQL | 18.7, pinned by digest | Official `postgres:18.7-trixie` image, the same reference in Compose and CI. PostgreSQL 19 came out on 19 November 2026; staying on 18 (supported to November 2030) is deliberate, and since the database is rebuilt from source an upgrade is a rebuild. `pg_trgm` ships with it |
| PostgreSQL client | 18 | `psql` from the PostgreSQL (PGDG) apt repository, because Ubuntu's own is version 16. PGDG's main component now ships libpq 19, so libpq is pinned to 18 |
| R packages | Locked with `renv` | Explicit snapshot of `DESCRIPTION`, Suggests included. Installed as Linux binaries from the Posit Package Manager snapshot of 2026-10-28 into R's site library. renv records versions; it is never activated inside a container |
| Package name | `prexp` | Used for the package, roles, database and images |

## 2. Docker setup

### 2.1 One Dockerfile, four stages

`docker/Dockerfile`, multi-stage, so development, CI and production run the same R and the same packages.

| Stage | Based on | Adds | Used by |
| --- | --- | --- | --- |
| `base` | `rocker/r-ver:4.6.1` | `apt-get upgrade`; system libraries (`libpq-dev`, `libxml2-dev`, `libfontconfig-dev`, `libharfbuzz-dev`, `libfribidi-dev`, `libpng-dev`, `libfreetype-dev`, `libuv1-dev`, `libcurl4-openssl-dev`, `libssl-dev`, `libjpeg-dev`, `libtiff-dev`, `libwebp-dev`); fonts (`fonts-liberation`, `fonts-dejavu-core`); `postgresql-client-18`; `unzip`; then `renv::restore()` of `renv.lock` into the site library, with `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` | Parent of the other stages |
| `ci` | `base` | Google Chrome from Google's apt repository (Ubuntu's `chromium` is a snap, which does not run in a container), for the `shinytest2` flows; after the package layers, so a new Chrome never rebuilds them. The repository is removed again, so the image's apt setup stays standard | GitHub Actions |
| `dev` | `ci` | RStudio Server, `git`, and the development tools (`devtools`, `usethis`, `roxygen2`) from the same snapshot. The tools are never in `renv.lock` | Local development |
| `app` | `base` | The installed `prexp` package, port 3838, the non-root user `prexp`, `/data/epd` for downloads, `CMD Rscript -e "prexp::run_app()"` | The app and the `jobs` container in production, local smoke tests |

**Packages.** `renv.lock` is the only list of package versions. Every stage installs exactly those versions into R's site library, where every R process finds them, so the repository's renv files never switch libraries inside a container. To add a package: install it in the dev container, add it to `DESCRIPTION`, run `renv::snapshot(project = "~/prexp", library = .libPaths(), prompt = FALSE)`, commit `DESCRIPTION` and `renv.lock`, and rebuild the images.

Images in the GitHub Container Registry:

- `ghcr.io/katonometrica/prexp-ci:<hash>-<month>`, where the hash covers `docker/Dockerfile` and `renv.lock` and the month (for example `2026-11`) refreshes the OS packages. CI rebuilds it only when either file changes or the month turns, and otherwise reuses the stored image
- `ghcr.io/katonometrica/prexp-app:main` and `:<commit sha>`, pushed from `main` only

### 2.2 Compose services, local development

`compose.yaml` at the repository root.

| Service | Image or build | Ports (host only) | Volumes | Notes |
| --- | --- | --- | --- | --- |
| `db` | `postgres:18.7-trixie`, pinned by digest | `127.0.0.1:5432` | `pgdata:/var/lib/postgresql`, `./docker/db/init` as init scripts, `./docker/db/postgresql.dev.conf` | Health check `pg_isready -h 127.0.0.1`, which only passes once the init scripts have finished (they run against a socket-only server). The PostgreSQL 18 image keeps data under `/var/lib/postgresql`, not `.../data` as in older versions. `shm_size: 1gb` for parallel queries |
| `rstudio` | build `docker/Dockerfile`, target `dev` | `127.0.0.1:8787` | Repository bind mount at `/home/rstudio/prexp`, `epd-downloads` at `/data/epd` | Starts after `db` is healthy. Gets database settings and all three role passwords from `.env`. Opens without a sign-in (`DISABLE_AUTH`): other machines cannot reach it, because the port is bound to `127.0.0.1`, but software on this machine can ([development.md](development.md) explains the trade-off). The `rstudio` user takes the host's UID and GID from `HOST_UID` and `HOST_GID` on Linux |
| `app` | build `docker/Dockerfile`, target `app` | `127.0.0.1:3838` | none | Compose profile `app`, so it only starts with `docker compose --profile app up`. Gets the app role's credentials only |

Named volumes: `pgdata`, `epd-downloads`. Monthly files (several GB each) go in `epd-downloads`, not the bind mount, because a Windows bind mount is slow for large files. Host ports can be changed in `.env` (`HOST_PORT_DB`, `HOST_PORT_RSTUDIO`, `HOST_PORT_APP`); they are always bound to `127.0.0.1`.

**Configuration.** `.env` holds the passwords and is in `.gitignore`. `.env.example` is committed with placeholder values. Variables: `POSTGRES_PASSWORD`, `PREXP_LOADER_PASSWORD`, `PREXP_APP_PASSWORD`, `PREXP_DB_HOST`, `PREXP_DB_PORT`, `PREXP_DB_NAME`, `PREXP_TEST_DB_NAME`, and the optional `HOST_PORT_*`, `HOST_UID` and `HOST_GID`. Passwords use letters and digits only, so they need no quoting anywhere. R reads the owner's password as `PREXP_OWNER_PASSWORD`, which Compose maps from `POSTGRES_PASSWORD`; CI and Coolify set it directly.

**Init scripts** in `docker/db/init/`, run once when `pgdata` is empty. CI runs the same scripts against its database service, with `bash` and `psql`.

1. `01-roles.sh`: creates the login roles `prexp_loader` and `prexp_app` with passwords from the environment, and the test database `prexp_test` owned by `prexp_owner`. Idempotent: a rerun only resets the passwords; run in the db container it also resets `prexp_owner`'s, which is how `.env` changes reach an existing volume. It turns statement logging off for its session before sending any password. It works whether the image's entrypoint executes or sources it, and by hand through the `PG*` variables. Passwords are passed as psql variables, never spliced into SQL. Committed with the executable bit
2. `02-database.sql`: sets `prexp_app` to read-only transactions, a 5 second `statement_timeout` and `jit = off`, as role settings, so they apply in every database

Everything else (schemas, tables, extensions, grants) is created by migrations (section 3.5), so local, CI and production databases are built the same way.

**Windows note.** Docker Desktop with the WSL 2 backend. The bind mount is fastest when the repository is cloned inside a WSL distribution; a clone on a Windows drive also works, provided only source code is on the bind mount and monthly files and the database stay in named volumes. `.gitattributes` keeps LF line endings, because containers read the working tree directly.

**Database configuration, development.** `docker/db/postgresql.dev.conf`, applied with `-c config_file=`. It first includes the `postgresql.conf` that initdb generated, so `listen_addresses` and the locale settings are kept, then sets small values for a laptop: `shared_buffers=1GB`, `work_mem=64MB`, `maintenance_work_mem=1GB`, `max_wal_size=8GB`, `jit=off`. Production values are set in phases 1 and 2 from the server's memory.

### 2.3 Production

Until phase 6 everything, the full twelve months included, runs in the local Docker stack: loads run from the `rstudio` container, and the app from the `app` service. The Coolify host comes in P6-02. There the `app` image runs twice: as the app, with the app role's credentials, and as the `jobs` container, with the owner's and loader's credentials, for migrations, loads, plan checks and model fits. PostgreSQL 18 runs on the same host and is never exposed outside the Docker network. Coolify's superuser there is `postgres`, and `prexp_owner` is an ordinary login that owns the `prexp` database (`docker/db/server/00-owner.sh`), which is all the migrations need. Details in section 7, and the setup step by step in `docs/server.md`.

## 3. Database

### 3.1 Roles and schemas

| Role | Can do | Used by |
| --- | --- | --- |
| `prexp_owner` | Owns every object, runs migrations | Migrations, and the loader's build and swap steps |
| `prexp_loader` | Writes `raw` and `core` (insert, update, delete, truncate), reads `raw`, `core` and `app` | Monthly loader (staging, dimensions, checks), model batch job, plan check |
| `prexp_app` | `SELECT` on schema `app` only, read-only, 5 second timeout, JIT off | The Shiny app |

Creating, attaching and detaching partitions needs ownership of the tables, which no grant can give. So the loader's dimensions, build and swap steps (section 4, steps 5, 6 and 8) run on one owner connection, which also holds the month's temporary tables between them; the `jobs` container has the owner's credentials. Staging and the checks run as `prexp_loader`. `meta` is the owner's alone.

| Schema | Holds |
| --- | --- |
| `raw` | Staging tables |
| `core` | Fact, dimensions, rollups, load log, model results |
| `app` | Views the app reads. Nothing else |
| `meta` | `schema_migrations` |

### 3.2 Tables

A source row is finer than practice × BNF presentation × month: it is per SNOMED product and quantity per item, about 18.4 million rows a month. The app never needs that detail, so the loader aggregates on load to one row per month × practice × presentation (about 9.5 million rows a month), summing the measures ([dataset.md](dataset.md#row-grain)).

**`core.prescribing`**, partitioned by range on `year_month`, one partition per month (`core.prescribing_202609`), no default partition

| Column | Type | Notes |
| --- | --- | --- |
| `year_month` | `int4` | `YYYYMM`. The source sends the text `'YYYY-MM'` (since March 2025), converted on load |
| `practice_id` | `int4` | Key into `dim_practice` |
| `presentation_id` | `int4` | Key into `dim_presentation` |
| `items` | `int4` | Sum of `ITEMS` |
| `total_quantity` | `numeric` | Sum of `TOTAL_QUANTITY`. Units differ by presentation, never summed across presentations |
| `adq_usage` | `numeric` | Sum of `ADQ_USAGE`; NULL where the presentation has no ADQ (the source writes 0) |
| `nic` | `numeric` | Pounds; the source has at most 2 decimals |
| `actual_cost` | `numeric` | Pounds; the source has up to 5 decimals |

The measures are exact `numeric`, so the load check reconciles to the penny.

Indexes, defined on the parent so each attached partition's matching indexes are adopted:

- `(presentation_id, year_month) INCLUDE (practice_id, items, total_quantity, adq_usage, nic, actual_cost)`
- `(practice_id, year_month) INCLUDE (presentation_id, items, adq_usage, nic, actual_cost)`

Both are covering indexes, so lookups are index-only scans. That only works once the visibility map is set, which is why the loader runs `VACUUM (ANALYZE)` on each new partition.

**`core.dim_chemical`**: `chemical_id` (identity), `chemical_code` (unique, the source's `BNF_CHEMICAL_SUBSTANCE_CODE`: 9 characters, or 4 for appliance chapters 20 to 23), `chemical_name`, `first_seen`, `last_seen`. Trigram GIN index on `chemical_name`, and a `text_pattern_ops` index on `chemical_code` for prefix search (the database's collation is not C).

**`core.dim_presentation`**: `presentation_id` (identity), `bnf_code` (unique), `bnf_description`, `chemical_id`, `bnf_chapter` (`05`), `bnf_chapter_name` (`Infections`, from `BNF_CHAPTER_PLUS_CODE`), `bnf_section` (`0501`), `bnf_paragraph` (`050101`), `is_generic` (characters 10 and 11 of the BNF code are `AA`; null for appliance chapters 20 to 23), `first_seen`, `last_seen`. No SNOMED code: a presentation can have several. Trigram GIN index on `bnf_description`, and a `text_pattern_ops` index on `bnf_code`.

**`core.dim_practice`**: `practice_id` (identity), `practice_code` (unique), `practice_name`, `address`, `postcode`, `icb_code`, `icb_name`, `region_code`, `region_name`, `is_unidentified`, `first_seen`, `last_seen`. Trigram GIN index on `practice_name`, and a `text_pattern_ops` index on `practice_code`. Name, ICB and region take the values of the prescriber's own last month: one still prescribing after the ICB reorganisation of April 2026 shows its new ICB for every month, while one that stopped before keeps its old one. `is_unidentified` marks the 'UNIDENTIFIED DOCTORS' codes, including the national code `-`; their rows stay in the fact table so totals reconcile.

**Rollups**, all rebuilt one month at a time by the loader:

| Table | Grain | Serves |
| --- | --- | --- |
| `core.agg_presentation_month` | Presentation × region × month | Drug series at presentation level, without touching the fact table |
| `core.agg_chemical_month` | Chemical × region × month | Drug series at chemical level, regional comparison |
| `core.agg_practice_month` | Practice × month | Practice monthly totals |

Each rollup row holds the sums of the measures that can be added at its grain (`total_quantity` only per presentation, `adq_usage` not across substances), and the number of practices, or for a practice the number of presentations, behind it. `region_code` is the practice's region when the month was loaded (`-` when unknown). The presentation rollup's primary key (presentation, month, region) carries the measures, so a chemical's presentations are an index-only scan; the loader vacuums the rollups after each swap to keep that so.

**`core.load_log`**: one row per load attempt: `load_id`, `year_month`, `source_url` (the resource's stable CSV link, never the signed ZIP link), `source_sha256`, `source_rows`, `loaded_rows`, `file_bytes`, `started_at`, `finished_at`, `status` (`running`, `loaded`, `failed`, `replaced`, `dropped`), `error`. A month has at most one `loaded` row, the data that is live (a unique index): a successful reload marks the previous one `replaced` in the same transaction as the swap, and a failed reload leaves it alone. The current window is the months with a `loaded` row.

**`raw.epd_staging`**: unlogged, with autovacuum off, every column `text`, named as the source header in lower case and in its order. Truncated at the start of each load.

### 3.3 App views

| View | Reads | Used by |
| --- | --- | --- |
| `app.v_window` | `load_log` | Date range, cache key |
| `app.v_chemical` | `dim_chemical` | Search, labels |
| `app.v_presentation` | `dim_presentation` + `dim_chemical` | Search, labels |
| `app.v_practice` | `dim_practice` | Search, labels |
| `app.v_region` | `dim_practice` | Region names for the rollups' `region_code` |
| `app.v_presentation_month` | `agg_presentation_month` + dimensions | Drug view, presentation level |
| `app.v_chemical_month` | `agg_chemical_month` + dimensions | Drug view, chemical level; region view |
| `app.v_practice_month` | `agg_practice_month` | Practice view, totals |
| `app.v_practice_presentation` | `prescribing` + `dim_presentation`, a left join the planner leaves out when no presentation column is used | Practice view, top drugs |
| `app.v_variation` (v2) | `model_variation` + dimensions | Variation view |

### 3.4 Size estimate

Measured on September 2026 (P1-09, [benchmarks.md](benchmarks.md#one-month-p1-09)): 9,459,744 fact rows after aggregation, a 639 MB table (71 bytes a row) and 1,133 MB for its two indexes, 1,772 MB (1.73 GB) a month in all; the month's rollup rows and the dimensions add under 40 MB. Twelve months, measured in P2-02 ([benchmarks.md](benchmarks.md#twelve-months-p2-02)): 112.8 million fact rows, 20.7 GB of fact table and indexes, 20.9 GB for the whole database. While a month loads, staging holds 7.0 GB, the month being built beside the live one 1.7 GB, and the write-ahead log peaked at 1.6 GB, so the peak is about 31 GB (sizes in PostgreSQL's units, 1 GB = 1,024 MB). **Plan for at least 50 GB free disk for Postgres**, which leaves room for larger months. Phase 2's indexes added about 50 MB (migrations 008 and 009); the database is 20.9 GB ([benchmarks.md](benchmarks.md#at-a-glance-p2-06)).

### 3.5 Migrations

Numbered SQL files in `inst/sql/migrations/` (`001_schemas.sql`, `002_dimensions.sql`, ...), applied in order by `prexp::migrate()` as `prexp_owner`, each in its own transaction, recorded with a checksum in `meta.schema_migrations`. Applied files are never edited; changes are new files, and a changed checksum stops `migrate()`. CI applies all migrations to an empty database on every run, and the `jobs` container runs `migrate()` after every deploy.

- `migrate()` with no arguments connects as the owner; it refuses to run as any other role
- A per-database advisory lock stops two runs at once
- Checksums ignore line endings and a byte-order mark, so Windows and Linux checkouts agree
- Before applying anything, it stops if an applied file has changed or is missing, or if a pending file is numbered below the last applied one
- Each file is sent in one call (RPostgres's simple query protocol) inside its own transaction, so files must not contain `BEGIN`, `COMMIT` or commands that cannot run in a transaction. Row-returning statements in one file must all return the same columns; wrap calls whose result is not needed in `DO $$ BEGIN PERFORM ...; END $$`
- A test records every shipped migration's checksum (a testthat snapshot), so editing an applied file fails CI; adding a migration means accepting the new snapshot (`testthat::snapshot_accept()`), which reviewers see in the diff

## 4. Monthly loader

Entry points:

- `prexp::load_month(year_month)`: loads or reloads one month
- `prexp::load_latest()`: what the schedule calls. It loads the most recent published months that are missing, as `load_window()` does (the newest month once it is published, which drops the oldest, and any month a failed run missed), then reloads each live month whose published `sha256` is no longer the one it was loaded with, since months are sometimes re-published. A month without a hash, on the portal or in `load_log`, is never reloaded. With nothing to do it says so and returns, so the task exits 0; a failure stops with an error naming the month, so the task exits non-zero and its alert fires
- `prexp::load_window(n)`: loads the `n` most recent published months missing from `load_log` (by default the whole window, `PREXP_WINDOW_MONTHS`), oldest first, as they were published. Used for the first load and for rebuilds. A month older than every month the window keeps is left out with a message, since it would be dropped at once. It stops at the first month that fails; running it again carries on

A Postgres advisory lock stops two loads from running at once. The window size comes from `PREXP_WINDOW_MONTHS`, default 12.

**Steps**

| Step | What | Detail |
| --- | --- | --- |
| 1. Find | Look up the month's file | The NHSBSA open data portal runs CKAN: `package_show` for the dataset lists one resource per month, named `EPD_SNOMED_YYYYMM`. Resource ids are random, so the month is found by name. Its `sha256` is recorded; months are sometimes re-published, and a changed hash means the month is reloaded |
| 2. Download | Fetch the ZIP into `epd-downloads` | The ZIP (about 0.67 GB against 7.7 GB for the CSV) is only offered through the resource's `zip_url`, a signed link valid for one hour, so the metadata is fetched again just before each attempt. Without a `zip_url`, the CSV (`url`) is downloaded instead. Written to a `.part` file and renamed when complete. Skipped if a complete file is already there |
| 3. Validate header | Compare the CSV header with `inst/extdata/epd_columns.csv` | Read as the first line of `bsdtar -xOf`. Any difference stops the load with a message listing the differences |
| 4. Stage | Stream into `raw.epd_staging`, then check that it holds the month asked for | `bsdtar -xOf file.zip \| psql -c "\copy raw.epd_staging FROM STDIN CSV HEADER"` under `bash -o pipefail`, with the stream's SHA-256 computed on the way and compared with the resource's `sha256`. A blank value is staged as an empty string, never NULL (`FORCE_NOT_NULL`), so it can never drop out of a sum. `bsdtar` (libarchive), because Ubuntu's `unzip` cannot read these archives and silently outputs nothing. Streaming avoids unpacking a multi-GB file to disk and avoids loading it into R |
| 5. Dimensions | Work out the month's chemicals, presentations and practices | In temporary tables, with their ids: existing ones, or new ones from the identity sequences. Nothing in `core` changes; the swap writes them |
| 6. Build | Create `core.prescribing_YYYYMM_new` as a plain table, insert from staging joined to the dimensions and grouped by practice and presentation (sums of the measures; `ADQ_USAGE` of 0 becomes NULL), add `CHECK (year_month = YYYYMM)`, build both indexes, `VACUUM (ANALYZE)` | Done outside the partitioned table, so the live data is untouched while it builds |
| 7. Check | Every staged value valid (`ITEMS` a whole number of at least 1, the other measures finite and not negative); staging rows against the `COPY` count; new table rows against the distinct practice × presentation pairs in staging; `sum(items)`, `sum(nic)` and `sum(actual_cost)` of the new table against staging | Any mismatch stops the load. The live data is still untouched |
| 8. Swap | One transaction: write the month's dimensions (new codes inserted; names, ICB and region replaced only by a month at least as recent as `last_seen`), rebuild that month in the three rollups, then detach and drop the existing partition for that month if any, rename and attach the new table, and update `load_log`. A new month that takes the window beyond `PREXP_WINDOW_MONTHS` months drops the oldest months beyond it in the same transaction (one, or several if the window has been made smaller): their rollup rows are deleted before any detach, then their partitions are detached and dropped after the attach, and their loads marked `dropped`. A reload never drops anything | The `CHECK` constraint makes the attach instant. Detaching locks the parent table until the commit, and app queries queue behind a detach that waits for its lock, so each wait is limited to 1 s (`lock_timeout`, well under the app's 5 s statement timeout) and retried, up to 10 times, after a pause that lets them run. After the commit, the parent's statistics are refreshed (`ANALYZE ONLY`) and the rollups vacuumed, which keeps their visibility maps set for index-only scans; a failure there is a warning, never a failed load |
| 9. Clean | Truncate staging. Delete the ZIP | |

Rerunning a month rebuilds and swaps it, which makes the loader idempotent. A failure before step 8 changes nothing in `core`, dimensions included. A failure inside step 8 rolls back. An interrupted load is recorded as failed and cleaned up like any other failure, unless the interrupt came after its swap committed, while the COMMIT's reply was on its way: then the month is loaded, and the error says so. A downloaded file that fails before its SHA-256 is checked is deleted, so it is downloaded again. Loading a month older than the first month of a full window is refused, before anything is downloaded or recorded, since it would be dropped at once. Dimension rows are never deleted, so shared links never point at a missing key.

## 5. Application

### 5.1 Package layout

```
prexp/
├── DESCRIPTION, NAMESPACE, LICENSE, README.md
├── R/
│   ├── run_app.R, app_ui.R, app_server.R
│   ├── db.R                   pool and connections, migrate(), settings from env
│   ├── fct_queries.R          all app SQL access, fetch_*()
│   ├── fct_query_registry.R   each query's SQL file and sample arguments
│   ├── fct_charts.R           ggplot + ggiraph chart builders
│   ├── fct_report_spec.R      report spec: add, remove, move, encode, decode, clamp
│   ├── fct_export_office.R    PowerPoint and Word
│   ├── fct_export_excel.R     Excel
│   ├── fct_methods.R          methods content, shared by the About tab and all formats
│   ├── fct_source.R           the source files and the portal: columns, header, download
│   ├── fct_loader.R           load_month(), load_latest(), load_window()
│   ├── fct_plan_check.R       check_plans()
│   ├── mod_search.R, mod_drug.R, mod_practice.R, mod_region.R, mod_report.R
│   ├── theme.R                brand tokens and CSS; bslib, ggplot2, reactable and mschart themes
│   └── utils_validate.R, utils_format.R, utils_log.R
├── inst/
│   ├── sql/migrations/, sql/load/, sql/queries/
│   ├── templates/report.pptx, report.docx
│   ├── extdata/epd_columns.csv   expected source header
│   └── app/www/                  CSS, scripts, fonts (IBM Plex, OFL), favicon
├── tests/testthat/
│   ├── fixtures/                 thirteen fixture months, saved API responses
│   └── test-*.R
├── data-raw/make_fixtures.R
├── docker/Dockerfile, docker/db/
├── compose.yaml, .env.example
├── .github/workflows/ci.yaml
├── docs/spec.md, docs/dataset.md, docs/benchmarks.md, docs/runbook.md
└── renv.lock
```

A plain R package following golem file naming, without depending on `golem`.

### 5.2 Query catalogue

Every function takes `con` (a pool or connection) first, validates its arguments, reads its SQL from `inst/sql/queries/` through the registry, binds parameters, and returns a tibble. The plan check runs the same SQL files, so what is checked is what the app runs.

| Function | Arguments | Returns | Reads |
| --- | --- | --- | --- |
| `fetch_window()` | none | First and last month | `v_window` |
| `fetch_regions()` | none | The seven NHS regions, for a comparison that shows each | `v_region` |
| `fetch_search_drugs()` | `q` (2 to 100 characters, after control characters and spaces at either end are removed), `limit = 20` | Chemicals and presentations whose name contains `q` (for two characters: starts with it, or has a word after a space that does) or whose BNF code starts with it; names that contain `q` ranked by similarity. `%`, `_` and `\` match themselves: the query escapes them | `v_chemical`, `v_presentation` |
| `fetch_search_practices()` | `q`, `limit = 20` | Practices matched by name, the same way, or by code | `v_practice` |
| `fetch_drug_series()` | `level` (chemical or presentation), `id`, `months`, `measure` | Monthly national totals | `v_chemical_month` or `v_presentation_month` |
| `fetch_drug_presentations()` | `chemical_id`, `months` | Totals per presentation, brand or generic | `v_presentation_month` |
| `fetch_practice_profile()` | `practice_id` | Name, address, ICB, region | `v_practice` |
| `fetch_practice_series()` | `practice_id`, `months` | Monthly totals | `v_practice_month` |
| `fetch_practice_top_drugs()` | `practice_id`, `months`, `by` (items, NIC or actual cost), `limit`, `after` (the last presentation of the previous page; keyset paging on the total and the presentation) | Top presentations, paged | `v_practice_presentation` |
| `fetch_region_comparison()` | `level`, `id`, `months`, `measure`, `per` (total, or per 1,000 patients in v2) | Totals per region | `v_chemical_month` or `v_presentation_month` |
| `fetch_subject()` | `kind` (chemical, presentation or practice), `code` | The id, code and name of the subject with that code, for a report's link (§5.5); not only those with data in the window, and not the unidentified prescribers | `v_chemical`, `v_presentation` or `v_practice` |
| `fetch_variation()` (v2) | `group`, `icb_code` | Observed, expected, ratio, interval per practice | `v_variation` |

Quantity is only valid for a single presentation, because units differ across presentations.

`fetch_drug_series()` and `fetch_region_comparison()` return the measure asked for as `value`, with a `measure` column that names it; the others return every measure. A month or region without prescribing has no row, and an unknown id returns no rows at all. `is_generic` is `NA` for a chemical and for an appliance (BNF chapters 20 to 23), which is neither brand nor generic; `adq_usage` is `NA` where no ADQ is defined, and a chemical's sums only its presentations that have one. Chemical and presentation ids are numbered apart, so a search match is known by its level and id together. A refused argument stops the call before it queries, with an error of class `prexp_invalid_argument`, so the app can tell a request it refused from a query that failed. Sums of items are doubles, exact up to 2^53.

Each query is registered in `fct_query_registry.R` with two sample argument sets. Codes are looked up at run time, among those with data in the months asked for:
- large, over the whole window, the worst case it holds, picked from the data when the check runs: the chemical with the most presentation rollup rows (presentation × region × month), the practice with the most prescribing rows, and for each search the two characters that start the most names' words;
- small, over the last three months: a rarely prescribed drug, or a small practice.

`check_plans()` runs every entry once to warm the cache, then with `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, FORMAT JSON)`. It fails on any of:
- a read of a `core.prescribing` partition that is not an index-only scan;
- a plan that reads more partitions than the months asked for;
- heap fetches in an index-only scan of one;
- planning and execution over 50 ms;
- a query that returns no rows, or errors.

`check_plans(generic = TRUE)` checks the generic plans of prepared statements the same way.

### 5.3 Screens

`bslib::page_navbar` with five tabs and the theme button. The footer on every tab shows the data window, the NHSBSA attribution, the link to the source and KATONOMETRICA's wordmark. The page head carries `noindex, nofollow`.

| Tab | Inputs | Shows | Pinnable |
| --- | --- | --- | --- |
| Drug | Search (chemical or presentation), month range, measure | Monthly series chart; presentations table with brand or generic | Yes |
| Practice | Search, month range, measure | Profile, monthly totals chart, top drugs table | Yes |
| Region | Drug search, month range, measure | Bar chart and table by region | Yes |
| Report | none | Pinned items with notes, reorder, remove, copy link, three export buttons | n/a |
| About | none | Methods, data source, licence, limitations | n/a |

Every view handles three states besides the normal one: nothing selected, no rows, and query error. Each shows a message rather than an empty chart.

**The look.** The app looks like KATONOMETRICA's site, katonometrica.com. Its values come from the site's `styles.css` (the tokens of its dark theme and its light one) and `fonts/fonts.css`; its principles from the brand's designer instructions: square corners, flat surfaces with no shadows, gold as a signal (the call to action, the open tab, a selected mark, the focus outline), sentence case, and motion limited to shifts of colour and border in 150 ms (`cubic-bezier(0.4, 0, 0.2, 1)`), none where the visitor asks for reduced motion.

- **Themes.** Dark on every first visit, as on the site, with a light theme. A button at the navbar's right, as the site's (◐ in dark, ◑ in light, labelled "Switch to light theme" or "Switch to dark theme"), switches between them, and the browser keeps the choice in `localStorage` under `theme`; no cookie. An inline script in the head sets `data-bs-theme` on the page's root before the page is drawn, so Bootstrap 5.3's colour modes and the app's own colours switch together.
- **One source for the colours.** `brand_tokens()` in `R/theme.R` holds each theme's colours. `brand_css()` writes them into the head as custom properties (`--prexp-*`) and as Bootstrap's own, and `inst/app/www/prexp.css` styles every component from those alone. The tests check, in both themes, every text on every surface it sits on at 4.5:1 and every mark and control edge at 3:1.
- **Type.** IBM Plex Sans, weights 400 to 600, for everything; IBM Plex Mono for small details: codes, badges, the footer's provenance line. The site's files are served with the app from `inst/app/www/fonts`, under the SIL Open Font License 1.1 (`OFL.txt` beside them); nothing is fetched from elsewhere.
- **Charts.** Drawn once on the server, in the light theme's colours, with no background of their own. CSS generated from the same tokens maps each role's colour to the theme shown, so a switch costs no redraw and no cache entry: marks in navy blue (#355695 light, #678ccf dark); a selected mark in the gold, a bar outlined at 2 px in the text colour, a point drawn 1.8 times larger with a 1 px ring in the text colour; tick labels in the secondary text colour, axis titles in the text colour, gridlines as faint as the borders, at one pixel. Tooltips are square, in IBM Plex Sans. The server measures the charts' text with the page's own copy of IBM Plex Sans, registered with `systemfonts` when the app starts, unless IBM Plex Sans is installed: the installed font, with the same metrics, then measures it.
- **Components.** The navbar on the page's colour, a rule under it, its tabs as the site's links (14 px, weight 500, in the secondary text colour; the open tab in the text colour over a 2 px gold rule, which in the collapsed menu is at its left). Cards on the brand's surface with a 1 px border. Fields, selects and the note box as the site's inputs: a well of the page's colour, the edge gold on focus, no glow. Radios stay round, filled gold when checked. One gold button per view (Add to report, Prepare); the site's outline button for downloads and links; ghost buttons for moving and removing. Neutral badges in Plex Mono, "Months clamped" marked by the word Note rather than a warning colour. Tables on no background of their own, a stronger rule under the header, no stripes. Notifications as the site's: square and opaque. The About tab as the site's policy pages: one column at most 800 px wide. Focus is a 2 px gold outline, 2 px off the element, or just inside a table's cell, which the table's scroll box would cut. The favicon is the brand's mark.
- **Where the app departs from the site,** for WCAG AA, which the brand calls non-negotiable:

| What | The site | The app |
| --- | --- | --- |
| Edges of fields, selects, radios and their lists | `--border-strong`: 1.3:1 dark, 1.8:1 light | #706b63 dark, #858280 light: 3.3:1 or more on the page and on cards |
| Placeholders | `--muted` #5a5650: 2.6:1 on the dark page | The secondary text colour; `--muted` marks disabled controls only |
| Disabled controls, light | `--muted` #5a5650, the secondary text colour (7.1:1): a disabled button looks live | #9e9a94: 2.7:1 on the page, as dark's muted is 2.6:1 |
| Hover of the gold buttons, light | #c9a84c: 2.2:1 under their text | #5e4c1a: 8.1:1 |
| Error text | #e74c3c dark, #dc2626 light: under 4.5:1 on raised surfaces | #f87171 dark, #b91c1c light: 5:1 or more |
| Success text, light | #15803d: under 4.5:1 on raised surfaces | #166534 |
| Links | Gold, 1.7:1 from the dark theme's text | Underlined in running text, 0.2 em below it |
| Floating layers that carry secondary text | `--bg-elevated` #182545: 4.1:1 | `--bg-alt` #0f1730: lists, tooltips, notifications |

**The exports.** The Office exports (section 5.5) take the light theme, which the brand keeps for print and daytime presentations, from `export_palette()` in `R/theme.R`, which reads `brand_tokens()`: text #0b1222; secondary text #5a5650 (views and subjects, captions, footnotes, the charts' tick labels); links #7d6523, underlined; the charts' mark #355695, the app's charts' own, so that an export shows what the screen shows, with gridlines #DFDEDD, no axis lines or ticks, no frame around the chart and no outline on its bars; tables with a #0b1222 rule under the header and over a total, #BEBDBC rules between rows and no bands (Excel's in its Light 1 style, drawn in the theme's text colour, with no bands). On white, every text colour reads at 4.5:1 or more and the mark at 3:1, as the tests check.

- **Font.** IBM Plex Sans, the owner's decision of 26 November 2026, knowing that an Office file cannot embed it. The templates and the workbook name it as their theme's font, major and minor, with IBM's PANOSE of its Regular (`020B0503050203000203`) and pitch family 34, a sans of variable pitch, and Word's font table declares it too. Microsoft 365 downloads IBM Plex Sans and IBM Plex Mono as cloud fonts the first time a file names them, so most Office readers see Plex itself; Office without cloud fonts, and LibreOffice, draw a sans of their own, chosen by the declared PANOSE and family. The text takes the theme's font, and the tables and charts name it by reference (`+mn-lt`); the workbook's base font is IBM Plex Sans, of the Swiss family. The text is measured in both IBM Plex Sans and Arial, so that a slide or a table fits in either (section 5.5).
- **Themes.** The templates' and the workbook's colour scheme is the brand's, so that a chart, a table or a shape a reader adds in Office takes its colours: dark 1 #0B1222, light 1 #FFFFFF, dark 2 #0F1730, light 2 #F7F5F2, accents #355695, #7D6523, #5A5650, #678CCF, #BEBDBC and #C9A84C, hyperlinks #7D6523, followed ones #5A5650; their shapes are flat, with no gradient, shadow or bevel. The schemes are named Katonométrica, and so are the Word template's and the workbook's themes; the PowerPoint's keeps its name, Office Theme, as officer names the master after it.
- **The maker.** The PowerPoint's cover and the Word's title page carry the wordmark KATONOMETRICA above the title, letter-spaced 0.18 em, in the secondary text's colour, linking to https://katonometrica.com; in IBM Plex Mono, declared as Plex Sans is (PANOSE `020B0509050203000203`, fixed pitch), so that Office draws a font of fixed pitch in its place. On the cover the text box is the link, as PowerPoint would draw linked text in the theme's link colour. The cover's title, its lines and the slides' titles are left-aligned at the content's margin.

### 5.4 Runtime

- `pool` created once per process as `prexp_app` by `db_pool()`, and closed when the app stops. Every connection it opens, and every `db_connect("app")`, must be read-only by default from the server's settings for the login or the database (a default the client asks for, with `PGOPTIONS` or the `options` parameter, does not count), and its login must not be a superuser or able to use the `core` and `raw` schemas. Otherwise the connection is closed and refused, so the app refuses to start with the loader's or the owner's login
- Search uses selectize with remote loading: a small script sends typed text to the server, which ignores fewer than two characters, debounces at 300 ms, and sends back up to 20 matches from `fetch_search_*()`
- Tables use `reactable`, the one table library in the app
- An app-wide `cachem::cache_mem()` of 200 MB around the fetch functions the views call, keyed on the fetch, its arguments and the window from `fetch_window()`, so a month loaded starts afresh. The charts the views draw are kept in it too, keyed on what each is drawn from (its data, months, width and name) and the window. Not `bindCache()` on the views' reactives or outputs: it keeps an error as it keeps a value, so one session's passing database error would be served to every session asking the same. Here an error is never kept
- A lookup is answered in one message. A view's results sit in a frame drawn again only when its layout changes: which message it shows, and its text, or which parts the results have (the presentations table or its error, the Region chart and note). Otherwise its outputs change in place. The chart and table outputs in it are computed without waiting for the browser to report them shown, and the chart is drawn at the body's width, which the browser reports before any pick, to the nearest 10 px. It is drawn again only when that width moves by 30 px or more, so a long table that gives the page a scroll bar does not draw it again
- Exports and any fetch expected over 100 ms run in `ExtendedTask` on two `mirai` daemons. Each daemon opens its own connection, because a pool cannot be shared across processes
- Every fetch logs one JSON line to the process's standard output: the time, the function, a keyed hash of its arguments (16 hex digits of a SHA-256 of a key and the arguments, so identical requests share it, while the values, search text included, cannot be read back from it), the rows and the milliseconds, and `"error": true` if the query failed or was interrupted. The key is `PREXP_LOG_KEY`, or one the app's process draws when it is unset and gives to its daemons, so that identical requests share a hash within a run. Each line is one write to connection 1, which no `sink()` diverts, so `renderPrint()` cannot take it, and lines from processes that share the output do not mix. The `mirai` daemons start with `output = TRUE`, so the lines of the fetches they run reach the app's output too. `PREXP_LOG=off` turns the log off, as the tests do. `timing_summary()` reads logs back into count, errors, p50 and p95 per function, by nearest rank, also from `docker compose logs`, whose lines carry a prefix. Used for the p95 figure and for spotting slow queries in production

### 5.5 Reports

**Flow.** Explore a guided view, press "Add to report" to pin it with its current selections, write a note under it, then reorder or remove items in the report panel. When ready, export.

**Report spec.** A report is an ordered list of items, each with a view type, its parameters (drug, practice, region, months) and a note. Items store parameters, not data, so an export re-runs the queries and stays consistent with the database.

**Shareable link.** The report is encoded in the URL with Shiny URL bookmarking. Opening the link restores the selections, pinned items and notes; nothing is stored on the server. Notes are capped at 500 characters, reports at 15 items and a report's link at 7,500 characters, to keep links within URL limits: a pin, a note or a move that would make the link longer is refused. Because the window rolls, a link can name months that have since been dropped: on restore those items are clamped to the current window and flagged in the report panel, rather than failing.

**Contents of every export.** A title page with the data period and export date; one section per pinned item with its chart, table and note; and a methods section with the data source and period, the filters applied per item, measure definitions, and the NHSBSA attribution with the Open Government Licence 3.0.

| Format | Built with | Charts | Layout |
| --- | --- | --- | --- |
| PowerPoint | `officer` + `mschart` on `report.pptx` | Native Office charts, editable | One slide per item, methods as the last slide |
| Word | `officer` + `mschart` on `report.docx` | Native Office charts, editable | One section per item, methods as an appendix |
| Excel (`.xlsx`) | `openxlsx2` + `mschart` | Native Excel charts | One sheet per item, methods as the last sheet. No macros, so it opens without security warnings. Built in R, with no template |

Implementation notes:

- The report spec is a list of items `{id, view, params, note}`. Pure functions in `fct_report_spec.R` add, remove, move, validate and clamp it, and encode it for the URL (compact JSON, gzip, base64url)
- `enableBookmarking("url")` stores only the active tab, the selections of the view last shown (the Copy link button is on the Report tab), or, in a session opened from a link that has shown no view yet, those the link put back, and the encoded spec: the selections as a one-item report, so that `decode_report()` checks both whole when a link is opened. Every other input is excluded as the URL is written. The Copy link button copies the URL with the browser's clipboard and shows it, selected, where the browser will not copy it; it answers clicks only, not a value a link's `_inputs_` gives it. Limits: 15 items, 500 characters per note and 7,500 characters for the report's link, which leaves room for the rest of the URL under the 8,000 that RFC 9110 asks servers to accept. Notes of English prose at the first two limits take about 4,500; notes that compress poorly reach the link's limit first
- On restore, `clamp_report(spec, window)` limits each item's months to the current window and marks changed items `clamped`, which the report panel shows. A link opened while the window cannot be fetched waits for it
- A link names each drug and practice by its code, which a rebuilt database keeps while ids change. On restore, `fetch_subject()` looks each one up by its code, not only within the window, and the id and the name come from there, never from the link, which could name any id anything. An item whose code the data does not hold is left out and the user told; a part of the link that is not what the app writes, or that Shiny dropped because it was cut short, is refused and the user told
- Exports run each item's fetch again with the fetch functions the views call, build charts with `mschart` using `theme.R`, and add `fct_methods.R` content last. They run as an `ExtendedTask`, on a background worker with its own connection (in the app's process when no workers run): "Prepare", then "Download". A file prepared for a report that has changed since is not offered. An item's table is the one its view shows: a chemical substance's presentations, most items first; a practice's top drugs by the item's measure; a drug's regions with their shares. A presentation, which has no table on screen, gets its months. A table shows at most 25 rows
- PowerPoint, on `report.pptx` (16:9; `data-raw/make_templates.R` makes it from officer's template, in the brand's theme from `R/theme.R`, section 5.3): a title slide with the maker's wordmark, the data period and the export time; one slide per item (title, its view and subject, chart, note), with the table beside the chart when it has at most 12 rows of at most 3 columns and fits there, and otherwise on following slides, as many as its measured height needs, filled evenly; a note too long for the room under the chart continues on slides of its own; then the methods, a slide per section, a long one continued. A slide does not grow to fit its text, so the text is measured in both the fonts Office may draw it in, IBM Plex Sans and Arial, at their design widths: each string takes the wider font's width, each paragraph the more lines it wraps to, each line keeps a point of room, and a line is 1.2 em high, as PowerPoint lays out single-spaced text in any font, so that nothing runs off a slide in either. A table's total is measured in bold, the weight it is drawn in, and a character neither font has, such as a Chinese one, as an em wide, since Office draws it from a font of its own. The charts draw straight lines between the months and the view's axis steps, and carry their alt text; each table's first row is its header row; each text box's text starts at its top. Word, on `report.docx` (A4 with 2.5 cm margins; `data-raw/make_templates.R` makes it from officer's template, in the brand's theme, its text in the text's colour, its styles named in English, its headings unnumbered, with a Title style and a Report Table style): a title page with the maker's wordmark, the data period and the export time; a page per item, which its heading starts, with its view and subject, a native chart with its alt text, its note and its table, a plain Word table in the Report Table style whose header row repeats on a page it runs onto (a flextable's formatting of every cell made a 15-item report six times larger and ten times slower to write); a table of more than three columns, whose BNF codes and national totals do not wrap, on landscape pages of its own after its item's; the methods as an appendix, a heading per section, their points a bulleted list. The text is in British English for Word's proofing, as the charts are. Excel, built in R with openxlsx2's methods, which change the workbook in place (its `wb_*()` functions copy it at every call), with IBM Plex Sans as its base font and the templates' theme: a first sheet with the data period, the export time and the items' sheets; a sheet per item, named by its number and subject in at most 31 characters (a straight apostrophe written as a typographic one, which a chart's reference to the sheet needs no doubling for), with its title, view, subject and note in the first rows (a note too long for the frozen rows goes under the tables, as Excel does not scroll a frozen pane), its table as an Excel table under a frozen header row, in Excel's Light 1 style, whose rules take the theme's text colour, with no bands, numbers kept as numbers in the app's formats and blank where there is none, and its months or regions beside it as a small table with a native chart under it, with its alt text; a Methods sheet last, its rows as high as their lines, measured as a slide's are, at 15 points a line, as Excel draws 11-point IBM Plex Sans; no macros, no pivots, no formulas

## 6. Testing and CI

### 6.1 Test database

Tests connect to the `prexp_test` database, and make the databases they read or change. `local_fixture_db()` makes one per test run: migrated, with the thirteen fixture months loaded by the real loader (about 8 seconds), and dropped when the run ends. The fetch tests read it as `prexp_app`; a test that writes makes a database of its own. So no test depends on what an earlier run left, and two runs at once do not collide. The fixtures are 3,984 rows from one real month (every row of eight prescribers in all seven regions, covering the v2 groups, brands and generics, drugs no other practice prescribed, presentations with no ADQ, appliances and unidentified prescribers, plus a sample of the national unidentified prescriber), repeated as thirteen synthetic months with scaled measures, so the rolling drop can be tested; under 2 MB in all (`tests/testthat/fixtures/README.md`). Expected values come from an independent `dplyr` aggregation of the fixture files, with exact decimal sums, never from the code under test. Fetch tests connect as `prexp_app`, so they also prove the grants. `local_test_db()` skips a test with a clear message when no database is reachable, so pure tests still run anywhere; in CI, where `PREXP_TEST_DB_REQUIRED=true`, it fails instead, so a broken database setup cannot pass as skipped tests. Migration tests each create a temporary database from `template0` and drop it afterwards, because migrations create schemas, extensions and default privileges.

### 6.2 Workflow `ci.yaml`, on every pull request and push to `main`

1. Job `image`: the tag is the hash of `docker/Dockerfile` and `renv.lock` plus the month. It builds and pushes `ghcr.io/katonometrica/prexp-ci:<tag>` only if that tag does not exist yet, passing the month as the build argument `OS_REFRESH`, so the OS layer (`apt-get upgrade`) is rebuilt monthly instead of being frozen by the build cache. Otherwise every run reuses the stored image, so a new image is built only when a package or the Dockerfile changes, or the month turns. The image carries its own cache metadata (inline), which the app builds reuse, and one shared cache, overwritten by each build, lets a build for a new `renv.lock` reuse the OS layer, so cache storage does not grow. Each CI build passes the fastest Ubuntu mirror it can reach (the runner's own, Azure's or the main archive, each timed on one index file), because some are very slow from GitHub's runners. It goes in as a build secret, not a build argument: build arguments are part of the cache key, and the mirror differs from runner to runner. The image keeps the standard sources. Pull requests from forks cannot push, so a fork that needs a new image gets a clear failure
2. Job `checks` runs in that image with a `postgres:18.7-trixie` service (the same digest as Compose), after creating the roles with the same init scripts as Compose. It runs even when `image` fails, and then fails. The required check is a small gate job, `test`, that always runs and passes only if `checks` passed, so a failed, skipped or cancelled run fails it (GitHub treats a skipped required check as passed) while Cancel still stops the checks
3. Install the package, then `lintr::lint_package()`, failing on any lint
4. `prexp::migrate()` on the empty service database and on the test database
5. Tests and coverage in one run. The gate: 85% overall, and no package function with zero coverage, so deleting any test that is a function's only coverage fails CI. The `coverage/` report is uploaded as an artifact
6. The end-to-end flows (`tests/testthat/e2e-flows.R`): the app as the `app` image runs it, the installed package with its background workers, on the fixture database, driven in Google Chrome by `shinytest2`. Seven flows: search a drug, see its series and change the measure; page through a practice's top drugs; compare a drug across the regions; pin two views with notes and export them to Excel; copy the report's link and open it in a new tab; type, paste or dictate over a picked drug; open the page dark, switch it to light with the theme button, which recolours the page and a chart, and open it light again on a narrow screen, with the keyboard's focus shown on a radio and on the collapsed navbar's toggle, and the open tab marked in the collapsed menu. They assert on values and outputs, against the fetch functions' results, never on screenshots. The file's name does not start with `test`, so the suite and the coverage run leave it out: the app runs in its own process, where coverage could not count it. A skipped flow fails the step, since shinytest2 skips rather than fails a flow when Chrome cannot start; a failing run uploads the apps' logs
7. Jobs `app-image` (pull requests, read-only token) and `app-publish` (`main` only): build the `app` image on the tested CI image's own layers and check that `library(prexp)` loads. `app-publish` pushes `:<commit sha>`, and moves `:main` only while the commit is still the tip of `main`, so re-running an old run cannot roll it back. When `:main` moved, it asks Coolify's API to deploy the app and the `jobs` container (P6-02), over HTTPS, with a deploy-only token. The token, Coolify's host name and the two applications' ids are four repository secrets, one value in each, so that Actions hides each in its logs. Coolify answers 200 even when it could not queue an application, so the step checks that both were queued

Triggers: pull requests, pushes to `main`, a monthly schedule on the 1st (which publishes the refreshed image) and manual runs. Third-party actions are pinned to commit SHAs and updated by Dependabot, with a seven-day cooldown on new releases; the BuildKit image is pinned by digest and updated by hand, because the image jobs hold a token that can push packages. The required check is strict: a pull request must be up to date with `main` before it merges. The container packages are public from P6-02, so the server pulls them without logging in; jobs log in with `GITHUB_TOKEN` to push, and to read the registry caches.

### 6.3 Checks that need the full database

The full database (twelve months, 112.8 million fact rows) lives in the local Docker stack, not in GitHub Actions, so these run there; P6-02 runs them again on the server, which is smaller than the development machine:

- `prexp::check_plans()`: during phase 2 by hand, then nightly as a Coolify scheduled task
- The p95 benchmark: `shinyloadtest` records a session of searches and view changes, `shinycannon` replays it with 5 concurrent users, and p95 comes from the report and from the fetch timing logs. Run at the end of phase 4 against the `app` service of the local stack with the full database, again on the server in P6-02, and after schema changes. Results go to `docs/benchmarks.md`; P4-08's runs are in [The app under load](benchmarks.md#the-app-under-load-p4-08)

A failing scheduled task notifies by email through Coolify's notifications.

## 7. Deployment

| Piece | Where | Schedule |
| --- | --- | --- |
| Postgres 18 | Coolify database resource, `postgres:18.7-trixie`, pinned by the same digest as Compose and CI, persistent volume, not publicly exposed; its settings in `docker/db/postgresql.prod.conf` and its roles from the init scripts, `docker/db/server/00-owner.sh` first | Always on, from P6-02 |
| `jobs` container | Coolify application from the `prexp-app` image, command `sleep infinity` (Coolify's custom Docker options), owner and loader credentials, a volume at `/data/epd` for downloads. Runs `migrate()` after each deploy | Always on, from P6-02 |
| App container | Coolify application from `ghcr.io/katonometrica/prexp-app`, app role credentials only, a memory limit and a health check on `/`. From P6-02, on an unlisted subdomain with HTTPS | Redeployed on push to `main` |
| Loader | Coolify scheduled task in the `jobs` container, `prexp::load_latest()` | Daily from the 18th to the 28th at 02:00: loads a newly published month and reloads a re-published one, otherwise says there is nothing to do and exits 0 |
| Plan check | Coolify scheduled task in the `jobs` container, `prexp::migrate(); prexp::check_plans(max_ms = 150)` | Nightly at 04:00. It allows 150 ms a query, not 50: the server's cores are about half as fast as the development machine's (docs/benchmarks.md), and a plan that goes wrong fails whatever its time |
| v2 model fit | Called by `load_latest()`, `prexp::fit_variation_all()` | After each successful load |

**Hiding the app.** `X-Robots-Tag: noindex, nofollow` on every response, from Coolify's proxy (the domain's "Search engine indexing: Noindex"), `noindex` in the page head, and no links from the company site, the repository or the issues. There is no `robots.txt`: the proxy cannot serve one, and a rule that kept crawlers out would also keep them from seeing the noindex header, so a URL linked from elsewhere could still be listed. The certificate is Let's Encrypt's for the subdomain, so its name is in the public Certificate Transparency logs; noindex keeps it out of search engines. The address is shared privately, and never appears in the repository or its issues.

**Backups.** The data can be rebuilt from the source, so there is no database backup. `docs/runbook.md` documents a rebuild from an empty database: `migrate()`, `load_window()`, `check_plans(max_ms = 150)`. It took 64 minutes on the server (P6-02).

**Server.** Minimum 4 vCPU, 16 GB RAM, 100 GB SSD free for Postgres. Checked when it is provisioned (P6-02) and recorded in `docs/benchmarks.md`. Until then the full database runs locally (P1-08), inside Docker Desktop's virtual disk.

## 8. Repository conventions

- Public GitHub repository. Code under the MIT licence, copyright Katonométrica; data under the Open Government Licence 3.0, with the attribution in the README
- Issues in GitHub, one milestone per phase and one issue per ticket, titled with the ticket ID (`P1-07 · Build, check and swap a month`). The body holds the context, **Tasks** and **Done when**, with the estimate, dependencies and spec sections on its first line; dependencies are also recorded as "blocked by" relationships. Labels by type (`type:feature`, `type:chore`, `type:spike`, `type:test`, `type:docs`) and by area (`area:*`)
- `main` is protected by a ruleset: pull requests only, squash merges only, no force pushes or deletion, and CI must pass. Nobody bypasses it
- One pull request per ticket, on a branch `phase-N/<ticket id>-<short-name>`, with `Closes #<issue>`
- Tests ship in the same pull request as the code they test
- A ticket is done when every **Done when** box is ticked and CI is green
- Secrets only in `.env` locally, GitHub Actions secrets and Coolify. GitHub secret scanning and push protection are on
- No client names and no app URL in the repository or its issues

## 9. Work breakdown

The tickets are this repository's GitHub issues, one [milestone](https://github.com/katonometrica/prexp/milestones) per phase, each with tasks, a "done when" checklist, dependencies and an estimate. Each milestone's description is its exit criterion.

| Milestone | Tickets | Hours | Days |
| --- | --- | --- | --- |
| Phase 0 · Setup | 7 | 18 | 2 |
| Phase 1 · Data | 9 | 29 | 4 |
| Phase 2 · Scale | 6 | 24 | 3 |
| Phase 3 · Data layer | 4 | 16 | 2 |
| Phase 4 · App | 8 | 33 | 4 |
| Phase 5 · Reports | 8 | 32 | 4 |
| Phase 6 · Ship | 4 | 19 | 2 |
| Phase 7 · Write up | 2 | 8 | 1 |
| **v1** | **48** | **179** | **22** |
| v2 · Practice variation | 7 | 56 | 7 |
| **Total** | **55** | **235** | **29** |

At 10 hours a week, v1 is about 18 weeks and v2 about 6 more.

**Order.** The main sequence is P0-01 → P0-02 → P0-03 → P0-04 → P0-05 → P1-01 → P1-05 → P1-06 → P1-07 → P1-09 → P2-02 → P2-05 → P3-02 → P4-03 → P4-04 → P4-07 → P4-08 → P5-02 → P5-05 → P6-01 → P6-02 → P6-03. Work that can run alongside it:

- P0-07 can start on day one and must finish before P1-01
- P1-03 and P1-04 run alongside P1-01 and P1-02
- P2-03 and P2-04 can be written against the fixtures while P2-02 loads the full window locally
- P3-01 can start as soon as P0-05 is done
- P5-01 and P5-04 are pure functions and can start once P4-01 exists
- v2 starts after phase 6; V2-01 and V2-02 need only the full local database (P1-08)

## 10. v2: practice variation model

**Question.** For a group of drugs, which practices and ICBs prescribe more or less than expected given the patients they serve?

**Extra data, all open**

| Source | Gives | Join |
| --- | --- | --- |
| NHS England, Patients Registered at a GP Practice (monthly) | List size by age band and sex per practice | Practice code |
| NHS England, patients registered by LSOA (quarterly) | Where each practice's patients live | Practice code, LSOA |
| English Indices of Deprivation, latest release | Deprivation score per LSOA | LSOA, weighted by the practice's patients |
| ONS Rural Urban Classification | Rural or urban per LSOA | LSOA, weighted the same way |

**Groups.** One model per group. Prefixes follow the legacy BNF structure the dataset uses. P0-07 found that several prefixes also capture drugs the group does not mean (for example heart-failure diuretics in `0202`, INR test strips in `020802`) and that ADQ is undefined for whole classes; the proposals are in [dataset.md](dataset.md#v2-groups-findings-to-review-in-v2-03). V2-03 turns the table below into a reviewed lookup of chemical codes with inclusions, exclusions and reasons.

| Area | Group | BNF prefix | Outcome |
| --- | --- | --- | --- |
| Cardiovascular | Lipid lowering | `0212` | ADQ |
| Cardiovascular | Antihypertensives | `0204`, `020505`, `020602`, `0202` | ADQ |
| Cardiovascular | Oral anticoagulants | `020802` | Items |
| Diabetes | Insulins | `060101` | Items |
| Diabetes | Non-insulin antidiabetics | `060102` | Items (ADQ is 0 for 44% of items) |
| Respiratory | Inhaled bronchodilators | `0301` | Items |
| Respiratory | Inhaled corticosteroids and combinations | `0302` | Items |

**Model**

- Outcome per practice and month: items, or ADQ where the group uses it
- Items: negative binomial (`nbinom2`). ADQ: Tweedie, because ADQ is continuous rather than a count
- Offset `log(list size)`. Standardised covariates: shares aged 0 to 14, 65 to 74, 75 and over, and female; patient-weighted deprivation; rural share; month fixed effects
- Random intercepts for ICB and for practice within ICB, fitted with `glmmTMB`

**Outputs.** Per practice: observed; expected from the fixed effects only; their ratio; the within-ICB practice effect with a 95% interval. The same per ICB. Stored in `core.model_runs`, `core.model_variation` and `core.model_variation_icb`, read through `app.v_variation`.

**Interpretation.** Below expected is not automatically a problem: it can mean unmet need or good practice, such as avoiding overtreatment. The model shows where practices differ, not why, and the view, the exports and the methods page say so.
