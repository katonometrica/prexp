# Prescription Explorer: technical spec

How Prescription Explorer is built, at the level needed to write and work tickets. The goal and scope come first; the tickets are this repository's GitHub issues, one milestone per phase (section 9).

The source data's format and grain were checked in phase 0; the findings are in [dataset.md](dataset.md).

## Goal and scope

Prescription Explorer is an R Shiny app, built as the R package `prexp`, for exploring a rolling twelve months of NHS England prescribing data, about 200 million rows, with lookups answered in under 300 ms. Users explore through guided views, pin what they find, add notes, and export a report as PowerPoint, Word or Excel. The data is the English Prescribing Dataset (EPD) with SNOMED Code from the NHS Business Services Authority (NHSBSA), published monthly under the Open Government Licence 3.0.

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
| Rows loaded | About 200 million (twelve months) |

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
| `ci` | `base` | Google Chrome for `shinytest2`, added in phase 6 | GitHub Actions |
| `dev` | `base` | RStudio Server, `git`, and the development tools (`devtools`, `usethis`, `roxygen2`) from the same snapshot. The tools are never in `renv.lock` | Local development |
| `app` | `base` | The installed `prexp` package, port 3838, the non-root user `prexp`, `/data/epd` for downloads, `CMD Rscript -e "prexp::run_app()"` | The app and the `jobs` container in production, local smoke tests |

**Packages.** `renv.lock` is the only list of package versions. Every stage installs exactly those versions into R's site library, where every R process finds them, so the repository's renv files never switch libraries inside a container. To add a package: add it to `DESCRIPTION`, install it in the dev container, run `renv::snapshot()`, commit `DESCRIPTION` and `renv.lock`, and rebuild the images.

Images in the GitHub Container Registry:

- `ghcr.io/katonometrica/prexp-ci:<hash>`, where the hash covers `docker/Dockerfile` and `renv.lock`, so CI rebuilds it only when either changes
- `ghcr.io/katonometrica/prexp-app:main` and `:<commit sha>`, pushed from `main` only

### 2.2 Compose services, local development

`compose.yaml` at the repository root.

| Service | Image or build | Ports (host only) | Volumes | Notes |
| --- | --- | --- | --- | --- |
| `db` | `postgres:18.7-trixie`, pinned by digest | `127.0.0.1:5432` | `pgdata:/var/lib/postgresql`, `./docker/db/init` as init scripts, `./docker/db/postgresql.dev.conf` | Health check `pg_isready -h 127.0.0.1`, which only passes once the init scripts have finished (they run against a socket-only server). The PostgreSQL 18 image keeps data under `/var/lib/postgresql`, not `.../data` as in older versions. `shm_size: 1gb` for parallel queries |
| `rstudio` | build `docker/Dockerfile`, target `dev` | `127.0.0.1:8787` | Repository bind mount at `/home/rstudio/prexp`, `epd-downloads` at `/data/epd` | Starts after `db` is healthy. Gets database settings and all three role passwords from `.env`. Opens without a sign-in (`DISABLE_AUTH`), which is safe because the port is bound to `127.0.0.1` |
| `app` | build `docker/Dockerfile`, target `app` | `127.0.0.1:3838` | none | Compose profile `app`, so it only starts with `docker compose --profile app up`. Gets the app role's credentials only |

Named volumes: `pgdata`, `epd-downloads`. Monthly files (several GB each) go in `epd-downloads`, not the bind mount, because a Windows bind mount is slow for large files. Host ports can be changed in `.env` (`HOST_PORT_DB`, `HOST_PORT_RSTUDIO`, `HOST_PORT_APP`); they are always bound to `127.0.0.1`.

