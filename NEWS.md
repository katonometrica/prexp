# prexp 0.1.0

The first release: Prescription Explorer in production, over a rolling twelve months of the English Prescribing Dataset (EPD) with SNOMED codes.

## The app

- **Three views,** each with a search box: a drug (a chemical substance or one of its presentations), a practice, and a drug compared across England's regions. Each has a chart, a table and a CSV download, in items, ADQ usage, net ingredient cost or actual cost.
- **A report:** pin views with notes, export them to PowerPoint, Word or Excel, and share a link that opens the report again.
- **The attribution** on every page and in every export, and a link to this repository.

## The data

- **A monthly load from NHSBSA's open data portal.** Each month is downloaded, staged, aggregated beside the live data, checked against staging, and swapped in in one transaction, which drops the oldest month. A month the portal publishes again is reloaded.
- **PostgreSQL 18:** one partition a month, covering indexes, and rollup tables for the app's views, built by numbered SQL migrations.

## Quality

- **Tests** against a database the real loader builds from real EPD rows (eight prescribers from one real month, repeated as thirteen months with scaled measures), checked against totals computed independently, browser flows with shinytest2, and an 85% coverage gate in CI.
- **`check_plans()`** checks each of the app's queries for index-only reads, pruned partitions and its time, nightly in production; `docs/benchmarks.md` has the measurements.

## Running it

- **A demo in one command,** with Docker: the published image, PostgreSQL and the test fixtures.
- **Production on Coolify,** with the scheduled monthly load and the nightly check; `docs/server.md` sets it up, failure emails and deploys from CI included, and `docs/runbook.md` operates it.
