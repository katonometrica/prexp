# Architecture

How Prescription Explorer is built, and why: each decision below names what it costs. The full design is in [spec.md](spec.md), and every number here comes from [benchmarks.md](benchmarks.md).

## The problem

The English Prescribing Dataset (EPD) publishes each month as one CSV of about 18 million rows, 7.7 GB, around the 20th of the second month after it. A row is a practice's prescriptions of one product in one quantity per item. The app answers questions across a rolling twelve months: a drug's national series and its presentations, a practice's top drugs, a drug compared across the regions. That is about 220 million source rows, which a lookup must not read.

![How it fits together: the NHSBSA portal; a jobs container that loads each month into PostgreSQL 18 and checks every query's plan nightly; and the app container, which reads the database's views through a query registry and a shared cache, runs exports on mirai workers, which read the views over their own connections, and answers the browser through an HTTPS proxy](images/architecture.svg)

## The data layer

**Aggregate on load.** The app never needs a row's product and quantity per item, so the loader sums each month to one row per practice and presentation: 9.5 million rows instead of 18.4 million, with the measures in exact `numeric`, so the load reconciles to the penny. *Cost:* the source's finest grain is not kept; a question that needs it means loading the months again.

**Rollups for the views.** The Drug and Region views read two small tables, the presentation and chemical rollups by region and month, and the Practice view's monthly totals read a third, by practice and month. The loader builds them one month at a time, so only a practice's top drugs reads the fact table. *Cost:* the loader does more work, about a third of each month's build, and every measure must be one that can be added at the rollup's grain.

**A partition a month, with covering indexes.** Each month is a partition of the fact table, with two covering indexes, so a lookup is an index-only scan over the partitions it needs, and the oldest month leaves the window by dropping a partition, not by deleting 9.5 million rows. *Cost:* an index-only scan needs the visibility map set, so the loader vacuums each new partition, and both indexes are built for every month.

**An atomic month swap.** A month is built as a table beside the live data, checked against the staged source (row counts, item and cost totals), then swapped in one transaction: the dimensions, the three rollups, the partition, the load log, and the oldest month dropped. The app sees the whole month or none of it, a failed load changes nothing, and loading a month again is how a re-published month is fixed. *Cost:* a month takes about twice its space while it loads, and the build and check take longer than a direct insert.

## The app

**SQL in files, through a registry.** Each of the app's fifteen queries is one file in `inst/sql/queries/`, read through a registry that also holds its parameters and test samples. The fetch functions and the plan check run the same files, so the SQL that is checked is the SQL the app runs, and values are always bound as parameters, never pasted into SQL. *Cost:* no R-side composition, as dbplyr offers: a new query is written, and tuned, as SQL.

**Plans checked, not assumed.** `check_plans()` runs every query with its largest and smallest samples and fails on a read that is not index-only, on partitions not pruned, on heap fetches, or on time. It runs on the full twelve months, and nightly in production, so a plan that goes wrong surfaces before a user notices. *Cost:* time limits depend on the machine (50 ms on the development machine, 150 ms on the server), and a small database can only report, since a sequential scan is the right plan there.

**A cache around the fetches and the charts, shared by every session.** A fetch another session made is answered from memory, and so is a chart it drew, keyed on the data's window, so a new month starts afresh. It wraps the fetch functions and the drawing of the charts rather than using Shiny's `bindCache()`, which would keep one session's passing error and serve it to every session. *Cost:* memory: the cache counts a chart as about 40 KB, so its 200 MB holds about 5,000, fewer with the fetches it also keeps. And a lookup no one has made yet still draws its chart, which on the server is most of its time.

**One message for each lookup.** A view's results sit in a frame that is drawn again only when its layout changes, such as another message or a chemical substance's presentations table appearing. Otherwise only the chart and table in it change. They are computed with the frame rather than once the browser reports them shown. The chart is drawn at the body's width, which the browser reports before any pick. So a lookup is one round trip, and a chart is drawn once, not again when a long table gives the page a scroll bar. *Cost:* the chart is drawn again only when the width moves by 30 px or more, and is scaled to fit until then, by up to about 3%.

**Exports in background workers.** A 15-item PowerPoint export takes about three seconds; in the app's process it would freeze every session meanwhile. Exports run on two `mirai` workers as Shiny `ExtendedTask`s, each worker with its own database connection. *Cost:* each worker holds its own memory, up to about 170 MB more after a large export, and two workers cap how many exports run at once.

**A read-only login.** The app connects as a role that can only read the app's views, and refuses to start with a login that can write or reach the loader's tables. The loader and the migrations have roles of their own. *Cost:* three passwords to manage, and a migration must grant the app what it reads.

## Quality

**Tests on real data.** The tests run against a database the real loader builds from the fixtures: every row of eight prescribers across all seven regions, and a sample of the national unidentified prescriber, from one real month, repeated as thirteen months with scaled measures, so the window's monthly drop is tested too. They compare what the app shows with totals computed independently from the fixture files. Browser flows drive the app in Chrome with shinytest2. CI fails below 85% line coverage, and also on any function no test reaches. *Cost:* the tests need PostgreSQL, so CI runs one as a service, and building the fixture database adds about 8 seconds to a run.