**Configuration.** `.env` holds the passwords and is in `.gitignore`. `.env.example` is committed with placeholder values. Variables: `POSTGRES_PASSWORD`, `PREXP_LOADER_PASSWORD`, `PREXP_APP_PASSWORD`, `PREXP_DB_HOST`, `PREXP_DB_PORT`, `PREXP_DB_NAME`, `PREXP_TEST_DB_NAME`, and the optional `HOST_PORT_*`. Passwords use letters and digits only, so they need no quoting anywhere. R reads the owner's password as `PREXP_OWNER_PASSWORD`, which Compose maps from `POSTGRES_PASSWORD`; CI and Coolify set it directly.

**Init scripts** in `docker/db/init/`, run once when `pgdata` is empty. CI runs the same scripts against its database service, with `bash` and `psql`.

1. `01-roles.sh`: creates the login roles `prexp_loader` and `prexp_app` with passwords from the environment, and the test database `prexp_test` owned by `prexp_owner`. Idempotent: a rerun only resets the passwords. It works whether the image's entrypoint executes or sources it, and by hand through the `PG*` variables. Passwords are passed as psql variables, never spliced into SQL. Committed with the executable bit
2. `02-database.sql`: sets `prexp_app` to read-only transactions, a 5 second `statement_timeout` and `jit = off`, as role settings, so they apply in every database

Everything else (schemas, tables, extensions, grants) is created by migrations (section 3.5), so local, CI and production databases are built the same way.

**Windows note.** Docker Desktop with the WSL 2 backend. The bind mount is fastest when the repository is cloned inside a WSL distribution; a clone on a Windows drive also works, provided only source code is on the bind mount and monthly files and the database stay in named volumes. `.gitattributes` keeps LF line endings, because containers read the working tree directly.

**Database configuration, development.** `docker/db/postgresql.dev.conf`, applied with `-c config_file=`. It first includes the `postgresql.conf` that initdb generated, so `listen_addresses` and the locale settings are kept, then sets small values for a laptop: `shared_buffers=1GB`, `work_mem=64MB`, `maintenance_work_mem=1GB`, `max_wal_size=8GB`, `jit=off`. Production values are set in phases 1 and 2 from the server's memory.

### 2.3 Production

The `app` image runs twice on the Coolify host: as the app, with the app role's credentials, and as the `jobs` container, with the owner's and loader's credentials, for migrations, loads, plan checks and model fits. PostgreSQL 18 runs on the same host from phase 1 and is never exposed outside the Docker network. Details in section 7.

## 3. Database

### 3.1 Roles and schemas

| Role | Can do | Used by |
| --- | --- | --- |
| `prexp_owner` | Owns every object, runs migrations | Migrations, and the loader's build and swap steps |
| `prexp_loader` | Writes `raw` and `core` (insert, update, delete, truncate), reads `raw`, `core` and `app` | Monthly loader (staging, dimensions, checks), model batch job, plan check |
| `prexp_app` | `SELECT` on schema `app` only, read-only, 5 second timeout, JIT off | The Shiny app |

Creating, attaching and detaching partitions needs ownership of the tables, which no grant can give. So the loader's build and swap steps (section 4, steps 6 and 8) run on an owner connection, which the `jobs` container already has; everything else runs as `prexp_loader`. `meta` is the owner's alone.

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

