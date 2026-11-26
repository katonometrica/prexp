# prexp (development version)

- **KATONOMETRICA's look** (#129, the app's part): the app looks like katonometrica.com. Dark by default, with a light theme and a button that switches it and is remembered; IBM Plex Sans and Mono, served with the app; the brand's navy and gold, square corners and flat surfaces. The charts take the theme's colours without being drawn again. Where the site's colours fall short of WCAG AA, the app uses stronger ones.
- **The exports in KATONOMETRICA's look** (#129, the exports' part): the PowerPoint, Word and Excel files take the brand's light colours, the app's chart colours among them, and IBM Plex Sans. An Office file cannot carry the font, so their themes name it with IBM's classification of it, and Office draws a sans of its own where it is not installed; slides and tables are measured in both Plex and Arial, so that they fit either, and a table of 24 or 25 rows now has its rows split evenly over two slides. The templates' colour schemes are the brand's, for anything a reader adds, and the cover and the title page carry the KATONOMETRICA wordmark, linked to katonometrica.com.
- **One message for each lookup** (#125): a view's results are drawn again only when their layout changes, and each chart once, at the width the browser reports. The shared cache keeps drawn charts as well as fetches.
- **Deploys from CI** (#118): a merge to `main` that publishes a new app image deploys the app and the jobs container to production.
- **The server's measurements** (#124), in `docs/benchmarks.md`, and again after #125: lookups at 141 ms at the median and 540 ms at the 95th percentile (569 ms before), and 699 ms for the largest chemical (957 ms before). The load test's sessions are recorded again by `bench/drive.R`.
- **The README and the architecture page:** how the project was built, specification first; a diagram that can be read at the page's width; the techniques table brought up to date. The screenshots, the badges and the diagram in KATONOMETRICA's look (#129).

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