**One image, pinned.** CI builds its image from `docker/Dockerfile` and `renv.lock`, tagged by their hash, so the tests, the development stack and production run the same R packages; third-party actions are pinned to commit SHAs. *Cost:* a package update is a rebuild of the image.

## Running it

**One small server, rebuilt rather than backed up.** Production is the database, a `jobs` container and the app, under Coolify on a shared server with 4 CPUs and 15 GB. Everything in the database comes from the portal, so it is rebuilt, in 64 minutes, instead of backed up. A scheduled task loads each new month, a nightly one runs the migrations and the plan check, and a failure emails. *Cost:* if the database is lost, the app is down for about an hour.

**Performance, measured.** With five users replaying a recorded session against the server, measured from outside with the network included, lookups take 141 ms at the median and 540 ms at the 95th percentile, and 699 ms for the chemical with the most presentations. Before one message for each lookup, they took 569 and 957 ms at the 95th percentile. What sets the 95th percentile now is opening a session, about half a second on the server, whose cores are about half as fast as the development machine's for this work. Opening took about 0.4 s before one message for each lookup, which computes every view's charts and tables as a session opens, shown or not. The database's part is small: the time is the app's own work in R.

## Techniques and where they are

Every technique the project uses, with the files that show it. The [README](../README.md#what-sets-the-engineering-apart) picks out five.

| Technique | Where |
| --- | --- |
| A Shiny app as an R package: modules (`mod_*`) for the views, plain functions (`fct_*`, `utils_*`) for the logic | [R/](../R/) |
| SQL kept in files: numbered, checksummed migrations, and one file per query | [inst/sql/](../inst/sql/), [R/db.R](../R/db.R) |
| A query registry: the app and the plan checks run the same SQL files, with parameters, never with values pasted in | [R/fct_query_registry.R](../R/fct_query_registry.R), [R/fct_queries.R](../R/fct_queries.R) |
| ETL from NHSBSA's CKAN API: download, stage, aggregate beside the live data, check against staging, and swap a month in one transaction | [R/fct_source.R](../R/fct_source.R), [R/fct_loader.R](../R/fct_loader.R), [inst/sql/load/](../inst/sql/load/) |
| Aggregated on load: a month's 18.4 million source rows become 9.5 million, one per practice and presentation, with the measures in exact `numeric` | [inst/sql/load/build_month.sql](../inst/sql/load/build_month.sql) |
| A partition a month with covering indexes, and rollup tables, so a lookup reads index entries and pre-aggregated rows | [inst/sql/migrations/](../inst/sql/migrations/), [inst/sql/load/swap_month.sql](../inst/sql/load/swap_month.sql) |
| Every query's plan checked: it fails on a fact-table read that is not index-only, on partitions not pruned, on heap fetches, or on time, over the full twelve months and nightly in production | [R/fct_plan_check.R](../R/fct_plan_check.R), [tests/testthat/test-plan-check.R](../tests/testthat/test-plan-check.R) |
| A read-only login: every pooled connection is checked, and the app stops if its login can write, is a superuser, or can use the loader's schemas | [R/db.R](../R/db.R) (`check_read_only()`) |
| One message for each lookup: a view's results are drawn again only when their layout changes, and each chart once, at the width the browser reports | [R/utils_view.R](../R/utils_view.R), [R/mod_drug.R](../R/mod_drug.R) |
| A cache shared by every session, for fetches and drawn charts, keyed on the data's window. It wraps the fetch functions instead of using `bindCache()`, so one session's passing error is never served to the others | [R/fct_cache.R](../R/fct_cache.R) |
| Exports on two `mirai` workers as `ExtendedTask`s, each with its own database connection, so a 15-item PowerPoint export (about 3 s) holds up no other session | [R/fct_workers.R](../R/fct_workers.R) |
| Charts with text alternatives, in the app and in the native charts of the PowerPoint, Word and Excel exports | [R/fct_charts.R](../R/fct_charts.R), [R/fct_export_pptx.R](../R/fct_export_pptx.R) |
| Tests on a database the real loader builds from real rows, checked against totals computed independently from the fixture files; browser flows with shinytest2 | [tests/testthat/helper-oracle.R](../tests/testthat/helper-oracle.R), [tests/testthat/e2e-flows.R](../tests/testthat/e2e-flows.R) |
| CI: an image tagged by the hash of the Dockerfile, `renv.lock` and the month; lint, migrations, tests, two coverage gates (85% of lines, and no function without a test) and the browser flows; then the app image published and production deployed. Actions pinned to commit SHAs | [.github/workflows/ci.yaml](../.github/workflows/ci.yaml) |
| Measured performance: load times, query plans, and the 95th percentile of lookups with five users replaying recorded sessions, on the development machine and on the server | [docs/benchmarks.md](benchmarks.md) |
| Production on one shared server under Coolify: a scheduled monthly load, a nightly migration and plan check, failure emails, and a deploy from CI on every merge | [docs/server.md](server.md), [docs/runbook.md](runbook.md) |
| The data's attribution on every page and in every PowerPoint, Word and Excel report | [R/fct_methods.R](../R/fct_methods.R) |