**`core.dim_chemical`**: `chemical_id` (identity), `chemical_code` (unique, the source's `BNF_CHEMICAL_SUBSTANCE_CODE`: 9 characters, or 4 for appliance chapters 20 to 23), `chemical_name`. Trigram GIN index on `chemical_name`.

**`core.dim_presentation`**: `presentation_id` (identity), `bnf_code` (unique), `bnf_description`, `chemical_id`, `bnf_chapter`, `bnf_section`, `bnf_paragraph`, `is_generic` (characters 10 and 11 of the BNF code are `AA`; null for appliance chapters 20 to 23), `first_seen`, `last_seen`. No SNOMED code: a presentation can have several. Trigram GIN index on `bnf_description`.

**`core.dim_practice`**: `practice_id` (identity), `practice_code` (unique), `practice_name`, `address`, `postcode`, `icb_code`, `icb_name`, `region_code`, `region_name`, `is_unidentified`, `first_seen`, `last_seen`. Trigram GIN index on `practice_name`. Name, ICB and region take the latest month's values, so every month shows today's geography (ICBs were reorganised in April 2026). `is_unidentified` marks the 'UNIDENTIFIED DOCTORS' codes, including the national code `-`; their rows stay in the fact table so totals reconcile.

**Rollups**, all rebuilt one month at a time by the loader:

| Table | Grain | Serves |
| --- | --- | --- |
| `core.agg_presentation_month` | Presentation × region × month | Drug series at presentation level, without touching the fact table |
| `core.agg_chemical_month` | Chemical × region × month | Drug series at chemical level, regional comparison |
| `core.agg_practice_month` | Practice × month | Practice monthly totals |

**`core.load_log`**: `year_month`, `source_url`, `source_sha256`, `source_rows`, `loaded_rows`, `file_bytes`, `started_at`, `finished_at`, `status` (`running`, `loaded`, `failed`, `dropped`), `error`. The current window is the first and last month with status `loaded`.

**`raw.epd_staging`**: unlogged, every column `text`, matching the source header exactly. Truncated at the start of each load.

### 3.3 App views

| View | Reads | Used by |
| --- | --- | --- |
| `app.v_window` | `load_log` | Date range, cache key |
| `app.v_chemical` | `dim_chemical` | Search, labels |
| `app.v_presentation` | `dim_presentation` + `dim_chemical` | Search, labels |
| `app.v_practice` | `dim_practice` | Search, labels |
| `app.v_presentation_month` | `agg_presentation_month` + dimensions | Drug view, presentation level |
| `app.v_chemical_month` | `agg_chemical_month` + dimensions | Drug view, chemical level; region view |
| `app.v_practice_month` | `agg_practice_month` | Practice view, totals |
| `app.v_practice_presentation` | `prescribing` + `dim_presentation` | Practice view, top drugs |
| `app.v_variation` (v2) | `model_variation` + dimensions | Variation view |

### 3.4 Size estimate

After aggregation about 9.5 million fact rows per month. At about 90 bytes per row including overhead, that is about 0.9 GB of table per month and about 1 GB of indexes. Twelve months: roughly 23 GB, plus 5 to 10 GB while a month is staged, plus the next month being built before the oldest is dropped. **Plan for at least 80 GB free disk for Postgres.** P1-09 replaces this estimate with measured numbers.

### 3.5 Migrations

Numbered SQL files in `inst/sql/migrations/` (`001_schemas.sql`, `002_dimensions.sql`, ...), applied in order by `prexp::migrate()` as `prexp_owner`, each in its own transaction, recorded with a checksum in `meta.schema_migrations`. Applied files are never edited; changes are new files, and a changed checksum stops `migrate()`. CI applies all migrations to an empty database on every run, and the `jobs` container runs `migrate()` after every deploy.

- `migrate()` with no arguments connects as the owner; it refuses to run as any other role
- A per-database advisory lock stops two runs at once
- Checksums ignore line endings and a byte-order mark, so Windows and Linux checkouts agree
- Before applying anything, it stops if an applied file has changed or is missing, or if a pending file is numbered below the last applied one
- Each file is sent in one call (RPostgres's simple query protocol) inside its own transaction, so files must not contain `BEGIN`, `COMMIT` or commands that cannot run in a transaction

## 4. Monthly loader

Entry points:

- `prexp::load_month(year_month)`: loads or reloads one month
- `prexp::load_latest()`: loads the newest published month not yet loaded, or does nothing. This is what the schedule calls
- `prexp::load_window(n = 12)`: loads the `n` most recent published months missing from `load_log`, oldest first. Used for the first load and for rebuilds

A Postgres advisory lock stops two loads from running at once. The window size comes from `PREXP_WINDOW_MONTHS`, default 12.

**Steps**

| Step | What | Detail |
| --- | --- | --- |
| 1. Find | Look up the month's file | The NHSBSA open data portal runs CKAN: `package_show` for the dataset lists one resource per month, named `EPD_SNOMED_YYYYMM`. Resource ids are random, so the month is found by name. Its `sha256` is recorded; months are sometimes re-published, and a changed hash means the month is reloaded |
| 2. Download | Fetch the ZIP into `epd-downloads` | The ZIP (about 0.67 GB against 7.7 GB for the CSV) is only offered through the resource's `zip_url`, a signed link valid for one hour, so the metadata is fetched again just before each attempt. Without a `zip_url`, the CSV (`url`) is downloaded instead. Written to a `.part` file and renamed when complete. Skipped if a complete file is already there |
| 3. Validate header | Compare the CSV header with `inst/extdata/epd_columns.csv` | Read as the first line of `bsdtar -xOf`. Any difference stops the load with a message listing the differences |
| 4. Stage | Stream into `raw.epd_staging` | `bsdtar -xOf file.zip \| psql -c "\copy raw.epd_staging FROM STDIN CSV HEADER"` under `bash -o pipefail`, with the stream's SHA-256 computed on the way and compared with the resource's `sha256`. `bsdtar` (libarchive), because Ubuntu's `unzip` cannot read these archives and silently outputs nothing. Streaming avoids unpacking a multi-GB file to disk and avoids loading it into R |
| 5. Dimensions | Upsert chemicals, presentations and practices | `INSERT ... ON CONFLICT DO UPDATE`. Names are only overwritten by a month at least as recent as `last_seen` |
| 6. Build | Create `core.prescribing_YYYYMM_new` as a plain table, insert from staging joined to the dimensions and grouped by practice and presentation (sums of the measures; `ADQ_USAGE` of 0 becomes NULL), add `CHECK (year_month = YYYYMM)`, build both indexes, `VACUUM (ANALYZE)` | Done outside the partitioned table, so the live data is untouched while it builds |
| 7. Check | Staging rows against the `COPY` count; new table rows against the distinct practice × presentation pairs in staging; `sum(items)`, `sum(nic)` and `sum(actual_cost)` of the new table against staging | Any mismatch stops the load. The live data is still untouched |
| 8. Swap | One transaction, `lock_timeout` 10 s, retried: detach and drop the existing partition for that month if any, rename and attach the new table, rebuild that month in the three rollups, drop the oldest partition and its rollup rows if the window is exceeded, update `load_log` | The `CHECK` constraint makes the attach instant. Detaching briefly locks the parent, so app queries may wait a moment |
| 9. Clean | Truncate staging. Delete the ZIP | |

Rerunning a month rebuilds and swaps it, which makes the loader idempotent. A failure before step 8 changes nothing in `core`. A failure inside step 8 rolls back. Loading a month older than a full window is refused. Dimension rows are never deleted, so shared links never point at a missing key.

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
│   ├── fct_loader.R           load_month(), load_latest(), load_window()
│   ├── fct_plan_check.R       check_plans()
│   ├── mod_search.R, mod_drug.R, mod_practice.R, mod_region.R, mod_report.R
│   ├── theme.R                palette, bslib, ggplot2 and mschart themes
│   └── utils_validate.R, utils_format.R, utils_log.R
├── inst/
│   ├── sql/migrations/, sql/load/, sql/queries/
│   ├── templates/report.pptx, report.docx
│   ├── extdata/epd_columns.csv   expected source header
│   └── app/www/                  CSS, search.js
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
| `fetch_search_drugs()` | `q`, `limit = 20` | Chemicals and presentations matching by name or BNF code prefix | `v_chemical`, `v_presentation` |
| `fetch_search_practices()` | `q`, `limit = 20` | Practices matching by name or code | `v_practice` |
| `fetch_drug_series()` | `level` (chemical or presentation), `id`, `months`, `measure` | Monthly national totals | `v_chemical_month` or `v_presentation_month` |
| `fetch_drug_presentations()` | `chemical_id`, `months` | Totals per presentation, brand or generic | `v_presentation_month` |
| `fetch_practice_profile()` | `practice_id` | Name, address, ICB, region | `v_practice` |
| `fetch_practice_series()` | `practice_id`, `months` | Monthly totals | `v_practice_month` |
| `fetch_practice_top_drugs()` | `practice_id`, `months`, `by` (items or cost), `limit`, `after` (keyset) | Top presentations, paged | `v_practice_presentation` |
| `fetch_region_comparison()` | `level`, `id`, `months`, `measure`, `per` (total, or per 1,000 patients in v2) | Totals per region | `v_chemical_month` or `v_presentation_month` |
| `fetch_variation()` (v2) | `group`, `icb_code` | Observed, expected, ratio, interval per practice | `v_variation` |

Quantity is only valid for a single presentation, because units differ across presentations.

Each query is registered in `fct_query_registry.R` with two sample argument sets, large and small (for example a widely prescribed statin and a rarely prescribed drug), looked up by code at run time. `check_plans()` runs `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` for every entry and fails on any sequential scan of a `core.prescribing` partition or any execution over 50 ms.

### 5.3 Screens

`bslib::page_navbar` with five tabs. The footer on every tab shows the data window and the NHSBSA attribution. The page head carries `noindex, nofollow`.

| Tab | Inputs | Shows | Pinnable |
| --- | --- | --- | --- |
| Drug | Search (chemical or presentation), month range, measure | Monthly series chart; presentations table with brand or generic | Yes |
| Practice | Search, month range, measure | Profile, monthly totals chart, top drugs table | Yes |
| Region | Drug search, month range, measure | Bar chart and table by region | Yes |
| Report | none | Pinned items with notes, reorder, remove, copy link, three export buttons | n/a |
| About | none | Methods, data source, licence, limitations | n/a |

Every view handles three states besides the normal one: nothing selected, no rows, and query error. Each shows a message rather than an empty chart.

### 5.4 Runtime

- `pool` created once per process as `prexp_app`. The app refuses to start unless its connection is read-only
- Search uses selectize with remote loading: a small script sends typed text to the server, which ignores fewer than two characters, debounces at 300 ms, and sends back up to 20 matches from `fetch_search_*()`
- Tables use `reactable`, the one table library in the app
- `bindCache()` on every fetch-backed reactive, keyed on the arguments plus the window from `fetch_window()`, with an app-wide `cachem::cache_mem()` of 200 MB
- Exports and any fetch expected over 100 ms run in `ExtendedTask` on two `mirai` daemons. Each daemon opens its own connection, because a pool cannot be shared across processes
- Every fetch logs one JSON line to stdout: function, hash of the arguments, rows, milliseconds. Used for the p95 figure and for spotting slow queries in production

### 5.5 Reports

**Flow.** Explore a guided view, press "Add to report" to pin it with its current selections, write a note under it, then reorder or remove items in the report panel. When ready, export.

**Report spec.** A report is an ordered list of items, each with a view type, its parameters (drug, practice, region, months) and a note. Items store parameters, not data, so an export re-runs the queries and stays consistent with the database.

**Shareable link.** The report is encoded in the URL with Shiny URL bookmarking. Opening the link restores the selections, pinned items and notes; nothing is stored on the server. Notes are capped at 500 characters and reports at 15 items, to keep links within browser URL limits. Because the window rolls, a link can name months that have since been dropped: on restore those items are clamped to the current window and flagged in the report panel, rather than failing.

**Contents of every export.** A title page with the data period and export date; one section per pinned item with its chart, table and note; and a methods section with the data source and period, the filters applied per item, measure definitions, and the NHSBSA attribution with the Open Government Licence 3.0.

| Format | Built with | Charts | Layout |
| --- | --- | --- | --- |
| PowerPoint | `officer` + `mschart` on `report.pptx` | Native Office charts, editable | One slide per item, methods as the last slide |
| Word | `officer` + `mschart` on `report.docx` | Native Office charts, editable | One section per item, methods as an appendix |
| Excel (`.xlsx`) | `openxlsx2` + `mschart` | Native Excel charts | One sheet per item, methods as the last sheet. No macros, so it opens without security warnings. Built in R, with no template |

Implementation notes:

- The report spec is a list of items `{id, view, params, note}`. Pure functions in `fct_report_spec.R` add, remove, move, validate and clamp it, and encode it for the URL (compact JSON, gzip, base64url)
- `enableBookmarking("url")` stores only the active tab, the active view's selections and the encoded spec. Limits: 15 items, 500 characters per note, which keeps the worst case under 8,000 characters
- On restore, `clamp_report(spec, window)` limits each item's months to the current window and marks changed items `clamped`, which the report panel shows
- Exports run each item's fetch again, build charts with `mschart` using `theme.R`, and add `fct_methods.R` content last. They run as an `ExtendedTask`: "Prepare", then "Download"
- PowerPoint: one slide per item (title, chart, note), with the table on a following slide if it has more than 12 rows. Word: one heading per item, chart, note, table. Excel: one sheet per item with the note in the first rows, an Excel table and a native chart; Methods sheet last; no macros, no pivots

## 6. Testing and CI

### 6.1 Test database

Tests use the `prexp_test` database with all migrations applied and the fixture months loaded by the real loader. The fixtures are about 5,000 rows sampled from one real month (every row for about ten practices, covering the v2 groups, brands and generics, a rare drug and a presentation with no ADQ), repeated as thirteen synthetic months with scaled measures, so the rolling drop can be tested. Expected values come from an independent `dplyr` aggregation of the fixture files, never from the code under test. Fetch tests connect as `prexp_app`, so they also prove the grants. `local_test_db()` skips a test with a clear message when no database is reachable, so pure tests still run anywhere; in CI, where `PREXP_TEST_DB_REQUIRED=true`, it fails instead, so a broken database setup cannot pass as skipped tests. Migration tests each create a temporary database from `template0` and drop it afterwards, because migrations create schemas, extensions and default privileges.

### 6.2 Workflow `ci.yaml`, on every pull request and push to `main`

1. Job `image`: the tag is the hash of `docker/Dockerfile` and `renv.lock` plus the month. It builds and pushes `ghcr.io/katonometrica/prexp-ci:<tag>` only if that tag does not exist yet, passing the month as the build argument `OS_REFRESH`, so the OS layer (`apt-get upgrade`) is rebuilt monthly instead of being frozen by the build cache. Otherwise every run reuses the stored image, so a new image is built only when a package or the Dockerfile changes, or the month turns. Each build writes its own registry cache, and a shared one for the next build. Pull requests from forks cannot push, so a fork that needs a new image gets a clear failure
2. Job `test` runs in that image with a `postgres:18.7-trixie` service (the same digest as Compose), after creating the roles with the same init scripts as Compose. It runs even when `image` fails or the run is cancelled (`always()`), and then fails itself, because GitHub treats a skipped required check as passed
3. Install the package, then `lintr::lint_package()`, failing on any lint
4. `prexp::migrate()` on the empty service database and on the test database
5. Tests and coverage in one run. The gate: 85% overall, and no package function with zero coverage, so deleting any test that is a function's only coverage fails CI. The `coverage/` report is uploaded as an artifact
6. `shinytest2` flows (from phase 6), not counted in coverage
7. Jobs `app-image` (pull requests, read-only token) and `app-publish` (`main` only): build the `app` image from the tested CI image's cache and check that `library(prexp)` loads. `app-publish` pushes `:<commit sha>`, and moves `:main` only while the commit is still the tip of `main`, so re-running an old run cannot roll it back; from phase 6 it then calls the Coolify deploy webhook

Triggers: pull requests, pushes to `main`, a monthly schedule on the 1st (which publishes the refreshed image) and manual runs. Third-party actions are pinned to commit SHAs and updated by Dependabot, with a seven-day cooldown on new releases; the BuildKit image is pinned by digest and updated by hand, because the image jobs hold a token that can push packages. The required check is strict: a pull request must be up to date with `main` before it merges. The container packages stay private until P1-08, when the server has to pull them; jobs log in with `GITHUB_TOKEN`.

### 6.3 Checks that need the full database

The 200 million row database exists only on the server, from phase 1 on, so these run there, not in GitHub Actions:

- `prexp::check_plans()`: during phase 2 by hand, then nightly as a Coolify scheduled task
- The p95 benchmark: `shinyloadtest` records a session of searches and view changes, `shinycannon` replays it with 5 concurrent users, and p95 comes from the report and from the fetch timing logs. Run at the end of phase 4 against a private staging deployment on the server, and after schema changes. Results go to `docs/benchmarks.md`

A failing scheduled task notifies by email through Coolify's notifications.

## 7. Deployment

| Piece | Where | Schedule |
| --- | --- | --- |
| Postgres 18 | Coolify database resource, persistent volume, not publicly exposed | Always on, from phase 1 |
| `jobs` container | Coolify application from the `prexp-app` image, command `sleep infinity`, owner and loader credentials, `epd-downloads` volume. Runs `migrate()` after each deploy | Always on, from phase 1 |
| App container | Coolify application from `ghcr.io/katonometrica/prexp-app`, app role credentials only. Private staging in phase 4, then an unlisted subdomain with HTTPS | Redeployed on push to `main` |
| Loader | Coolify scheduled task in the `jobs` container, `prexp::load_latest()` | Daily from the 18th to the 28th at 02:00, does nothing if no new month is published |
| Plan check | Coolify scheduled task in the `jobs` container, `prexp::check_plans()` | Nightly at 04:00 |
| v2 model fit | Called by `load_latest()`, `prexp::fit_variation_all()` | After each successful load |

**Hiding the app.** `X-Robots-Tag: noindex, nofollow` on every response through a proxy middleware, `noindex` in the page head, a `robots.txt` that disallows everything if the proxy can serve it, and no links from the company site, the repository or the issues.

**Backups.** The data can be rebuilt from the source, so there is no database backup. `docs/runbook.md` documents a rebuild from an empty database: `migrate()`, `load_window()`, `check_plans()`. The rebuild time is estimated from the phase 2 load timings.

**Server.** Minimum 4 vCPU, 16 GB RAM, 100 GB SSD free for Postgres. Checked in phase 0 (P0-07) and recorded in `docs/benchmarks.md` in P1-08.

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
| Phase 1 · Data | 9 | 30 | 4 |
| Phase 2 · Scale | 6 | 24 | 3 |
| Phase 3 · Data layer | 4 | 16 | 2 |
| Phase 4 · App | 8 | 33 | 4 |
| Phase 5 · Reports | 8 | 32 | 4 |
| Phase 6 · Ship | 4 | 14 | 2 |
| Phase 7 · Write up | 2 | 8 | 1 |
| **v1** | **48** | **175** | **22** |
| v2 · Practice variation | 7 | 56 | 7 |
| **Total** | **55** | **231** | **29** |

At 10 hours a week, v1 is about 18 weeks and v2 about 6 more.

**Order.** The main sequence is P0-01 → P0-02 → P0-03 → P0-04 → P0-05 → P1-01 → P1-05 → P1-06 → P1-07 → P1-09 → P2-02 → P2-05 → P3-02 → P4-03 → P4-04 → P4-07 → P4-08 → P5-02 → P5-05 → P6-01 → P6-02 → P6-03. Work that can run alongside it:

- P0-07 can start on day one and must finish before P1-01
- P1-03 and P1-04 run alongside P1-01 and P1-02
- P2-03 and P2-04 can be written against the fixtures while P2-02 loads data on the server
- P3-01 can start as soon as P0-05 is done
- P5-01 and P5-04 are pure functions and can start once P4-01 exists
- v2 starts after phase 6; V2-01 and V2-02 need only the server database (P1-08)

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
